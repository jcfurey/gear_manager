//
//  PhotoUsageRecorderTests.swift
//  ShutterManagerTests
//
//  Usage from Photos in the app: reading real files and folders, remembering matches, and what a
//  save writes.
//

import Foundation
import ImageIO
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct PhotoUsageRecorderTests {
    private static let start = Date(timeIntervalSince1970: 1_750_000_000)

    private static func shot(_ model: String = "Z6_3", serial: String? = "3000123", lens: String? = "NIKKOR Z 24-70mm f/2.8 S",
                             count: Int? = nil, minutes: Double = 0) -> PhotoUsageSample {
        PhotoUsageSample(cameraMake: "Nikon", cameraModel: model, bodySerialNumber: serial, lensMake: "Nikon",
                         lensModel: lens, lensSerialNumber: nil, shutterCount: count,
                         dateTaken: start.addingTimeInterval(minutes * 60))
    }

    private static func candidates(_ items: [GearItem]) -> [PhotoUsageCandidate] {
        items.map {
            PhotoUsageCandidate(id: $0.id, make: $0.make ?? "", model: $0.model ?? "",
                                serialNumber: $0.serialNumber ?? "", category: $0.gearCategory)
        }
    }

    /// A library with the sample body and lens, and a batch they took: 3 shots, the last at 20,500.
    private func library() throws -> (context: ModelContext, body: GearItem, lens: GearItem, summary: PhotoUsageSummary) {
        let context = ModelContext(try TestSupport.makeContainer())
        let body = TestSupport.insertSampleBody(into: context)
        let lens = TestSupport.insertSampleLens(into: context)
        try context.save()
        let samples = [Self.shot(count: 20_300, minutes: 0), Self.shot(count: 20_400, minutes: 30),
                       Self.shot(count: 20_500, minutes: 60)]
        let summary = PhotoUsageSummary(samples: samples, candidates: Self.candidates([body, lens]))
        return (context, body, lens, summary)
    }

    private func makeRecorder(_ summary: PhotoUsageSummary) -> PhotoUsageRecorder {
        PhotoUsageRecorder(summary: summary, assignments: PhotoUsageRecorder.initialAssignments(for: summary))
    }

    // MARK: - Reading files

    private static func writePhoto(named name: String, in folder: URL, model: String = "X-T5",
                                   serial: String = "5AB12345") throws {
        let data = try PhotoMetadataTests.jpeg(properties: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "FUJIFILM", kCGImagePropertyTIFFModel: model],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifBodySerialNumber: serial,
                                             kCGImagePropertyExifLensModel: "XF23mmF1.4 R LM WR",
                                             kCGImagePropertyExifDateTimeOriginal: "2026:05:03 10:15:00"]
        ])
        try data.write(to: folder.appendingPathComponent(name))
    }

    @Test func aFileIsReadWithoutLoadingIt() throws {
        let folder = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.writePhoto(named: "DSCF0001.JPG", in: folder)

        let sample = try #require(PhotoUsageReader.sample(at: folder.appendingPathComponent("DSCF0001.JPG")))
        #expect(sample.cameraMake == "Fujifilm")
        #expect(sample.cameraModel == "X-T5")
        #expect(sample.bodySerialNumber == "5AB12345")
        #expect(sample.lensModel == "XF23mmF1.4 R LM WR")
        #expect(sample.dateTaken != nil)
        #expect(sample.shutterCount == nil)
    }

    @Test func whatIsNotAPhotoReadsAsNothing() throws {
        let folder = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: fake)
        #expect(PhotoUsageReader.sample(at: fake) == nil)
        #expect(PhotoUsageReader.sample(at: folder.appendingPathComponent("missing.jpg")) == nil)
    }

    /// A folder is searched all the way down; a raw file and its JPEG count once; other files,
    /// hidden ones included, are left alone.
    @Test func aFolderGivesOneFilePerShot() throws {
        let folder = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let card = folder.appendingPathComponent("DCIM/100NIKON")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        for name in ["DSC_0001.NEF", "DSC_0001.JPG", "DSC_0002.JPG", "DSC_0003.heic", "notes.txt", "clip.mov", ".hidden.jpg"] {
            try Data([0]).write(to: card.appendingPathComponent(name))
        }
        // The same name in another folder is another shot.
        try Data([0]).write(to: folder.appendingPathComponent("DSC_0001.JPG"))

        let listing = PhotoUsageReader.imageFiles(in: [folder])
        #expect(!listing.wasCutShort)
        let names = listing.files.map { $0.deletingPathExtension().lastPathComponent }.sorted()
        #expect(names == ["DSC_0001", "DSC_0001", "DSC_0002", "DSC_0003"])

        // Files chosen one by one pair up the same way, and a limit says it cut the list short.
        let chosen = ["DSC_0001.NEF", "DSC_0001.JPG", "DSC_0002.JPG"].map { card.appendingPathComponent($0) }
        #expect(PhotoUsageReader.imageFiles(in: chosen).files.count == 2)
        let limited = PhotoUsageReader.imageFiles(in: [folder], limit: 2)
        #expect(limited.files.count == 2)
        #expect(limited.wasCutShort)
        #expect(!PhotoUsageReader.imageFiles(in: chosen, limit: 2).wasCutShort, "Exactly the limit isn't cut short")
    }

    @Test func aFolderOfPhotosBecomesATally() async throws {
        let folder = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.writePhoto(named: "DSCF0001.JPG", in: folder)
        try Self.writePhoto(named: "DSCF0002.JPG", in: folder)
        try Self.writePhoto(named: "DSCF0003.JPG", in: folder, model: "X100VI", serial: "6CD00001")
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("DSCF0004.JPG"))

        let importer = PhotoUsageImporter()
        importer.read(files: [folder])
        var batch: PhotoUsageImporter.Batch?
        for _ in 0..<200 {
            if case .finished(let finished) = importer.state {
                batch = finished
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let read = try #require(batch, "The importer finishes")
        #expect(read.samples.count == 3)
        #expect(read.unreadableCount == 1)

        let summary = PhotoUsageSummary(samples: read.samples, candidates: [])
        #expect(summary.cameras.map(\.photoCount) == [2, 1])
        #expect(summary.lenses.map(\.photoCount) == [3])

        importer.cancel()
        #expect(importer.state == .idle)
    }

    // MARK: - Remembered matches

    @Test func aChosenMatchIsRememberedAndForgotten() {
        let store = PhotoUsageMatchStore(defaults: TestSupport.makeDefaults())
        let id = UUID()
        #expect(store.load().isEmpty)
        store.remember(id, for: "camera|sony|ilce7m4|")
        store.remember(UUID(), for: "lens||fe50mmf12gm|")
        #expect(store.load()["camera|sony|ilce7m4|"] == id)
        #expect(store.load().count == 2)
        store.remember(nil, for: "camera|sony|ilce7m4|")
        #expect(store.load()["camera|sony|ilce7m4|"] == nil)
        #expect(store.load().count == 1)
    }

    @Test func rememberedMatchesStayBounded() {
        let store = PhotoUsageMatchStore(defaults: TestSupport.makeDefaults())
        let limit = Constants.PhotoUsage.maximumRememberedMatches
        for index in 0..<(limit + 5) { store.remember(UUID(), for: "lens||lens\(index)|") }
        let latest = UUID()
        store.remember(latest, for: "lens||newest|")
        #expect(store.load().count == limit)
        #expect(store.load()["lens||newest|"] == latest, "The match just chosen is never the one dropped")
    }

    // MARK: - Saving

    @Test func matchedGearStartsAssigned() throws {
        let (_, body, lens, summary) = try library()
        let assignments = PhotoUsageRecorder.initialAssignments(for: summary)
        #expect(assignments[summary.cameras[0].key] == .item(body.id))
        #expect(assignments[summary.lenses[0].key] == .item(lens.id), "\"NIKKOR Z 24-70mm f/2.8 S\" is the item \"Z 24-70mm f/2.8 S\"")
    }

    @Test func aBodysShutterCountIsRecordedOnce() throws {
        let (context, body, _, summary) = try library()
        let recorder = makeRecorder(summary)
        #expect(recorder.preview(items: [body]).readingsAdded == 1)

        let everything = try context.fetch(FetchDescriptor<GearItem>())
        let outcome = try #require(recorder.save(in: context, items: everything))
        #expect(outcome == PhotoUsageRecorder.Outcome(gearAdded: 0, readingsAdded: 1, gearLinked: 0, shootAdded: false))
        let latest = try #require(body.latestShutterReading)
        #expect(latest.count == 20_500)
        #expect(latest.source == .photo)
        #expect(latest.date == Self.start.addingTimeInterval(3600), "Dated by the photo, not by today")
        #expect(body.shutterCountReadings?.count == 3)

        // The same photos again add nothing.
        let again = try #require(recorder.save(in: context, items: everything))
        #expect(again.isEmpty)
        #expect(body.shutterCountReadings?.count == 3)
    }

    @Test func shutterCountsCanBeLeftOut() throws {
        let (context, body, _, summary) = try library()
        var recorder = makeRecorder(summary)
        recorder.recordsShutterCounts = false
        let outcome = try #require(recorder.save(in: context, items: [body]))
        #expect(outcome.isEmpty)
        #expect(body.shutterCountReadings?.count == 2)
    }

    /// A reading belongs to a body: a count is never put on a lens or a drone.
    @Test func onlyABodyGetsAReading() throws {
        let context = ModelContext(try TestSupport.makeContainer())
        let drone = GearItem(category: .drone, make: "Nikon", model: "Z6 III")
        context.insert(drone)
        try context.save()
        let summary = PhotoUsageSummary(samples: [Self.shot(count: 900)], candidates: Self.candidates([drone]))
        #expect(summary.cameras[0].match == .item(drone.id))
        #expect(makeRecorder(summary).preview(items: [drone]).readingsAdded == 0)
    }

    @Test func gearTheInventoryLacksCanBeAdded() throws {
        let context = ModelContext(try TestSupport.makeContainer())
        let samples = [Self.shot(count: 150, minutes: 5), Self.shot(count: 149, minutes: 0)]
        let summary = PhotoUsageSummary(samples: samples, candidates: [])
        var recorder = makeRecorder(summary)
        #expect(recorder.preview(items: []).isEmpty, "Nothing is added unless the user asks")
        for group in summary.groups { recorder.assignments[group.key] = .new }

        let outcome = try #require(recorder.save(in: context, items: []))
        #expect(outcome == PhotoUsageRecorder.Outcome(gearAdded: 2, readingsAdded: 1, gearLinked: 0, shootAdded: false))
        let items = try context.fetch(FetchDescriptor<GearItem>())
        let body = try #require(items.first { $0.gearCategory == .cameraBody })
        #expect(body.make == "Nikon")
        #expect(body.model == "Z6_3")
        #expect(body.serialNumber == "3000123")
        #expect(body.latestShutterReading?.count == 150)
        let lens = try #require(items.first { $0.gearCategory == .lens })
        #expect(lens.model == "NIKKOR Z 24-70mm f/2.8 S")
        #expect(lens.shutterCountReadings?.isEmpty != false)

        // The next batch finds them by name and serial number.
        let next = PhotoUsageSummary(samples: samples, candidates: Self.candidates(items))
        #expect(next.cameras[0].match == .item(body.id))
        #expect(next.lenses[0].match == .item(lens.id))
    }

    @Test func aBatchCanBeLoggedAsAShoot() throws {
        let (context, body, lens, summary) = try library()
        var recorder = makeRecorder(summary)
        recorder.shoot = .new(title: "  Harbor at dawn ")
        #expect(recorder.preview(items: [body, lens]).parts == ["record 1 shutter count", "log a shoot with 2 items"])

        let outcome = try #require(recorder.save(in: context, items: [body, lens]))
        #expect(outcome.shootAdded)
        #expect(outcome.gearLinked == 2)
        let shoot = try #require(try context.fetch(FetchDescriptor<Shoot>()).first)
        #expect(shoot.title == "Harbor at dawn")
        #expect(shoot.startDate == Self.start)
        #expect(shoot.endDate == Self.start.addingTimeInterval(3600))
        #expect(Set((shoot.gear ?? []).map(\.id)) == [body.id, lens.id])
        #expect(shoot.notes == "Logged from 3 photos.")
        // The log is where an item's use is counted from.
        #expect(body.pastShoots(at: Self.start.addingTimeInterval(86_400)).count == 1)
        #expect(lens.lastUsed(at: Self.start.addingTimeInterval(86_400)) == Self.start)
    }

    @Test func undatedPhotosCannotBecomeAShoot() throws {
        let (context, body, _, _) = try library()
        var sample = Self.shot()
        sample.dateTaken = nil
        let summary = PhotoUsageSummary(samples: [sample], candidates: Self.candidates([body]))
        var recorder = makeRecorder(summary)
        recorder.shoot = .new(title: "Undated")
        #expect(recorder.preview(items: [body]).isEmpty)
        let outcome = try #require(recorder.save(in: context, items: [body]))
        #expect(outcome.isEmpty)
        let shoots = try context.fetch(FetchDescriptor<Shoot>())
        #expect(shoots.isEmpty)
    }

    @Test func gearUsedIsAddedToAnExistingShoot() throws {
        let (context, body, lens, summary) = try library()
        let shoot = Shoot(title: "Wedding", startDate: Self.start)
        context.insert(shoot)
        shoot.gear = [body]
        shoot.packedIDs = [body.id]
        try context.save()

        var recorder = makeRecorder(summary)
        recorder.recordsShutterCounts = false
        recorder.shoot = .existing(shoot)
        #expect(recorder.preview(items: [body, lens]).parts == ["add 1 item to the shoot"])
        let outcome = try #require(recorder.save(in: context, items: [body, lens]))
        #expect(outcome.gearLinked == 1, "The body was already on it")
        #expect(Set((shoot.gear ?? []).map(\.id)) == [body.id, lens.id])
        #expect(shoot.packedIDs == [body.id], "Packing ticks are left alone")
        let shoots = try context.fetch(FetchDescriptor<Shoot>())
        #expect(shoots.count == 1)

        // Again: everything is already there.
        #expect(recorder.preview(items: [body, lens]).isEmpty)
    }

    @Test func gearLeftOutIsNotWritten() throws {
        let (context, body, lens, summary) = try library()
        var recorder = makeRecorder(summary)
        recorder.assignments[summary.cameras[0].key] = .leftOut
        recorder.shoot = .new(title: "Lens only")
        let outcome = try #require(recorder.save(in: context, items: [body, lens]))
        #expect(outcome.readingsAdded == 0)
        #expect(outcome.gearLinked == 1)
        #expect(body.shutterCountReadings?.count == 2)
        let shoot = try #require(try context.fetch(FetchDescriptor<Shoot>()).first)
        #expect((shoot.gear ?? []).map(\.id) == [lens.id])
    }

    /// An assignment to an item that's since been deleted is ignored, not a crash.
    @Test func anItemThatIsGoneIsSkipped() throws {
        let (context, body, lens, summary) = try library()
        let recorder = makeRecorder(summary)
        let outcome = try #require(recorder.save(in: context, items: [lens]))
        #expect(outcome.isEmpty)
        #expect(body.shutterCountReadings?.count == 2)
    }

    @Test func whatASaveWritesReadsAsASentence() {
        typealias Outcome = PhotoUsageRecorder.Outcome
        #expect(Outcome().parts.isEmpty)
        #expect(Outcome(gearAdded: 1, readingsAdded: 2, gearLinked: 3, shootAdded: false).parts
                == ["add 1 item to your inventory", "record 2 shutter counts", "add 3 items to the shoot"])
        #expect(Outcome(gearAdded: 2, readingsAdded: 0, gearLinked: 0, shootAdded: true).parts
                == ["add 2 items to your inventory", "log a shoot"])
    }

    // MARK: - The screen's text

    @Test func theBatchSaysWhatItLeftOut() {
        var batch = PhotoUsageImporter.Batch()
        var summary = PhotoUsageSummary()
        #expect(PhotoUsageView.notes(for: summary, batch: batch).isEmpty)

        batch.wasCutShort = true
        batch.unreadableCount = 2
        summary.photoCount = 10
        summary.unnamedCameraCount = 1
        summary.unnamedLensCount = 4
        let notes = PhotoUsageView.notes(for: summary, batch: batch)
        #expect(notes.count == 4)
        #expect(notes[0].contains(Constants.PhotoUsage.maximumPhotos.formatted()))
        #expect(notes[1].hasPrefix("2 photos couldn't be read"))
        #expect(notes[2] == "1 photo doesn't say which camera took it.")
        #expect(notes[3].hasPrefix("4 photos don't name a lens"))
    }

    @Test func datesReadAsADayOrARange() {
        let day = Self.start
        #expect(PhotoUsageView.dateRange(nil, nil) == nil)
        #expect(PhotoUsageView.dateRange(day, nil) == day.formatted(date: .abbreviated, time: .omitted))
        #expect(PhotoUsageView.dateRange(day, day.addingTimeInterval(60)) == day.formatted(date: .abbreviated, time: .omitted))
        let range = PhotoUsageView.dateRange(day, day.addingTimeInterval(5 * 86_400))
        #expect(range != nil)
        #expect(range != day.formatted(date: .abbreviated, time: .omitted), "Five days read as a range")
        #expect(PhotoUsageView.detail(for: PhotoUsageGroup(kind: .camera, make: "Nikon", model: "Z8", serialNumber: "42"))
                .hasSuffix("Serial number 42"))
    }
}
