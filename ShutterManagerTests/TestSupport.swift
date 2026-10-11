//
//  TestSupport.swift
//  ShutterManagerTests
//
//  Shared helpers: isolated stores, scratch preferences and sample gear.
//

import Foundation
import SwiftData
@testable import ShutterManager

@MainActor
enum TestSupport {
    /// A fresh in-memory container with the app's full schema. In-memory stores can't mirror to
    /// CloudKit, so the configuration says so explicitly.
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(
            schema: AppSchema.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    /// A scratch UserDefaults suite, emptied first, so tests never touch the app's preferences.
    static func makeDefaults(_ name: String = "tests.\(UUID().uuidString)") -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A temporary directory for backup and export files.
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShutterManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A camera body with every camera field set, its children inserted into `context`.
    @discardableResult
    static func insertSampleBody(into context: ModelContext) -> GearItem {
        let body = GearItem(category: .cameraBody, make: "Nikon", model: "Z6 III", serialNumber: "3000123",
                            purchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
                            purchasePrice: Decimal(string: "2499.99"), currentValue: Decimal(string: "2100.07"),
                            notes: "Main body")
        body.mount = "Nikon Z"
        body.sensorFormatID = SensorFormat.fullFrame.id
        body.resolutionWidthPx = 6048
        body.resolutionHeightPx = 4032
        body.firmwareVersion = "1.10"
        body.ratedShutterLife = 200_000
        body.sensorCleaningIntervalDays = 180
        body.lastSensorCleaningDate = Date(timeIntervalSince1970: 1_710_000_000)
        body.reminderHour = 9
        body.reminderMinute = 30
        body.manufacturingYear = 2024
        body.referenceLinks = "nikonusa.com/manual\nhttps://example.com/review"
        context.insert(body)
        context.insert(ShutterCountReading(gearItem: body, date: Date(timeIntervalSince1970: 1_720_000_000), count: 12_000))
        context.insert(ShutterCountReading(gearItem: body, date: Date(timeIntervalSince1970: 1_730_000_000), count: 18_500, source: .photo))
        context.insert(GearLoan(gearItem: body, direction: .lentOut, person: "Sam", contact: "555-0100",
                                outDate: Date(timeIntervalSince1970: 1_735_000_000),
                                dueDate: Date(timeIntervalSince1970: 1_735_600_000), notes: "With strap"))
        context.insert(MaintenanceRecord(gearItem: body, type: .sensorCleaning, date: Date(timeIntervalSince1970: 1_710_000_000),
                                         cost: Decimal(string: "45.50"), notes: "Wet clean", performedBy: "Shop"))
        context.insert(MaintenanceReminder(gearItem: body, type: .firmwareUpdate, dueDate: Date(timeIntervalSince1970: 1_760_000_000),
                                           recurringInterval: 90, notes: "Check site"))
        return body
    }

    /// A zoom lens with lens fields set.
    @discardableResult
    static func insertSampleLens(into context: ModelContext) -> GearItem {
        let lens = GearItem(category: .lens, make: "Nikon", model: "Z 24-70mm f/2.8 S", purchasePrice: 1999)
        lens.mount = "Nikon Z"
        lens.sensorFormatID = SensorFormat.fullFrame.id
        lens.focalLengthMin = 24
        lens.focalLengthMax = 70
        lens.maxApertureWide = 2.8
        lens.maxApertureTele = 2.8
        lens.minFocusDistance = 0.38
        lens.filterThread = 82
        context.insert(lens)
        return lens
    }
}
