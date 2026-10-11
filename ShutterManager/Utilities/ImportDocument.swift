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

enum ImportError: LocalizedError {
    case accessDenied
    case fileTooLarge
    case unsupportedFormat
    case newerFormat
    case corruptedData
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to the file was denied."
        case .fileTooLarge:
            return "The file is larger than the supported 256 MB."
        case .unsupportedFormat:
            return "This isn't a \(Constants.App.name) export or backup."
        case .newerFormat:
            return "This file was made by a newer version of \(Constants.App.name). Update the app to import it."
        case .corruptedData:
            return "The file appears to be damaged."
        case .importFailed(let message):
            return "Import failed: \(message)"
        }
    }
}
