//
//  LibraryDeduplicatorTests.swift
//  ShutterManagerTests
//
//  Folding a library that holds its records twice back into one: what counts as a double, which
//  copy is kept, and what the kept copy takes over from the others.
//

import Foundation
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct LibraryDeduplicatorTests {
    /// Nonisolated: `insertCopy` reads it in a default argument, which is evaluated off the main actor.
    private nonisolated static let base = Date(timeIntervalSince1970: 1_750_000_000)

    /// The IDs of a small library: every copy of it made with these is a double of the others.
    private struct IDs {
        let body = UUID(), lens = UUID(), photo = UUID(), reading = UUID(), record = UUID(), reminder = UUID()
        let loan = UUID(), recipe = UUID(), step = UUID(), place = UUID(), shoot = UUID(), shot = UUID()
        let kit = UUID(), template = UUID(), templateItem = UUID(), roll = UUID()
    }

    /// One copy of the library, as its records.
    private struct Copy {
        let body: GearItem, lens: GearItem, shoot: Shoot, kit: Kit, roll: FilmRoll
        let recipe: DevelopmentRecipe, template: ShotListTemplate
    }

    /// Inserts one copy: a body with every kind of history, a lens, a recipe with a step, a
    /// place, a shoot with both items and a shot, a kit, a template and a roll.
    @discardableResult
    private func insertCopy(_ ids: IDs, into context: ModelContext, note: String = "", modified: Date = base) -> Copy {
        let body = GearItem(category: .cameraBody, make: "Nikon", model: "FM2", notes: note)
        body.id = ids.body
        body.dateModified = modified
        let lens = GearItem(category: .lens, make: "Nikon", model: "50mm f/1.8", notes: note)
        lens.id = ids.lens
        lens.dateModified = modified
        context.insert(body)
        context.insert(lens)

        let photo = GearPhoto(imageData: Data([1, 2, 3]), isPrimary: true)
        photo.id = ids.photo
        photo.gearItem = body
        context.insert(photo)
        let reading = ShutterCountReading(gearItem: body, date: Self.base, count: 1_000)
        reading.id = ids.reading
        context.insert(reading)
        let record = MaintenanceRecord(gearItem: body, type: .sensorCleaning, date: Self.base)
        record.id = ids.record
        context.insert(record)
        let reminder = MaintenanceReminder(gearItem: body, type: .firmwareUpdate, dueDate: Self.base)
        reminder.id = ids.reminder
        context.insert(reminder)
        let loan = GearLoan(gearItem: body, direction: .lentOut, person: "Sam", outDate: Self.base)
        loan.id = ids.loan
        context.insert(loan)

        let recipe = DevelopmentRecipe(name: "HP5", notes: note)
        recipe.id = ids.recipe
        recipe.dateModified = modified
        context.insert(recipe)
        let step = DevelopmentStep(recipe: recipe, name: "Developer", order: 0, durationSeconds: 390)
        step.id = ids.step
        context.insert(step)

        let place = SavedPlace(name: "Harbor")
        place.id = ids.place
        context.insert(place)

        let shoot = Shoot(title: "Harbor at dawn", startDate: Self.base, notes: note)
        shoot.id = ids.shoot
        shoot.dateModified = modified
        context.insert(shoot)
        shoot.gear = [body, lens]
        shoot.packedIDs = [ids.body]
        let shot = ShotListItem(shoot: shoot, title: "Boats")
        shot.id = ids.shot
        context.insert(shot)

        let kit = Kit(name: "Street")
        kit.id = ids.kit
        context.insert(kit)
        kit.gear = [body]

        let template = ShotListTemplate(name: "Portraits")
        template.id = ids.template
        context.insert(template)
        let templateItem = ShotListTemplateItem(template: template, title: "Headshot")
        templateItem.id = ids.templateItem
        context.insert(templateItem)

        let roll = FilmRoll(filmStockID: "ilfordHP5Plus", camera: body, loadedDate: Self.base)
        roll.id = ids.roll
        roll.shoot = shoot
        context.insert(roll)
        return Copy(body: body, lens: lens, shoot: shoot, kit: kit, roll: roll, recipe: recipe, template: template)
    }

    private func count<M: PersistentModel>(_ type: M.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<M>())
    }

    /// Every kind of record, counted, in a fixed order.
    private func counts(in context: ModelContext) throws -> [Int] {
        [try count(GearItem.self, in: context), try count(GearPhoto.self, in: context),
         try count(ShutterCountReading.self, in: context), try count(MaintenanceRecord.self, in: context),
         try count(MaintenanceReminder.self, in: context), try count(GearLoan.self, in: context),
         try count(DevelopmentRecipe.self, in: context), try count(DevelopmentStep.self, in: context),
         try count(SavedPlace.self, in: context), try count(Shoot.self, in: context),
         try count(ShotListItem.self, in: context), try count(Kit.self, in: context),
         try count(ShotListTemplate.self, in: context), try count(ShotListTemplateItem.self, in: context),
         try count(FilmRoll.self, in: context)]
    }

    private static let oneCopy = [2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]

    // MARK: - Finding

    @Test func aLibraryHeldOnceHasNothingToFold() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        insertCopy(IDs(), into: context)
        insertCopy(IDs(), into: context)  // Another library's worth, with its own IDs.
        try context.save()

        #expect(try LibraryDeduplicator.find(in: context).isEmpty)
        let removed = try LibraryDeduplicator.merge(in: context)
        #expect(removed.isEmpty)
        #expect(!context.hasChanges, "Nothing is touched when nothing is doubled")
        #expect(try counts(in: context) == Self.oneCopy.map { $0 * 2 })
    }

    @Test func doublesAreCountedByKind() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let ids = IDs()
        insertCopy(ids, into: context)
        insertCopy(ids, into: context)
        try context.save()

        let found = try LibraryDeduplicator.find(in: context)
        #expect(found == LibraryDeduplicator.Report(gear: 2, recipes: 1, places: 1, shoots: 1, kits: 1, templates: 1,
                                                    rolls: 1, parts: 8))
        #expect(found.total == 16)
        #expect(found.lines == ["2 gear items", "1 shoot", "1 kit", "1 film roll", "1 development recipe",
                                "1 shot-list template", "1 saved place", "8 photos, history records and list entries"])
        #expect(!context.hasChanges, "Looking changes nothing")
    }

    // MARK: - Folding

    @Test func aLibraryHeldTwiceFoldsBackToOne() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let ids = IDs()
        insertCopy(ids, into: context)
        insertCopy(ids, into: context)
        try context.save()
        #expect(try counts(in: context) == Self.oneCopy.map { $0 * 2 })

        let found = try LibraryDeduplicator.find(in: context)
        let removed = try LibraryDeduplicator.merge(in: context)
        try context.save()
        #expect(removed == found, "What's removed is what was counted")
        #expect(try counts(in: context) == Self.oneCopy)
        #expect(try LibraryDeduplicator.find(in: context).isEmpty)

        // What's left still hangs together.
        let body = try #require(try context.fetch(FetchDescriptor<GearItem>()).first { $0.gearCategory == .cameraBody })
        #expect(body.photos?.count == 1)
        #expect(body.shutterCountReadings?.count == 1)
        #expect(body.maintenanceRecords?.count == 1)
        #expect(body.maintenanceReminders?.count == 1)
        #expect(body.loans?.count == 1)
        let shoot = try #require(try context.fetch(FetchDescriptor<Shoot>()).first)
        #expect(Set((shoot.gear ?? []).map(\.id)) == [ids.body, ids.lens])
        #expect(shoot.gear?.count == 2)
        #expect(shoot.shotList?.count == 1)
        #expect(shoot.packedIDs == [ids.body])
        let kit = try #require(try context.fetch(FetchDescriptor<Kit>()).first)
        #expect(kit.gear?.count == 1)
        #expect(kit.gear?.first === body)
        let roll = try #require(try context.fetch(FetchDescriptor<FilmRoll>()).first)
        #expect(roll.camera === body)
        #expect(roll.shoot === shoot)
        #expect(body.shoots?.count == 1)
        #expect(body.kits?.count == 1)
        #expect(body.filmRolls?.count == 1)
    }

    @Test func threeCopiesFoldToOne() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let ids = IDs()
        for _ in 0..<3 { insertCopy(ids, into: context) }
        try context.save()
        #expect(try LibraryDeduplicator.find(in: context).total == 32)
        try LibraryDeduplicator.merge(in: context)
        try context.save()
        #expect(try counts(in: context) == Self.oneCopy)
    }

    @Test func theCopyChangedLastIsKept() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let ids = IDs()
        insertCopy(ids, into: context, note: "older", modified: Self.base)
        insertCopy(ids, into: context, note: "newer", modified: Self.base.addingTimeInterval(3600))
        insertCopy(ids, into: context, note: "oldest", modified: Self.base.addingTimeInterval(-3600))
        try context.save()

        try LibraryDeduplicator.merge(in: context)
        try context.save()
        let gear = try context.fetch(FetchDescriptor<GearItem>())
        #expect(gear.count == 2)
        #expect(gear.allSatisfy { $0.notes == "newer" })
        #expect(try #require(try context.fetch(FetchDescriptor<Shoot>()).first).notes == "newer")
        #expect(try #require(try context.fetch(FetchDescriptor<DevelopmentRecipe>()).first).notes == "newer")
    }

    /// The kept copy takes over history, list entries and gear that only another copy had.
    @Test func whatOnlyOneCopyHasIsKept() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let ids = IDs()
        let kept = insertCopy(ids, into: context, note: "kept", modified: Self.base.addingTimeInterval(60))
        let other = insertCopy(ids, into: context, note: "other")
        // Added to the other copy after the library was doubled.
        context.insert(ShutterCountReading(gearItem: other.body, date: Self.base.addingTimeInterval(86_400), count: 2_000))
        context.insert(ShotListItem(shoot: other.shoot, title: "Lighthouse", order: 1))
        context.insert(DevelopmentStep(recipe: other.recipe, name: "Fixer", order: 1, durationSeconds: 300))
        context.insert(ShotListTemplateItem(template: other.template, title: "Profile", order: 1))
        let flash = GearItem(category: .lighting, make: "Godox", model: "V1")
        context.insert(flash)
        other.shoot.gear = (other.shoot.gear ?? []) + [flash]
        other.shoot.packedIDs.insert(flash.id)
        other.kit.gear = (other.kit.gear ?? []) + [flash]
        try context.save()

        let removed = try LibraryDeduplicator.merge(in: context)
        try context.save()
        #expect(removed.gear == 2)
        #expect(removed.parts == 8, "The four new parts are kept, not counted as doubles")

        #expect(kept.body.notes == "kept")
        #expect(kept.body.shutterCountReadings?.count == 2)
        #expect(kept.body.latestShutterReading?.count == 2_000)
        #expect(kept.shoot.shotList?.count == 2)
        #expect(kept.recipe.steps?.count == 2)
        #expect(Set((kept.shoot.gear ?? []).map(\.id)) == [ids.body, ids.lens, flash.id])
        #expect(kept.shoot.gear?.count == 3)
        #expect(kept.shoot.packedIDs == [ids.body, flash.id])
        // A kit and a template keep no change date: the copy with more in it is the one kept.
        let kit = try #require(try context.fetch(FetchDescriptor<Kit>()).first)
        #expect(Set((kit.gear ?? []).map(\.id)) == [ids.body, flash.id])
        #expect(kit.gear?.count == 2)
        let template = try #require(try context.fetch(FetchDescriptor<ShotListTemplate>()).first)
        #expect(template.items?.count == 2)
        #expect(try count(GearItem.self, in: context) == 3)
        #expect(flash.shoots?.count == 1)
        #expect(flash.kits?.count == 1)
    }

    /// A shoot, a kit and a roll that aren't doubled themselves but point at the copy that goes.
    @Test func linksFollowTheKeptCopy() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let id = UUID()
        let kept = GearItem(category: .cameraBody, make: "Nikon", model: "FM2")
        kept.id = id
        kept.dateModified = Self.base.addingTimeInterval(60)
        let extra = GearItem(category: .cameraBody, make: "Nikon", model: "FM2")
        extra.id = id
        extra.dateModified = Self.base
        context.insert(kept)
        context.insert(extra)
        let shoot = Shoot(title: "Street")
        context.insert(shoot)
        shoot.gear = [extra]
        let both = Shoot(title: "Both")
        context.insert(both)
        both.gear = [extra, kept]
        let kit = Kit(name: "Everyday")
        context.insert(kit)
        kit.gear = [extra]
        let roll = FilmRoll(filmStockID: "kodakTriX400", camera: extra)
        context.insert(roll)
        try context.save()

        let removed = try LibraryDeduplicator.merge(in: context)
        try context.save()
        #expect(removed == LibraryDeduplicator.Report(gear: 1))
        #expect(shoot.gear?.count == 1)
        #expect(shoot.gear?.first === kept)
        #expect(both.gear?.count == 1, "On a shoot with both copies, the item is listed once")
        #expect(kit.gear?.first === kept)
        #expect(roll.camera === kept)
        #expect(kept.shoots?.count == 2)
        #expect(try count(GearItem.self, in: context) == 1)
    }

    /// A part doubled under one owner, with nothing else doubled, and one with no owner at all.
    @Test func aPartDoubledOnItsOwnIsRemoved() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        let readings = body.shutterCountReadings?.count ?? 0
        let id = UUID()
        for _ in 0..<2 {
            let reading = ShutterCountReading(gearItem: body, date: Self.base, count: 5_000)
            reading.id = id
            context.insert(reading)
        }
        let orphanID = UUID()
        for _ in 0..<2 {
            let step = DevelopmentStep(recipe: nil, name: "Stop", order: 0, durationSeconds: 10)
            step.id = orphanID
            context.insert(step)
        }
        try context.save()

        #expect(try LibraryDeduplicator.find(in: context) == LibraryDeduplicator.Report(parts: 2))
        let removed = try LibraryDeduplicator.merge(in: context)
        try context.save()
        #expect(removed == LibraryDeduplicator.Report(parts: 2))
        #expect(body.shutterCountReadings?.count == readings + 1)
        #expect(try count(DevelopmentStep.self, in: context) == 1)
        #expect(try count(GearItem.self, in: context) == 1)
    }

    /// A roll that names its camera is the fuller copy; a failed merge can be rolled back.
    @Test func theFullerRollIsKeptAndAMergeCanBeUndone() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        let id = UUID()
        let bare = FilmRoll(filmStockID: "ilfordHP5Plus")
        bare.id = id
        let loaded = FilmRoll(filmStockID: "ilfordHP5Plus", camera: body)
        loaded.id = id
        context.insert(bare)
        context.insert(loaded)
        try context.save()

        #expect(try LibraryDeduplicator.merge(in: context) == LibraryDeduplicator.Report(rolls: 1))
        context.rollback()
        #expect(try count(FilmRoll.self, in: context) == 2, "Rolled back, nothing is lost")

        try LibraryDeduplicator.merge(in: context)
        try context.save()
        let roll = try #require(try context.fetch(FetchDescriptor<FilmRoll>()).first)
        #expect(roll.camera === body)
        #expect(try count(FilmRoll.self, in: context) == 1)
    }

    // MARK: - The import screen's warning

    /// Importing is the moment a library gets doubled, so the import screen says when iCloud
    /// hasn't finished: while it's syncing, and before its first download since the app opened.
    @Test func importWarnsWhileICloudHasNotFinished() {
        let downloaded = Date()
        #expect(DataImportView.syncWarning(storageMode: .cloudKit, status: .syncing, lastDownload: downloaded)?
            .hasPrefix("iCloud is syncing now.") == true)
        #expect(DataImportView.syncWarning(storageMode: .cloudKit, status: .available, lastDownload: nil)?
            .hasPrefix("iCloud hasn't finished checking") == true)
        #expect(DataImportView.syncWarning(storageMode: .cloudKit, status: .available, lastDownload: downloaded) == nil)
        // Nothing to wait for: no iCloud, or no account.
        #expect(DataImportView.syncWarning(storageMode: .localOnly("offline"), status: .localOnly, lastDownload: nil) == nil)
        #expect(DataImportView.syncWarning(storageMode: .cloudKit, status: .noAccount, lastDownload: nil) == nil)
        #expect(DataImportView.syncWarning(storageMode: .opening, status: .unknown, lastDownload: nil) == nil)
    }

    @Test func aReportReadsInWords() {
        #expect(LibraryDeduplicator.Report().lines.isEmpty)
        #expect(LibraryDeduplicator.Report(gear: 1, parts: 1).lines == ["1 gear item", "1 photo, history record or list entry"])
        #expect(LibraryDeduplicator.Report(recipes: 2, places: 3, templates: 4).lines
                == ["2 development recipes", "4 shot-list templates", "3 saved places"])
    }
}
