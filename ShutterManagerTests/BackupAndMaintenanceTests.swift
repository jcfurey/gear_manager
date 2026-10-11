//
//  BackupAndMaintenanceTests.swift
//  ShutterManagerTests
//
//  Backups verify and restore; maintenance logging keeps history and due dates together.
//

import Foundation
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct BackupTests {
    @Test func backupIsListedAndRestoresTheLibrary() async throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = TestSupport.makeDefaults()
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        try context.save()

        let manager = BackupManager(directory: directory, defaults: defaults)
        try await manager.createBackup(gearItems: [body])
        #expect(manager.availableBackups.count == 1)
        let backup = try #require(manager.availableBackups.first)
        #expect(backup.itemCounts.gearItems == 1)
        #expect(backup.itemCounts.otherRecords == 6)
        #expect(backup.includesPhotos == true)
        #expect(manager.lastBackupDate != nil)

        // Change the library, then restore.
        body.model = "Changed"
        TestSupport.insertSampleLens(into: context)
        try context.save()
        try await manager.restoreBackup(backup, to: context)
        let items = try context.fetch(FetchDescriptor<GearItem>())
        #expect(items.count == 1)
        #expect(items.first?.model == "Z6 III")
        #expect(items.first?.shutterCountReadings?.count == 2)
    }

    @Test func retentionKeepsTheNewestBackups() async throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = BackupManager(directory: directory, defaults: TestSupport.makeDefaults())
        manager.configuration.maxBackups = 2
        for _ in 0..<3 {
            try await manager.createBackup(gearItems: [])
        }
        #expect(manager.availableBackups.count == 2)
    }

    @Test func automaticBackupIsDueWithoutAnEarlierOne() {
        let manager = BackupManager(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("Backups-\(UUID().uuidString)"), defaults: TestSupport.makeDefaults())
        #expect(manager.shouldCreateAutomaticBackup())
    }
}

@MainActor
struct MaintenanceServiceTests {
    @Test func loggingASensorCleaningMovesTheDueDate() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody)
        body.sensorCleaningIntervalDays = 90
        body.lastSensorCleaningDate = Calendar.current.date(byAdding: .day, value: -200, to: Date())
        context.insert(body)
        try context.save()
        #expect(body.isSensorCleaningDue)

        let today = Date()
        try MaintenanceService.log(for: body, type: .sensorCleaning, date: today, context: context)
        #expect(body.lastSensorCleaningDate == today)
        #expect(!body.isSensorCleaningDue)
        #expect(body.maintenanceRecords?.count == 1)
        #expect(body.maintenanceRecords?.first?.type == .sensorCleaning)
    }

    @Test func aBackdatedCleaningNeverMovesTheDateBackwards() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody)
        let recent = Date()
        body.lastSensorCleaningDate = recent
        context.insert(body)
        try context.save()
        try MaintenanceService.log(for: body, type: .sensorCleaning,
                                   date: Calendar.current.date(byAdding: .month, value: -6, to: recent) ?? recent,
                                   context: context)
        #expect(body.lastSensorCleaningDate == recent)
    }

    @Test func completingASensorReminderRecordsTheCleaning() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody)
        context.insert(body)
        let reminder = MaintenanceReminder(gearItem: body, type: .sensorCleaning, dueDate: Date(), recurringInterval: 180)
        context.insert(reminder)
        try context.save()

        let record = try MaintenanceService.complete(reminder, for: body, context: context)
        #expect(record?.type == .sensorCleaning)
        #expect(body.lastSensorCleaningDate != nil)
        let active = (body.maintenanceReminders ?? []).filter(\.isActive)
        #expect(active.count == 1)
        #expect((active.first?.daysUntilDue ?? 0) >= 179)
    }

    @Test func aFailedSaveUndoesTheLog() throws {
        struct SaveFailure: Error {}
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody)
        context.insert(body)
        try context.save()
        #expect(throws: SaveFailure.self) {
            try MaintenanceService.log(for: body, type: .sensorCleaning, date: Date(), context: context,
                                       saveChanges: { _ in throw SaveFailure() })
        }
        #expect(body.lastSensorCleaningDate == nil)
        #expect((body.maintenanceRecords ?? []).isEmpty)
    }

    @Test func recurringRemindersSkipToTheNextOccurrence() {
        let calendar = Calendar(identifier: .gregorian)
        let due = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 86_400 * 100.5)
        let next = MaintenanceReminder.nextOccurrence(after: due, intervalDays: 30, now: now, calendar: calendar)
        #expect(next == Date(timeIntervalSince1970: 86_400 * 120))
    }
}
