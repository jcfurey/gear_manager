//
//  ShootTests.swift
//  ShutterManagerTests
//
//  The shoot log, kits, shot lists and film rolls: their rules, and that export, import and
//  backups carry them with their links to gear.
//

import Foundation
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct ShootTests {
    private let day: TimeInterval = 86_400

    private func counts(_ progress: (Int, Int)) -> [Int] { [progress.0, progress.1] }

    private func encode(_ document: LibraryExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    private func export(_ library: LibraryContents) throws -> Data {
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        return try encode(service.buildExportData(configuration: .init(format: .json), library: library))
    }

    /// A body, a lens, a shoot with both and a shot list, a kit, a template and a roll in the body.
    private func insertSampleShootLibrary(into context: ModelContext) throws
        -> (body: GearItem, lens: GearItem, shoot: Shoot, kit: Kit, template: ShotListTemplate, roll: FilmRoll) {
        let body = TestSupport.insertSampleBody(into: context)
        let lens = TestSupport.insertSampleLens(into: context)
        let shoot = Shoot(title: "Harbour at dusk", startDate: Date(timeIntervalSince1970: 1_750_000_000),
                          endDate: Date(timeIntervalSince1970: 1_750_007_200), type: .landscape,
                          client: "Self", notes: "Bring the ND")
        shoot.place = PlaceValue(name: "Circular Quay", coordinate: GeoCoordinate(latitude: -33.861, longitude: 151.211),
                                 timeZoneIdentifier: "Australia/Sydney")
        shoot.goldenHourAlertMinutes = 30
        context.insert(shoot)
        shoot.gear = [body, lens]
        shoot.setPacked(true, for: body)
        context.insert(ShotListItem(shoot: shoot, title: "Bridge at blue hour", order: 0, isDone: true))
        context.insert(ShotListItem(shoot: shoot, title: "Ferry light trails", notes: "30 s at f/11", order: 1))
        let kit = Kit(name: "Landscape", notes: "Tripod too", symbol: "mountain.2")
        context.insert(kit)
        kit.gear = [lens]
        let template = ShotListTemplate(name: "City night", notes: "Long exposures")
        context.insert(template)
        context.insert(ShotListTemplateItem(template: template, title: "Skyline", order: 0))
        context.insert(ShotListTemplateItem(template: template, title: "Traffic trails", notes: "Overpass", order: 1))
        let roll = FilmRoll(filmStockID: "ilfordHP5Plus", formatID: SensorFormat.film35mm.id, ratedISO: 1600,
                            camera: body, loadedDate: Date(timeIntervalSince1970: 1_749_900_000))
        roll.pushPullStops = 2
        roll.framesShot = 20
        roll.lab = "Home"
        roll.notes = "Push two stops"
        roll.shoot = shoot
        context.insert(roll)
        try context.save()
        return (body, lens, shoot, kit, template, roll)
    }

    // MARK: - Rules

    @Test func shootDefaultsPlaceAndTitle() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let shoot = Shoot(startDate: start)
        #expect(shoot.endDate == start.addingTimeInterval(Constants.Shoots.defaultDuration))
        #expect(Shoot(startDate: start, endDate: start.addingTimeInterval(-60)).endDate == start, "The end never comes first")
        #expect(shoot.displayTitle == "Other")
        shoot.type = .wedding
        #expect(shoot.displayTitle == "Wedding")
        shoot.typeID = "underwaterPortrait"
        #expect(shoot.type == .other)
        #expect(shoot.typeID == "underwaterPortrait", "An ID from a newer version is kept")

        #expect(shoot.place == nil)
        #expect(shoot.timeZone == .current)
        shoot.place = PlaceValue(name: "Studio", coordinate: GeoCoordinate(latitude: 51.5, longitude: -0.1),
                                 timeZoneIdentifier: "Europe/London")
        #expect(shoot.place?.name == "Studio")
        #expect(shoot.timeZone.identifier == "Europe/London")
        shoot.latitude = 200
        #expect(shoot.place == nil, "Coordinates off the globe mean no place")
        shoot.place = nil
        #expect(shoot.latitude == nil && shoot.longitude == nil && shoot.placeName.isEmpty)

        #expect(shoot.isUpcoming(at: start))
        #expect(!shoot.isUpcoming(at: shoot.endDate.addingTimeInterval(1)))
    }

    @Test func packingTracksTheShootsGear() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        let lens = TestSupport.insertSampleLens(into: context)
        let shoot = Shoot(title: "Test")
        context.insert(shoot)
        shoot.gear = [body, lens]
        #expect(counts(shoot.packingProgress) == [0, 2])
        shoot.setPacked(true, for: lens)
        shoot.setPacked(true, for: body)
        #expect(counts(shoot.packingProgress) == [2, 2])
        #expect(shoot.packedGearIDs.split(separator: "\n").count == 2)
        shoot.setPacked(false, for: body)
        #expect(!shoot.isPacked(body) && shoot.isPacked(lens))
        shoot.gear = [body]
        #expect(counts(shoot.packingProgress) == [0, 1], "An item taken off the shoot stops counting")
        try context.save()
        #expect(body.shoots?.contains { $0.id == shoot.id } == true, "The gear side sees the shoot")
    }

    @Test func packingFlagsLoansServiceAndCleaning() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)  // Lent to Sam, cleaning overdue.
        let shoot = Shoot(title: "Test", startDate: Date().addingTimeInterval(day), endDate: Date().addingTimeInterval(3 * day))
        context.insert(shoot)
        var issues = body.packingIssues(for: shoot)
        #expect(issues.contains { $0.hasPrefix("Lent to Sam") })
        #expect(issues.contains("Sensor cleaning due"))
        #expect(!issues.contains("Needs service"))
        body.serviceNeeded = true
        #expect(body.packingIssues(for: shoot).contains("Needs service"))

        let rental = TestSupport.insertSampleLens(into: context)
        context.insert(GearLoan(gearItem: rental, direction: .rentedIn, person: "Lens Rentals",
                                outDate: Date(), dueDate: Date().addingTimeInterval(2 * day)))
        try context.save()
        issues = rental.packingIssues(for: shoot)
        #expect(issues.count == 1 && issues[0].hasPrefix("Rental due back"), "A rental due back before the end")
        shoot.endDate = Date().addingTimeInterval(day)
        #expect(rental.packingIssues(for: shoot).isEmpty, "A rental kept past the shoot is fine")
    }

    @Test func kitsAddOnlyNewGear() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        let lens = TestSupport.insertSampleLens(into: context)
        let kit = Kit(name: "Everyday")
        context.insert(kit)
        kit.gear = [body, lens]
        let shoot = Shoot(title: "Test")
        context.insert(shoot)
        shoot.gear = [body]
        #expect(shoot.add(kit) == 1)
        #expect(shoot.add(kit) == 0)
        #expect(Set((shoot.gear ?? []).map(\.id)) == [body.id, lens.id])
        #expect(Kit().displayName == "Untitled Kit")
    }

    @Test func templatesAreCopiedNotLinked() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let shoot = Shoot(title: "Wedding")
        context.insert(shoot)
        shoot.appendShots(ShotListStarter.wedding.entries, in: context)
        let count = ShotListStarter.wedding.entries.count
        #expect(shoot.orderedShotList.count == count)
        #expect(shoot.orderedShotList.map(\.order) == Array(0..<count))

        shoot.orderedShotList.first?.isDone = true
        let template = shoot.saveShotList(asTemplateNamed: "  My wedding  ", in: context)
        try context.save()
        #expect(template.name == "My wedding")
        #expect(template.entries.map(\.title) == shoot.orderedShotList.map(\.title))

        let second = Shoot(title: "Another")
        context.insert(second)
        second.appendShots(template.entries, in: context)
        try context.save()
        #expect(counts(second.shotListProgress) == [0, count], "Ticks aren't copied")
        template.orderedItems.first?.title = "Changed later"
        #expect(second.orderedShotList.first?.title != "Changed later", "Editing a template leaves shoots alone")

        for starter in ShotListStarter.allCases {
            #expect(!starter.entries.isEmpty, "\(starter.displayName) has shots")
        }
    }

    @Test func filmRollStatusAndSpeeds() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let camera = GearItem(category: .cameraBody, make: "Nikon", model: "FM2")
        context.insert(camera)
        let roll = FilmRoll(filmStockID: "ilfordHP5Plus", formatID: SensorFormat.film35mm.id, camera: camera)
        context.insert(roll)
        #expect(roll.frameCount == 36)
        #expect(roll.meteringISO == 400, "Box speed when no rating is set")
        #expect(roll.ratedStopsFromBox == nil)
        roll.ratedISO = 1600
        #expect(roll.meteringISO == 1600)
        #expect(roll.ratedStopsFromBox == 2)
        roll.pushPullStops = 2
        #expect(roll.pushPullText == "Push +2")
        roll.pushPullStops = -1
        #expect(roll.pushPullText == "Pull −1")
        roll.pushPullStops = 0
        #expect(roll.pushPullText == nil)

        try context.save()
        #expect(camera.loadedRoll?.id == roll.id)
        let later = Date().addingTimeInterval(60)
        roll.setStatus(.shot, at: later)
        #expect(roll.finishedDate == later)
        roll.setStatus(.atLab, at: later.addingTimeInterval(60))
        #expect(roll.finishedDate == later, "Coming out of the camera is stamped once")
        #expect(camera.loadedRoll == nil)
        roll.setStatus(.loaded)
        #expect(roll.finishedDate == nil)

        #expect(FilmRollStatus.loaded.next == .shot)
        #expect(FilmRollStatus.scanned.next == nil)
        roll.statusID = "framed"
        #expect(roll.status == .shot, "A status from a newer version is never the loaded roll")
        #expect(FilmRoll.defaultFrameCount(formatID: SensorFormat.film6x6.id) == 12)
        #expect(FilmRoll(formatID: SensorFormat.film6x7.id).frameCount == 10)
        #expect(FilmRoll().meteringISO == nil)
    }

    @Test func usageCountsShootsThatHaveStarted() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        let now = Date()
        let first = Shoot(title: "First", startDate: now.addingTimeInterval(-10 * day))
        let second = Shoot(title: "Second", startDate: now.addingTimeInterval(-2 * day))
        let planned = Shoot(title: "Planned", startDate: now.addingTimeInterval(5 * day))
        for shoot in [first, second, planned] {
            context.insert(shoot)
            shoot.gear = [body]
        }
        try context.save()
        #expect(body.pastShoots(at: now).count == 2)
        #expect(body.lastUsed(at: now) == second.startDate)
        #expect(body.nextShoot(at: now)?.id == planned.id)
        let lens = TestSupport.insertSampleLens(into: context)
        #expect(lens.lastUsed(at: now) == nil)
    }

    // MARK: - Deleting

    @Test func deletingUnlinksRatherThanCascadesAcrossTheLog() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let sample = try insertSampleShootLibrary(into: context)
        let rollID = sample.roll.id

        context.delete(sample.shoot)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<ShotListItem>()).isEmpty, "The shot list goes with its shoot")
        let roll = try #require(try context.fetch(FetchDescriptor<FilmRoll>()).first { $0.id == rollID })
        #expect(roll.shoot == nil, "The roll stays")
        #expect(try context.fetch(FetchDescriptor<GearItem>()).count == 2, "The gear stays")

        context.delete(sample.body)
        try context.save()
        #expect(roll.camera == nil, "Deleting the camera keeps the roll")
        context.delete(sample.lens)
        try context.save()
        #expect((sample.kit.gear ?? []).isEmpty, "Deleting gear takes it out of kits")
        #expect(try context.fetch(FetchDescriptor<Kit>()).count == 1)
    }

    // MARK: - Export, import, backups

    @Test func shootsKitsTemplatesAndRollsRoundTrip() async throws {
        let source = try TestSupport.makeContainer()
        let sample = try insertSampleShootLibrary(into: source.mainContext)
        let data = try export(try LibraryContents.fetch(from: source.mainContext))

        let destination = try TestSupport.makeContainer()
        let context = destination.mainContext
        let service = DataImportService(settingsStore: TestSupport.makeDefaults())
        try await service.importData(from: data, to: context, strategy: .replace)
        try await service.importData(from: data, to: context, strategy: .merge)

        let shoots = try context.fetch(FetchDescriptor<Shoot>())
        #expect(shoots.count == 1, "Merging again adds nothing")
        let shoot = try #require(shoots.first)
        #expect(shoot.id == sample.shoot.id)
        #expect(shoot.title == "Harbour at dusk")
        #expect(shoot.type == .landscape)
        #expect(shoot.client == "Self" && shoot.notes == "Bring the ND")
        #expect(shoot.startDate == sample.shoot.startDate && shoot.endDate == sample.shoot.endDate)
        #expect(shoot.place?.name == "Circular Quay")
        #expect(shoot.place?.coordinate.latitude == -33.861)
        #expect(shoot.timeZone.identifier == "Australia/Sydney")
        #expect(shoot.goldenHourAlertMinutes == 30)
        #expect(Set((shoot.gear ?? []).map(\.id)) == [sample.body.id, sample.lens.id])
        #expect(shoot.packedIDs == [sample.body.id])
        #expect(shoot.orderedShotList.map(\.title) == ["Bridge at blue hour", "Ferry light trails"])
        #expect(shoot.orderedShotList.map(\.isDone) == [true, false])
        #expect(shoot.orderedShotList.last?.notes == "30 s at f/11")
        #expect(try context.fetch(FetchDescriptor<ShotListItem>()).count == 2)

        let kit = try #require(try context.fetch(FetchDescriptor<Kit>()).first)
        #expect(kit.name == "Landscape" && kit.symbol == "mountain.2" && kit.notes == "Tripod too")
        #expect(kit.gear?.map(\.id) == [sample.lens.id])

        let template = try #require(try context.fetch(FetchDescriptor<ShotListTemplate>()).first)
        #expect(template.name == "City night" && template.notes == "Long exposures")
        #expect(template.entries == [ShotListEntry(title: "Skyline"), ShotListEntry(title: "Traffic trails", notes: "Overpass")])
        #expect(try context.fetch(FetchDescriptor<ShotListTemplateItem>()).count == 2)

        let roll = try #require(try context.fetch(FetchDescriptor<FilmRoll>()).first)
        #expect(roll.filmStockID == "ilfordHP5Plus" && roll.formatID == SensorFormat.film35mm.id)
        #expect(roll.ratedISO == 1600 && roll.pushPullStops == 2)
        #expect(roll.frameCount == 36 && roll.framesShot == 20)
        #expect(roll.status == .loaded && roll.lab == "Home" && roll.notes == "Push two stops")
        #expect(roll.camera?.id == sample.body.id)
        #expect(roll.shoot?.id == sample.shoot.id)
        #expect(roll.camera?.loadedRoll?.id == roll.id)
    }

    @Test func mergeLinksToGearAlreadyInTheLibrary() async throws {
        let source = try TestSupport.makeContainer()
        let sample = try insertSampleShootLibrary(into: source.mainContext)
        // A file with the shoot and roll but no gear.
        var library = try LibraryContents.fetch(from: source.mainContext)
        library.gearItems = []
        let data = try export(library)

        let destination = try TestSupport.makeContainer()
        let context = destination.mainContext
        let service = DataImportService(settingsStore: TestSupport.makeDefaults())
        // The library already has the gear (from an earlier import of the same source).
        try await service.importData(from: try export(LibraryContents(gearItems: [sample.body, sample.lens],
                                                                      developmentRecipes: [])),
                                     to: context, strategy: .replace)
        try await service.importData(from: data, to: context, strategy: .merge)
        let shoot = try #require(try context.fetch(FetchDescriptor<Shoot>()).first)
        #expect((shoot.gear ?? []).count == 2, "The shoot links to the library's own gear")
        let roll = try #require(try context.fetch(FetchDescriptor<FilmRoll>()).first)
        #expect(roll.camera?.id == sample.body.id)

        // Gear the file names but nobody has is dropped, not invented.
        let empty = try TestSupport.makeContainer()
        try await service.importData(from: data, to: empty.mainContext, strategy: .replace)
        let orphan = try #require(try empty.mainContext.fetch(FetchDescriptor<Shoot>()).first)
        #expect((orphan.gear ?? []).isEmpty)
        #expect(try empty.mainContext.fetch(FetchDescriptor<GearItem>()).isEmpty)
    }

    @Test func unusableNumbersAreDroppedSoBackupsStillWork() async throws {
        let source = try TestSupport.makeContainer()
        let sample = try insertSampleShootLibrary(into: source.mainContext)
        sample.shoot.latitude = .nan
        sample.roll.pushPullStops = .infinity
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        let document = service.buildExportData(configuration: .init(format: .json),
                                               library: try LibraryContents.fetch(from: source.mainContext))
        #expect(service.lastReplacedValueCount == 2)
        try ImportDocument.validate(document)

        let destination = try TestSupport.makeContainer()
        try await DataImportService(settingsStore: TestSupport.makeDefaults()).importData(
            from: try encode(document), to: destination.mainContext, strategy: .replace)
        let shoot = try #require(try destination.mainContext.fetch(FetchDescriptor<Shoot>()).first)
        #expect(shoot.place == nil && shoot.latitude == nil, "Half a coordinate is no place")
        #expect(try destination.mainContext.fetch(FetchDescriptor<FilmRoll>()).first?.pushPullStops == 0)
    }

    @Test func libraryContentsCountsAndDeleteCoverTheLog() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        _ = try insertSampleShootLibrary(into: context)
        let library = try LibraryContents.fetch(from: context)
        #expect(library.shoots.count == 1 && library.kits.count == 1)
        #expect(library.shotListTemplates.count == 1 && library.filmRolls.count == 1)
        // The body's 5 child records, then shoot + 2 shots, kit, template + 2 items, roll.
        #expect(library.otherRecordCount == 5 + 3 + 1 + 3 + 1)

        let document = DataExportService(settingsStore: TestSupport.makeDefaults())
            .buildExportData(configuration: .init(format: .json), library: library)
        #expect(document.recordCount == 2 + 5 + 3 + 1 + 3 + 1)

        try context.deleteEveryRecord()
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Shoot>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ShotListItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Kit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ShotListTemplateItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FilmRoll>()).isEmpty)
    }

    @Test func importPreviewCountsTheLog() throws {
        let container = try TestSupport.makeContainer()
        _ = try insertSampleShootLibrary(into: container.mainContext)
        let document = DataExportService(settingsStore: TestSupport.makeDefaults())
            .buildExportData(configuration: .init(format: .json), library: try LibraryContents.fetch(from: container.mainContext))
        let preview = ImportPreview(fileName: "test.json", document: document)
        #expect(preview.shootCount == 1 && preview.kitCount == 1 && preview.templateCount == 1 && preview.filmRollCount == 1)
    }
}
