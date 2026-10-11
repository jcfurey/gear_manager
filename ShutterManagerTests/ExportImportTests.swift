//
//  ExportImportTests.swift
//  ShutterManagerTests
//
//  Export writes what import reads back, merge never duplicates, and validation rejects only
//  what could hurt the app.
//

import Foundation
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct ExportImportTests {
    private func exportJSON(_ items: [GearItem], recipes: [DevelopmentRecipe] = [], defaults: UserDefaults,
                            photos: Bool = true) async throws -> Data {
        let service = DataExportService(settingsStore: defaults)
        var configuration = DataExportService.ExportConfiguration(format: .json)
        configuration.includePhotos = photos
        let url = try await service.exportData(configuration: configuration,
                                               library: LibraryContents(gearItems: items, developmentRecipes: recipes))
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    private func gear(_ items: [GearItem]) -> LibraryContents {
        LibraryContents(gearItems: items, developmentRecipes: [])
    }

    @Test func jsonRoundTripRestoresEveryRecord() async throws {
        let source = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: source.mainContext)
        let lens = TestSupport.insertSampleLens(into: source.mainContext)
        body.appendGalleryPhoto(Data([1, 2, 3]), in: source.mainContext)
        try source.mainContext.save()
        let defaults = TestSupport.makeDefaults()
        let data = try await exportJSON([body, lens], defaults: defaults)

        let destination = try TestSupport.makeContainer()
        try await DataImportService(settingsStore: TestSupport.makeDefaults()).importData(
            from: data, to: destination.mainContext, strategy: .replace)
        let context = destination.mainContext
        let items = try context.fetch(FetchDescriptor<GearItem>())
        #expect(items.count == 2)
        let restored = try #require(items.first { $0.id == body.id })
        #expect(restored.gearCategory == .cameraBody)
        #expect(restored.make == "Nikon")
        #expect(restored.serialNumber == "3000123")
        #expect(restored.purchasePrice == Decimal(string: "2499.99"))
        #expect(restored.currentValue == Decimal(string: "2100.07"))
        #expect(restored.mount == "Nikon Z")
        #expect(restored.sensorFormatID == "fullFrame")
        #expect(restored.resolutionWidthPx == 6048)
        #expect(restored.ratedShutterLife == 200_000)
        #expect(restored.reminderHour == 9)
        #expect(restored.reminderMinute == 30)
        #expect(restored.lastSensorCleaningDate == body.lastSensorCleaningDate)
        #expect(restored.photos?.count == 1)
        #expect(restored.photos?.first?.imageData == Data([1, 2, 3]))
        #expect(restored.shutterCountReadings?.count == 2)
        #expect(restored.latestShutterReading?.count == 18_500)
        #expect(restored.latestShutterReading?.source == .photo)
        #expect(restored.loans?.first?.person == "Sam")
        #expect(restored.loans?.first?.dueDate == body.loans?.first?.dueDate)
        #expect(restored.maintenanceRecords?.first?.type == .sensorCleaning)
        #expect(restored.maintenanceRecords?.first?.cost == Decimal(string: "45.50"))
        #expect(restored.maintenanceReminders?.first?.type == .firmwareUpdate)
        #expect(restored.maintenanceReminders?.first?.recurringInterval == 90)
        let restoredLens = try #require(items.first { $0.id == lens.id })
        #expect(restoredLens.focalLengthText == "24–70 mm")
        #expect(restoredLens.filterThread == 82)
        #expect(restoredLens.minFocusDistance == 0.38)
    }

    @Test func mergingTheSameFileTwiceAddsNothing() async throws {
        let source = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: source.mainContext)
        try source.mainContext.save()
        let data = try await exportJSON([body], defaults: TestSupport.makeDefaults())

        let destination = try TestSupport.makeContainer()
        let service = DataImportService(settingsStore: TestSupport.makeDefaults())
        try await service.importData(from: data, to: destination.mainContext, strategy: .merge)
        try await service.importData(from: data, to: destination.mainContext, strategy: .merge)
        let context = destination.mainContext
        #expect(try context.fetch(FetchDescriptor<GearItem>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ShutterCountReading>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<GearLoan>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MaintenanceRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MaintenanceReminder>()).count == 1)
    }

    @Test func replaceRemovesWhatTheFileDoesNotHave() async throws {
        let source = try TestSupport.makeContainer()
        let lens = TestSupport.insertSampleLens(into: source.mainContext)
        try source.mainContext.save()
        let data = try await exportJSON([lens], defaults: TestSupport.makeDefaults())

        let destination = try TestSupport.makeContainer()
        TestSupport.insertSampleBody(into: destination.mainContext)
        try destination.mainContext.save()
        try await DataImportService(settingsStore: TestSupport.makeDefaults()).importData(
            from: data, to: destination.mainContext, strategy: .replace)
        let context = destination.mainContext
        #expect(try context.fetch(FetchDescriptor<GearItem>()).map(\.id) == [lens.id])
        #expect(try context.fetch(FetchDescriptor<ShutterCountReading>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<GearLoan>()).isEmpty)
    }

    @Test func unknownStoredIDsSurviveARoundTrip() async throws {
        let source = try TestSupport.makeContainer()
        let item = GearItem()
        item.category = "hologramProjector"
        source.mainContext.insert(item)
        let record = MaintenanceRecord(gearItem: item, type: .other)
        record.typeID = "laserAlignment"
        source.mainContext.insert(record)
        try source.mainContext.save()
        let data = try await exportJSON([item], defaults: TestSupport.makeDefaults())

        let destination = try TestSupport.makeContainer()
        try await DataImportService(settingsStore: TestSupport.makeDefaults()).importData(
            from: data, to: destination.mainContext, strategy: .replace)
        let restored = try #require(try destination.mainContext.fetch(FetchDescriptor<GearItem>()).first)
        #expect(restored.category == "hologramProjector")
        #expect(restored.maintenanceRecords?.first?.typeID == "laserAlignment")
    }

    @Test func settingsTravelAndAreValidated() async throws {
        let exportDefaults = TestSupport.makeDefaults()
        exportDefaults.set(false, forKey: Constants.UserDefaultsKeys.hapticFeedback)
        exportDefaults.set("dark", forKey: Constants.UserDefaultsKeys.darkModePreference)
        exportDefaults.set("imperial", forKey: Constants.UserDefaultsKeys.measurementUnits)
        exportDefaults.set(3000, forKey: Constants.UserDefaultsKeys.depthOfFieldStandard)
        let data = try await exportJSON([], defaults: exportDefaults)

        let importDefaults = TestSupport.makeDefaults()
        let destination = try TestSupport.makeContainer()
        try await DataImportService(settingsStore: importDefaults).importData(from: data, to: destination.mainContext)
        #expect(importDefaults.object(forKey: Constants.UserDefaultsKeys.hapticFeedback) as? Bool == false)
        #expect(importDefaults.string(forKey: Constants.UserDefaultsKeys.darkModePreference) == "dark")
        #expect(importDefaults.string(forKey: Constants.UserDefaultsKeys.measurementUnits) == "imperial")
        #expect(importDefaults.object(forKey: Constants.UserDefaultsKeys.depthOfFieldStandard) as? Int == 3000)
    }

    @Test func everyExportableSettingHasAnImportRule() {
        #expect(ImportedSettings.validatedKeys == Set(Constants.UserDefaultsKeys.exportableSettings))
    }

    @Test func importedSettingsRejectBadValuesAndUnknownKeys() {
        let defaults = TestSupport.makeDefaults()
        let written = ImportedSettings.apply([
            Constants.UserDefaultsKeys.hapticFeedback: "maybe",
            Constants.UserDefaultsKeys.darkModePreference: "neon",
            Constants.UserDefaultsKeys.measurementUnits: "cubits",
            Constants.UserDefaultsKeys.depthOfFieldStandard: "1234",
            "someOtherKey": "true"
        ], to: defaults)
        #expect(written.isEmpty)
        #expect(defaults.object(forKey: "someOtherKey") == nil)
    }

    // MARK: - Validation

    @Test func nonFiniteNumbersAreReplacedSoTheExportStaysRestorable() async throws {
        let source = try TestSupport.makeContainer()
        let lens = TestSupport.insertSampleLens(into: source.mainContext)
        lens.focalLengthMin = .nan
        lens.filterThread = .infinity
        lens.guideNumber = 5e12
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        let data = service.buildExportData(configuration: .init(format: .json), library: gear([lens]))
        #expect(service.lastReplacedValueCount == 3)
        #expect(data.gearItems.first?.focalLengthMin == nil)
        #expect(data.gearItems.first?.focalLengthMax == 70)
        try ImportDocument.validate(data)
    }

    @Test func validationRejectsOutOfRangeNumbers() throws {
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        var data = service.buildExportData(configuration: .init(format: .json), library: .empty)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A reading with an absurd count, as a hand-edited file might have.
        let readingJSON = """
            {"id":"\(UUID().uuidString)","date":"2026-01-01T00:00:00Z","count":99999999999,"source":"manual"}
            """
        let reading = try decoder.decode(ShutterCountReadingDTO.self, from: Data(readingJSON.utf8))
        data.shutterCountReadings = [reading]
        #expect(throws: ImportError.self) { try ImportDocument.validate(data) }
        let file = try encoder.encode(data)
        #expect(throws: ImportError.self) { try ImportDocument.decode(file) }
    }

    @Test func rejectsFilesFromOtherApps() {
        let otherAppExport = Data("""
            {"metadata":{"appVersion":"1.5.1","exportDate":"2026-01-01T00:00:00Z","format":"json"},
             "gearItems":[],"practiceSessions":[],"practiceTemplates":[],"tensionCalculations":[],"customMaterials":[]}
            """.utf8)
        #expect(throws: ImportError.self) { try ImportDocument.decode(otherAppExport) }
        #expect(throws: ImportError.self) { try ImportDocument.decode(Data("not json".utf8)) }
    }

    @Test func rejectsFilesFromANewerFormat() throws {
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        var data = service.buildExportData(configuration: .init(format: .json), library: .empty)
        data.formatVersion = LibraryExport.currentFormatVersion + 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = try encoder.encode(data)
        do {
            _ = try ImportDocument.decode(file)
            Issue.record("A newer format should be rejected")
        } catch ImportError.newerFormat {
            // Expected.
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    // MARK: - CSV and PDF

    @Test func csvHasAHeaderAndOneRowPerItem() async throws {
        let source = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: source.mainContext)
        let lens = TestSupport.insertSampleLens(into: source.mainContext)
        try source.mainContext.save()
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        let csv = service.buildCSV(service.buildExportData(configuration: .init(format: .csv), library: gear([body, lens])))
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].contains("\"Serial Number\""))
        let bodyLine = try #require(lines.first { $0.contains("Z6 III") })
        #expect(bodyLine.contains("\"18500\""), "Latest shutter count")
        #expect(bodyLine.contains("\"On loan\""))
        #expect(bodyLine.contains("\"2499.99\""))
        let lensLine = try #require(lines.first { $0.contains("24-70") })
        #expect(lensLine.contains("\"24–70 mm\""))
        #expect(lensLine.contains("\"f/2.8\""))
    }

    @Test func pdfEntryListsTheIdentifyingDetails() throws {
        let container = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: container.mainContext)
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        let entry = service.pdfEntry(for: GearItemDTO(from: body, includePhotos: false), shutterCount: 18_500)
        #expect(entry.contains("Serial number: 3000123"))
        #expect(entry.contains("Mount: Nikon Z"))
        #expect(entry.contains("Format: Full frame"))
    }
}
