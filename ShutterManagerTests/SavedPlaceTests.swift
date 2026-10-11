//
//  SavedPlaceTests.swift
//  ShutterManagerTests
//
//  Saved places: the planner's stored selection, and that export, import and backups carry them.
//

import Foundation
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct SavedPlaceTests {
    private func export(places: [SavedPlace]) throws -> Data {
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        let document = service.buildExportData(configuration: .init(format: .json),
                                               library: LibraryContents(gearItems: [], developmentRecipes: [],
                                                                        savedPlaces: places))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    private func samplePlace() -> SavedPlace {
        SavedPlace(name: "Mesa Arch", coordinate: GeoCoordinate(latitude: 38.3895, longitude: -109.8679),
                   timeZoneIdentifier: "America/Denver", notes: "Sunrise through the arch")
    }

    @Test func placeValueRoundTripsThroughStorage() throws {
        let value = PlaceValue(name: "Home", coordinate: GeoCoordinate(latitude: -33.9, longitude: 151.2),
                               timeZoneIdentifier: "Australia/Sydney", savedPlaceID: UUID())
        let decoded = try #require(PlaceValue(stored: value.stored))
        #expect(decoded == value)
        #expect(decoded.timeZone.identifier == "Australia/Sydney")
        #expect(PlaceValue(stored: "") == nil)
        #expect(PlaceValue(stored: "{}") == nil)
        let offTheGlobe = PlaceValue(name: "Nowhere", coordinate: GeoCoordinate(latitude: 120, longitude: 0))
        #expect(PlaceValue(stored: offTheGlobe.stored) == nil)
        #expect(value.coordinateText == "33.9000° S, 151.2000° E")
        #expect(PlaceValue(name: "x", coordinate: GeoCoordinate(latitude: 0, longitude: 0)).timeZone == .current)
    }

    @Test func placesRoundTripThroughJSON() async throws {
        let source = try TestSupport.makeContainer()
        let place = samplePlace()
        source.mainContext.insert(place)
        try source.mainContext.save()
        let data = try export(places: [place])

        let destination = try TestSupport.makeContainer()
        let service = DataImportService(settingsStore: TestSupport.makeDefaults())
        try await service.importData(from: data, to: destination.mainContext, strategy: .merge)
        try await service.importData(from: data, to: destination.mainContext, strategy: .merge)
        let restored = try destination.mainContext.fetch(FetchDescriptor<SavedPlace>())
        #expect(restored.count == 1, "Merging twice keeps one copy")
        let first = try #require(restored.first)
        #expect(first.id == place.id)
        #expect(first.name == "Mesa Arch")
        #expect(first.latitude == 38.3895)
        #expect(first.longitude == -109.8679)
        #expect(first.timeZoneIdentifier == "America/Denver")
        #expect(first.notes == "Sunrise through the arch")
        #expect(first.value.savedPlaceID == place.id)

        try await service.importData(from: try export(places: []), to: destination.mainContext, strategy: .replace)
        #expect(try destination.mainContext.fetch(FetchDescriptor<SavedPlace>()).isEmpty)
    }

    @Test func unusableCoordinatesAreDroppedNotImported() async throws {
        let container = try TestSupport.makeContainer()
        let broken = samplePlace()
        broken.latitude = .nan
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        let document = service.buildExportData(configuration: .init(format: .json),
                                               library: LibraryContents(gearItems: [], developmentRecipes: [],
                                                                        savedPlaces: [broken, samplePlace()]))
        #expect(service.lastReplacedValueCount == 1)
        #expect(document.places.first?.latitude == nil)
        try ImportDocument.validate(document)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try await DataImportService(settingsStore: TestSupport.makeDefaults()).importData(
            from: try encoder.encode(document), to: container.mainContext, strategy: .replace)
        #expect(try container.mainContext.fetch(FetchDescriptor<SavedPlace>()).count == 1)
    }

    @Test func libraryContentsAndDeleteCoverPlaces() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        context.insert(samplePlace())
        try context.save()
        let library = try LibraryContents.fetch(from: context)
        #expect(library.savedPlaces.count == 1)
        #expect(library.otherRecordCount == 1)
        #expect(!library.isEmpty)
        try context.deleteEveryRecord()
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SavedPlace>()).isEmpty)
    }
}
