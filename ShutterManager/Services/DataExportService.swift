//
//  DataExportService.swift
//  ShutterManager
//
//  Exports the library as a package (everything, photos included, in one zip), JSON (the
//  records), CSV (the inventory, for spreadsheets) or a PDF inventory report. Money stays
//  Decimal in the store and Double on the JSON wire.
//

import Foundation
import SwiftUI
import CoreText
import SwiftData
import os

@MainActor
final class DataExportService {
    private let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "DataExportService")

    /// Where exported settings are read from. Injectable so a backup taken with a scratch
    /// `BackupManager` suite (tests) reads the same store its restore writes.
    private let settingsStore: UserDefaults

    /// How many NaN/±∞ or out-of-range values the most recent export wrote as defaults
    /// (see `LibraryExport.replaceUnrestorableNumbers()`). 0 when there were none.
    private(set) var lastReplacedValueCount = 0

    /// Whether the most recent package left its photos out because they made the file too large
    /// (see `ExportConfiguration.dropsPhotosIfTooLarge`).
    private(set) var lastExportDroppedPhotos = false

    /// The largest JSON file an export may write: what import and restore will read.
    private let maximumBytes: Int
    /// The largest package an export may write.
    private let maximumPackageBytes: Int
    /// How many photos go into a package at a time.
    private let photoBatch: Int

    init(settingsStore: UserDefaults = .standard, maximumBytes: Int = Constants.DataLimits.maximumImportBytes,
         maximumPackageBytes: Int = Constants.DataLimits.maximumPackageBytes,
         photoBatch: Int = Constants.DataLimits.packagePhotoBatch) {
        self.settingsStore = settingsStore
        self.maximumBytes = maximumBytes
        self.maximumPackageBytes = maximumPackageBytes
        self.photoBatch = max(photoBatch, 1)
    }

    struct ExportConfiguration {
        var includeGear = true
        /// Maintenance history and reminders, from each gear item's relationships.
        var includeMaintenance = true
        var includeShutterCounts = true
        var includeLoans = true
        /// Development recipes and their steps (JSON only; CSV and PDF list gear).
        var includeDevelopmentRecipes = true
        /// Saved places (JSON only).
        var includeSavedPlaces = true
        /// Shoots with their shot lists, kits, shot-list templates and film rolls (JSON only).
        var includeShoots = true
        var includePhotos = true
        var includeSettings = true
        /// For a package: when the photos make the file too large to read back, write it without
        /// them instead of failing. For backups, where records without photos beat no backup.
        var dropsPhotosIfTooLarge = false
        var format: ExportFormat

        var hasAnyDataSelected: Bool { includeGear || includeSettings }
    }

    // MARK: - Export

    /// Writes a JSON or CSV file to the temporary directory and returns its URL.
    func exportData(configuration: ExportConfiguration, library: LibraryContents) async throws -> URL {
        let data = buildExportData(configuration: configuration, library: library)
        lastExportDroppedPhotos = false
        switch configuration.format {
        case .json:
            return try await exportJSON(data)
        case .csv:
            return try await exportCSV(data)
        }
    }

    // MARK: - Package

    /// Writes the library as a package to the temporary directory and returns its URL: the
    /// records as JSON, and (with `includePhotos`) each photo as a file of its own.
    ///
    /// Photos go in a few at a time, read through contexts that are let go, so a library far
    /// larger than memory can be written. One past the package limit throws
    /// `ExportError.photosTooLarge`, or with `dropsPhotosIfTooLarge` is written without photos.
    func exportLibrary(configuration: ExportConfiguration, library: LibraryContents) async throws -> URL {
        lastExportDroppedPhotos = false
        // The records carry no photos here: those travel as files beside them.
        var records = configuration
        records.includePhotos = false
        records.format = .json
        let data = buildExportData(configuration: records, library: library)
        let manifest = try await encode(data)
        guard manifest.count <= maximumBytes else {
            throw ExportError.tooLarge(megabytes: (manifest.count + 1_048_575) / 1_048_576,
                                       limitMegabytes: maximumBytes / 1_048_576, includesPhotos: false)
        }
        let limit = maximumPackageBytes / 1_048_576
        if configuration.includePhotos {
            do {
                return try await writePackage(manifest: manifest, date: data.metadata.exportDate,
                                              photosOf: library, configuration: configuration)
            } catch ZipError.tooLarge {
                guard configuration.dropsPhotosIfTooLarge else {
                    throw ExportError.photosTooLarge(limitMegabytes: limit, includesPhotos: true)
                }
                logger.warning("Package left photos out: with them the file would be too large to read back")
            }
        }
        do {
            let url = try await writePackage(manifest: manifest, date: data.metadata.exportDate,
                                             photosOf: nil, configuration: configuration)
            lastExportDroppedPhotos = configuration.includePhotos
            return url
        } catch ZipError.tooLarge {
            throw ExportError.photosTooLarge(limitMegabytes: limit, includesPhotos: false)
        }
    }

    /// Writes one package file. Removes it again if anything goes wrong part-way.
    private func writePackage(manifest: Data, date: Date, photosOf library: LibraryContents?,
                              configuration: ExportConfiguration) async throws -> URL {
        let url = temporaryURL(extension: LibraryPackage.fileExtension)
        let writer = try LibraryPackageWriter(url: url, date: date, maximumBytes: maximumPackageBytes)
        do {
            if let library {
                try await addPhotos(of: library, configuration: configuration, to: writer)
            }
            try await writer.finish(manifest: manifest, includesPhotos: library != nil, appName: Constants.App.name)
            return url
        } catch {
            await writer.cancel()
            throw error
        }
    }

    /// Hands the library's photos to `writer`, `photoBatch` at a time.
    ///
    /// The bytes are read through a scratch context for each lot, never from the library's own
    /// objects: those stay in memory for as long as the screens showing them do, and a photo
    /// once read would stay with them.
    private func addPhotos(of library: LibraryContents, configuration: ExportConfiguration,
                           to writer: LibraryPackageWriter) async throws {
        let gear = configuration.includeGear ? library.gearItems : []
        let context = gear.lazy.compactMap(\.modelContext).first
        // Saved first, so the scratch contexts see what the library's own context does.
        if let context, context.hasChanges { try context.save() }
        let container = context?.container

        // Gear photos, in gallery order within each item.
        var seen = Set<UUID>()
        var photos: [GearPhoto] = []
        var ownerByPhoto: [UUID: UUID] = [:]
        for item in gear {
            for photo in (item.photos ?? []).sorted(by: { $0.order < $1.order }) where seen.insert(photo.id).inserted {
                photos.append(photo)
                ownerByPhoto[photo.id] = item.id
            }
        }
        for start in stride(from: 0, to: photos.count, by: photoBatch) {
            let lot = Array(photos[start..<min(start + photoBatch, photos.count)])
            try await writer.add(try Self.read(lot, ownerByPhoto: ownerByPhoto, container: container))
        }

        // Maintenance records' photos. Which records have one isn't known without reading them,
        // so every record is looked at, again through scratch contexts.
        guard configuration.includeMaintenance else { return }
        var seenRecords = Set<UUID>()
        let records = gear.flatMap { $0.maintenanceRecords ?? [] }.filter { seenRecords.insert($0.id).inserted }
        let recordBatch = photoBatch * 4
        for start in stride(from: 0, to: records.count, by: recordBatch) {
            let lot = Array(records[start..<min(start + recordBatch, records.count)])
            let found = try Self.readPhotos(of: lot, container: container)
            if !found.isEmpty { try await writer.add(found) }
        }
    }

    /// The bytes and details of `lot`, read through a scratch context when the photos are in a
    /// store, and from the objects themselves when they aren't (nothing to let go of there).
    private static func read(_ lot: [GearPhoto], ownerByPhoto: [UUID: UUID],
                             container: ModelContainer?) throws -> [LibraryPackageWriter.Photo] {
        func details(_ source: [GearPhoto]) -> [LibraryPackageWriter.Photo] {
            source.compactMap { photo in
                guard let owner = ownerByPhoto[photo.id] else { return nil }
                return LibraryPackageWriter.Photo(id: photo.id, gearItemID: owner, caption: photo.caption, order: photo.order,
                                                  dateAdded: photo.dateAdded, isPrimary: photo.isPrimary, data: photo.imageData)
            }
        }
        guard let container else { return details(lot) }
        let ids = lot.map(\.id)
        let scratch = ModelContext(container)
        // The context has to outlive the reading: its objects fetch their bytes through it.
        return try withExtendedLifetime(scratch) {
            details(try scratch.fetch(FetchDescriptor<GearPhoto>(predicate: #Predicate { ids.contains($0.id) })))
        }
    }

    private static func readPhotos(of lot: [MaintenanceRecord],
                                   container: ModelContainer?) throws -> [LibraryPackageWriter.MaintenancePhoto] {
        func details(_ source: [MaintenanceRecord]) -> [LibraryPackageWriter.MaintenancePhoto] {
            source.compactMap { record in
                record.photoData.map { LibraryPackageWriter.MaintenancePhoto(recordID: record.id, data: $0) }
            }
        }
        guard let container else { return details(lot) }
        let ids = lot.map(\.id)
        let scratch = ModelContext(container)
        return try withExtendedLifetime(scratch) {
            details(try scratch.fetch(FetchDescriptor<MaintenanceRecord>(predicate: #Predicate { ids.contains($0.id) })))
        }
    }

    /// Writes a PDF inventory report from the same selection-gated snapshot.
    func exportPDF(configuration: ExportConfiguration, library: LibraryContents) async throws -> URL {
        let data = buildExportData(configuration: configuration, library: library)
        let pdf = PDFRenderer().createPDF(
            title: "\(Constants.App.name) Inventory",
            subtitle: "Prepared \(data.metadata.exportDate.formatted(date: .long, time: .shortened))",
            sections: buildPDFSections(from: data))
        return try await saveToFile(data: pdf, extension: "pdf")
    }

    func buildExportData(configuration: ExportConfiguration, library: LibraryContents) -> LibraryExport {
        let gear = configuration.includeGear ? library.gearItems : []
        var data = LibraryExport(
            metadata: ExportMetadata(appName: Constants.App.name, appVersion: Constants.App.version,
                                     exportDate: Date(), format: configuration.format),
            gearItems: gear.map { GearItemDTO(from: $0, includePhotos: configuration.includePhotos) },
            maintenanceRecords: configuration.includeMaintenance
                ? gear.flatMap { ($0.maintenanceRecords ?? []).map { MaintenanceRecordDTO(from: $0, includePhotos: configuration.includePhotos) } } : [],
            maintenanceReminders: configuration.includeMaintenance
                ? gear.flatMap { ($0.maintenanceReminders ?? []).map(MaintenanceReminderDTO.init(from:)) } : [],
            shutterCountReadings: configuration.includeShutterCounts
                ? gear.flatMap { ($0.shutterCountReadings ?? []).map(ShutterCountReadingDTO.init(from:)) } : [],
            loans: configuration.includeLoans
                ? gear.flatMap { ($0.loans ?? []).map(GearLoanDTO.init(from:)) } : [],
            developmentRecipes: configuration.includeDevelopmentRecipes
                ? library.developmentRecipes.map(DevelopmentRecipeDTO.init(from:)) : [],
            savedPlaces: configuration.includeSavedPlaces
                ? library.savedPlaces.map(SavedPlaceDTO.init(from:)) : [],
            shoots: configuration.includeShoots ? library.shoots.map(ShootDTO.init(from:)) : [],
            kits: configuration.includeShoots ? library.kits.map(KitDTO.init(from:)) : [],
            shotListTemplates: configuration.includeShoots
                ? library.shotListTemplates.map(ShotListTemplateDTO.init(from:)) : [],
            filmRolls: configuration.includeShoots ? library.filmRolls.map(FilmRollDTO.init(from:)) : [],
            settings: configuration.includeSettings ? exportSettings() : nil,
            includesPhotos: configuration.includePhotos)
        lastReplacedValueCount = data.replaceUnrestorableNumbers()
        if lastReplacedValueCount > 0 {
            logger.warning("Export replaced \(self.lastReplacedValueCount, privacy: .public) unrestorable number(s) with defaults")
        }
        return data
    }

    // MARK: - JSON

    /// The records as JSON. The DTOs are plain values, so encoding (including base64 for any
    /// photos in them) runs off the main actor; encoding in place froze the UI.
    private func encode(_ data: LibraryExport) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(data)
        }.value
    }

    private func exportJSON(_ data: LibraryExport) async throws -> URL {
        let json = try await encode(data)
        // Import and restore refuse anything larger, so writing it would hand over a file that
        // can never be read back.
        guard json.count <= maximumBytes else {
            throw ExportError.tooLarge(megabytes: (json.count + 1_048_575) / 1_048_576,
                                       limitMegabytes: maximumBytes / 1_048_576,
                                       includesPhotos: data.includesPhotos)
        }
        return try await saveToFile(data: json, extension: "json")
    }

    // MARK: - CSV

    /// Column headers for the inventory CSV, in order.
    static let csvColumns = [
        "Category", "Make", "Model", "Serial Number", "Year", "Mount", "Format", "Focal Length",
        "Max Aperture", "Filter Thread (mm)", "Firmware", "Shutter Count", "Rated Shutter Life",
        "Purchase Date", "Purchase Price", "Current Value", "UPC", "Status", "Notes", "Added", "Links"
    ]

    private func exportCSV(_ data: LibraryExport) async throws -> URL {
        let csv = buildCSV(data)
        return try await saveToFile(data: Data(csv.utf8), extension: "csv")
    }

    /// The inventory as CSV: one header row, then one row per item. Amounts are plain numbers
    /// (no symbol or grouping) so a spreadsheet can sum them.
    func buildCSV(_ data: LibraryExport) -> String {
        let latestCounts = Self.latestShutterCounts(data.shutterCountReadings)
        let openLoans = Set(data.loans.filter { $0.returnedDate == nil }.compactMap(\.gearItemID))
        var lines = [Self.csvColumns.map(csvField).joined(separator: ",")]
        for item in data.gearItems {
            let format = item.sensorFormatID.flatMap { SensorFormat(id: $0) }
            var status: [String] = []
            if openLoans.contains(item.id) { status.append("On loan") }
            if item.serviceNeeded == true { status.append("Needs service") }
            let fields: [String] = [
                GearCategory(storedID: item.category).displayName,
                item.make ?? "",
                item.model ?? "",
                item.serialNumber ?? "",
                item.manufacturingYear.map { String($0) } ?? "",
                item.mount ?? "",
                format?.name ?? "",
                Self.rangeText(item.focalLengthMin, item.focalLengthMax, suffix: " mm"),
                Self.rangeText(item.maxApertureWide, item.maxApertureTele, prefix: "f/"),
                Self.plain(item.filterThread),
                item.firmwareVersion ?? "",
                latestCounts[item.id].map { String($0) } ?? "",
                (item.ratedShutterLife ?? 0) > 0 ? String(item.ratedShutterLife ?? 0) : "",
                item.purchaseDate?.formatted(date: .abbreviated, time: .omitted) ?? "",
                item.purchasePrice.map { String(format: "%.2f", $0) } ?? "",
                item.currentValue.map { String(format: "%.2f", $0) } ?? "",
                item.upcCode ?? "",
                status.joined(separator: "; "),
                item.notes ?? "",
                item.dateAdded.formatted(date: .abbreviated, time: .omitted),
                (item.referenceLinks ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - PDF

    private func buildPDFSections(from data: LibraryExport) -> [PDFSection] {
        let latestCounts = Self.latestShutterCounts(data.shutterCountReadings)
        let total = data.gearItems.reduce(Decimal.zero) { sum, item in
            sum + ((item.currentValue ?? item.purchasePrice).map { Decimal(roundTripping: $0) } ?? 0)
        }
        var sections = [PDFSection(title: "Summary", content: """
            Items: \(data.gearItems.count)
            Total value: \(CurrencyFormatter.format(total))
            Values are the current value where one was entered, otherwise the purchase price.
            """)]
        let grouped = Dictionary(grouping: data.gearItems) { GearCategory(storedID: $0.category) }
        for category in GearCategory.allCases {
            guard let items = grouped[category], !items.isEmpty else { continue }
            let content = items
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                .map { pdfEntry(for: $0, shutterCount: latestCounts[$0.id]) }
                .joined(separator: "\n")
            sections.append(PDFSection(title: "\(category.displayName) (\(items.count))", content: content))
        }
        return sections
    }

    /// One item's lines in the PDF report. Internal so tests can check it without parsing a PDF.
    func pdfEntry(for item: GearItemDTO, shutterCount: Int?) -> String {
        var lines = [item.displayName]
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { lines.append("   \(label): \(value)") }
        }
        add("Serial number", item.serialNumber)
        add("Year", item.manufacturingYear.map { String($0) })
        add("Mount", item.mount)
        add("Format", item.sensorFormatID.flatMap { SensorFormat(id: $0) }?.name)
        add("Focal length", Self.rangeText(item.focalLengthMin, item.focalLengthMax, suffix: " mm"))
        add("Max aperture", Self.rangeText(item.maxApertureWide, item.maxApertureTele, prefix: "f/"))
        add("Shutter count", shutterCount.map { $0.formatted() })
        add("Purchased", item.purchaseDate?.formatted(date: .abbreviated, time: .omitted))
        add("Purchase price", item.purchasePrice.map { CurrencyFormatter.format(Decimal(roundTripping: $0)) })
        add("Current value", item.currentValue.map { CurrencyFormatter.format(Decimal(roundTripping: $0)) })
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// The highest-dated reading's count per gear item.
    static func latestShutterCounts(_ readings: [ShutterCountReadingDTO]) -> [UUID: Int] {
        var latest: [UUID: ShutterCountReadingDTO] = [:]
        for reading in readings {
            guard let id = reading.gearItemID else { continue }
            if let current = latest[id], (current.date, current.count) >= (reading.date, reading.count) { continue }
            latest[id] = reading
        }
        return latest.mapValues(\.count)
    }

    /// "24–70 mm", "f/2.8", or "" when unset.
    static func rangeText(_ low: Double?, _ high: Double?, prefix: String = "", suffix: String = "") -> String {
        let values = [low ?? 0, high ?? 0].filter { $0 > 0 }
        guard let first = values.first else { return "" }
        let last = values.last ?? first
        return first == last ? "\(prefix)\(plain(first))\(suffix)" : "\(prefix)\(plain(first))–\(plain(last))\(suffix)"
    }

    /// A plain number for files: up to two decimals, "." separator, no grouping; "" for unset.
    static func plain(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }

    /// The `exportableSettings` keys, as the strings `ImportedSettings` validates on the way back.
    /// Unset keys export their effective defaults, so a restore doesn't change settings.
    private func exportSettings() -> [String: String] {
        typealias K = Constants.UserDefaultsKeys
        return [
            K.hapticFeedback: String(settingsStore.object(forKey: K.hapticFeedback) as? Bool ?? true),
            K.darkModePreference: settingsStore.string(forKey: K.darkModePreference) ?? "system",
            K.measurementUnits: settingsStore.string(forKey: K.measurementUnits) ?? UnitPreference.automatic.rawValue,
            K.depthOfFieldStandard: String(settingsStore.object(forKey: K.depthOfFieldStandard) as? Int
                                           ?? CircleOfConfusionStandard.standard.rawValue),
            // `String(Double)` is the shortest text that reads back as the same number.
            K.lightMeterCalibration: String(settingsStore.double(forKey: K.lightMeterCalibration))
        ]
    }

    private func saveToFile(data: Data, extension ext: String) async throws -> URL {
        let url = temporaryURL(extension: ext)
        try await Task.detached { try data.write(to: url) }.value
        return url
    }

    /// Exports are share-sheet artifacts, so they live in the temporary directory. A short
    /// unique suffix keeps same-second exports from colliding.
    private func temporaryURL(extension ext: String) -> URL {
        let name = "shuttermanager_\(DateFormatter.fileTimestamp.string(from: Date()))_\(UUID().uuidString.prefix(8)).\(ext)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    /// One RFC 4180 CSV field: newlines flattened, quotes doubled, always quoted.
    private func csvField(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

/// Why an export wasn't written.
enum ExportError: LocalizedError, Equatable {
    /// The JSON file would be larger than import and restore can read.
    case tooLarge(megabytes: Int, limitMegabytes: Int, includesPhotos: Bool)
    /// The library file passed its limit while it was being written. Its full size isn't known:
    /// writing stopped there.
    case photosTooLarge(limitMegabytes: Int, includesPhotos: Bool)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let megabytes, let limit, let includesPhotos):
            let size = "The file would be \(megabytes) MB, and \(Constants.App.name) can read back at most \(limit) MB."
            return includesPhotos ? size + " Turn Photos off to export everything else." : size
        case .photosTooLarge(let limit, let includesPhotos):
            let size = "The library is larger than one file can hold: \(Constants.App.name) can read back at most \(Self.sizeText(megabytes: limit))."
            return includesPhotos ? size + " Turn Photos off to export everything else." : size
        }
    }

    /// "3 GB", or "512 MB" below a gigabyte.
    static func sizeText(megabytes: Int) -> String {
        megabytes >= 1024 && megabytes % 1024 == 0 ? "\(megabytes / 1024) GB" : "\(megabytes) MB"
    }
}

// MARK: - PDF Rendering

/// Renders titled text sections onto pages of the region's paper (US Letter or A4), breaking
/// pages as needed.
final class PDFRenderer {
    private let pageWidth: CGFloat
    private let pageHeight: CGFloat
    private let margin: CGFloat = 50

    init(pageSize: CGSize = PrintPaper.size()) {
        pageWidth = pageSize.width
        pageHeight = pageSize.height
    }

    func createPDF(title: String, subtitle: String, sections: [PDFSection]) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: Constants.App.name,
            kCGPDFContextTitle as String: title
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), format: format)
        return renderer.pdfData { context in
            context.beginPage()
            var y = margin
            y = drawText(title, fontSize: 24, bold: true, at: y, in: context)
            y = drawText(subtitle, fontSize: 14, bold: false, at: y + 10, in: context)
            y += 30
            for section in sections {
                if y > pageHeight - margin - 100 {
                    context.beginPage()
                    y = margin
                }
                y = drawText(section.title, fontSize: 18, bold: true, at: y, in: context)
                y += 10
                y = drawText(section.content, fontSize: 12, bold: false, at: y, in: context)
                y += 20
            }
        }
    }

    private func drawText(_ text: String, fontSize: CGFloat, bold: Bool, at y: CGFloat,
                          in context: UIGraphicsPDFRendererContext) -> CGFloat {
        guard !text.isEmpty else { return y }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.black
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var offset = 0
        var cursor = y
        while offset < attributed.length {
            if pageHeight - margin - cursor < fontSize * 1.5 {
                context.beginPage()
                cursor = margin
            }
            let available = pageHeight - margin - cursor
            let path = CGPath(rect: CGRect(x: margin, y: margin, width: pageWidth - 2 * margin, height: available), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { return cursor }
            let cg = context.cgContext
            cg.saveGState()
            cg.textMatrix = .identity
            cg.translateBy(x: 0, y: pageHeight)
            cg.scaleBy(x: 1, y: -1)
            CTFrameDraw(frame, cg)
            cg.restoreGState()
            let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, visible, nil,
                CGSize(width: pageWidth - 2 * margin, height: .greatestFiniteMagnitude), nil)
            cursor += ceil(size.height)
            offset += visible.length
            if offset < attributed.length {
                context.beginPage()
                cursor = margin
            }
        }
        return cursor
    }
}

struct PDFSection {
    let title: String
    let content: String
}
