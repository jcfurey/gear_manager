//
//  ImportDocument.swift
//  ShutterManager
//
//  Reads and validates export and backup files, off the main actor.
//

import Foundation

/// Value-only decoding and validation, shared by import and restore and run away from the UI
/// actor. Nothing here touches the store: a file is fully read and checked before any record
/// changes.
enum ImportDocument {
    /// Reads a file someone chose as far as its records: a library package, whose photos stay
    /// in the file until they're imported, or a JSON export. Told apart by how the file starts,
    /// not by its name.
    static func open(_ url: URL) throws -> ImportFile {
        guard LibraryPackage.looksLikePackage(url) else {
            return ImportFile(document: try decode(read(url)), package: nil)
        }
        do {
            let package = try LibraryPackageFile(url: url, maximumBytes: Constants.DataLimits.maximumPackageBytes,
                                                 maximumManifestBytes: Constants.DataLimits.maximumImportBytes,
                                                 maximumPhotos: Constants.DataLimits.maximumRecords)
            let document = try decode(package.manifest)
            for photo in package.photoIndex?.photos ?? [] {
                try check(Double(photo.order), Constants.DataLimits.maximumMeasurement)
            }
            guard document.recordCount + (package.photoIndex?.count ?? 0) <= Constants.DataLimits.maximumRecords else {
                throw ImportError.importFailed("The file contains too many records.")
            }
            return ImportFile(document: document, package: package)
        } catch let error as LibraryPackageError {
            throw ImportError(error)
        }
    }

    static func read(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Constants.DataLimits.maximumImportBytes else { throw ImportError.fileTooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Constants.DataLimits.maximumImportBytes else { throw ImportError.fileTooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> LibraryExport {
        guard data.count <= Constants.DataLimits.maximumImportBytes else { throw ImportError.fileTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw ImportError.unsupportedFormat
        }
        guard header.formatVersion <= LibraryExport.currentFormatVersion else {
            throw ImportError.newerFormat
        }
        let document: LibraryExport
        do {
            document = try decoder.decode(LibraryExport.self, from: data)
        } catch {
            throw ImportError.corruptedData
        }
        try validate(document)
        return document
    }

    /// Just enough to recognize a Shutter Manager file before decoding the rest.
    private struct Header: Decodable {
        let formatVersion: Int
    }

    /// Rejects what could hurt the app: too many records, non-finite numbers, and magnitudes past
    /// the overflow-safety bounds in `Constants.DataLimits`. It deliberately accepts any value the
    /// app itself can store (a negative price typed on a hardware keyboard, a full-resolution
    /// photo), because backups run through this same check and rejecting such a value would stop
    /// every automatic backup. Keep it in step with `LibraryExport.replaceUnrestorableNumbers()`.
    static func validate(_ document: LibraryExport) throws {
        guard document.recordCount <= Constants.DataLimits.maximumRecords else {
            throw ImportError.importFailed("The file contains too many records.")
        }
        typealias Limits = Constants.DataLimits
        for item in document.gearItems {
            try check(item.purchasePrice, Limits.maximumMoney)
            try check(item.currentValue, Limits.maximumMoney)
            for value in [item.focalLengthMin, item.focalLengthMax, item.maxApertureWide, item.maxApertureTele,
                          item.minFocusDistance, item.filterThread, item.filterStops, item.guideNumber,
                          item.capacityGB] {
                try check(value, Limits.maximumMeasurement)
            }
            for count in [item.sensorCleaningIntervalDays, item.reminderHour, item.reminderMinute,
                          item.manufacturingYear, item.resolutionWidthPx, item.resolutionHeightPx] {
                try check(count.map { Double($0) }, Limits.maximumMeasurement)
            }
            for count in [item.ratedShutterLife, item.chargeCycles, item.ratedChargeCycles] {
                try check(count.map { Double($0) }, Limits.maximumCount)
            }
            for photo in item.photos ?? [] {
                try check(Double(photo.order), Limits.maximumMeasurement)
            }
        }
        for record in document.maintenanceRecords {
            try check(record.cost, Limits.maximumMoney)
        }
        for reminder in document.maintenanceReminders {
            try check(reminder.recurringInterval.map { Double($0) }, Limits.maximumMeasurement)
        }
        for reading in document.shutterCountReadings {
            try check(Double(reading.count), Limits.maximumCount)
        }
        for place in document.places {
            try check(place.latitude, Limits.maximumMeasurement)
            try check(place.longitude, Limits.maximumMeasurement)
        }
        for shoot in document.shootList {
            try check(shoot.latitude, Limits.maximumMeasurement)
            try check(shoot.longitude, Limits.maximumMeasurement)
            try check(shoot.goldenHourAlertMinutes.map { Double($0) }, Limits.maximumMeasurement)
            for item in shoot.shotList {
                try check(Double(item.order), Limits.maximumMeasurement)
            }
        }
        for template in document.templateList {
            for item in template.items {
                try check(Double(item.order), Limits.maximumMeasurement)
            }
        }
        for roll in document.rollList {
            try check(roll.pushPullStops, Limits.maximumMeasurement)
            for count in [roll.ratedISO, roll.frameCount, roll.framesShot] {
                try check(count.map { Double($0) }, Limits.maximumMeasurement)
            }
        }
        for recipe in document.recipes {
            try check(recipe.temperatureCelsius, Limits.maximumMeasurement)
            for step in recipe.steps {
                for value in [step.order, step.durationSeconds, step.agitationInitialSeconds,
                              step.agitationIntervalSeconds, step.agitationDurationSeconds] as [Int?] {
                    try check(value.map { Double($0) }, Limits.maximumMeasurement)
                }
            }
        }
    }

    /// Finite and within ±`maximum`; nil passes. Negative values pass too: every display path
    /// clamps or shows them, and nothing downstream traps on a sign.
    private static func check(_ value: Double?, _ maximum: Double) throws {
        guard let value else { return }
        guard value.isFinite, abs(value) <= maximum else {
            throw ImportError.importFailed("The file contains a number outside the supported range.")
        }
    }
}

/// A chosen file, read as far as its records.
struct ImportFile: Sendable {
    let document: LibraryExport
    /// The package the records came from, when the file is one. Its photos are read from it as
    /// they're imported, never all at once.
    let package: LibraryPackageFile?

    /// Gear photos the file holds, wherever it keeps them.
    var photoCount: Int {
        package?.photoIndex?.photos.count ?? document.gearItems.reduce(0) { $0 + ($1.photos?.count ?? 0) }
    }

    /// Whether the file was made with photos, so a restore can warn before replacing photos
    /// with none.
    var includesPhotos: Bool {
        package.map { $0.photoIndex != nil } ?? document.includesPhotos
    }

    /// Reads every photo in a package through and checks it against its checksum. What a backup
    /// does before it's listed; a JSON file's photos were checked by decoding them.
    func verifyPhotos() throws {
        do {
            try package?.verifyPhotos()
        } catch let error as LibraryPackageError {
            throw ImportError(error)
        }
    }
}

enum ImportError: LocalizedError {
    case accessDenied
    case fileTooLarge
    case unsupportedFormat
    case newerFormat
    case corruptedData
    /// A library file another app has unpacked and zipped again.
    case rewrittenArchive
    /// The records went in, but not every photo: `added` of `total` did.
    case photosIncomplete(added: Int, total: Int, reason: String)
    case importFailed(String)

    init(_ error: LibraryPackageError) {
        switch error {
        case .notALibrary: self = .unsupportedFormat
        case .rewritten: self = .rewrittenArchive
        case .damaged: self = .corruptedData
        case .newerVersion: self = .newerFormat
        case .tooLarge: self = .fileTooLarge
        }
    }

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to the file was denied."
        case .fileTooLarge:
            let json = Constants.DataLimits.maximumImportBytes / (1024 * 1024)
            let library = Constants.DataLimits.maximumPackageBytes / (1024 * 1024 * 1024)
            return "The file is larger than \(Constants.App.name) can read: \(library) GB for a library file, \(json) MB for a JSON file."
        case .unsupportedFormat:
            return "This isn't a \(Constants.App.name) export or backup."
        case .newerFormat:
            return "This file was made by a newer version of \(Constants.App.name). Update the app to import it."
        case .corruptedData:
            return "The file appears to be damaged."
        case .rewrittenArchive:
            return "This zip file has been changed by another app. Use the library file as \(Constants.App.name) wrote it: one that was unpacked and zipped again can't be read."
        case .photosIncomplete(let added, let total, let reason):
            return "The records were imported, but only \(added) of \(total) photos were. Import the file again to add the rest. (\(reason))"
        case .importFailed(let message):
            return "Import failed: \(message)"
        }
    }
}
