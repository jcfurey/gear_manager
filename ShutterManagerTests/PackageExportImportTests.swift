//
//  PackageExportImportTests.swift
//  ShutterManagerTests
//
//  A library exported as a package and brought back: the records as JSON, each photo as a file,
//  written and read a few at a time. Merging fills in missing photos, an import that stops
//  part-way can be run again, and the JSON files earlier versions wrote still import.
//

import Foundation
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct PackageExportImportTests {
    private static func jpeg(_ fill: UInt8, count: Int = 2_000) -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: fill, count: count)
    }

    /// A body with three gallery photos (the first the cover, the second captioned) and a photo
    /// on its maintenance record, saved.
    private func makeLibrary() throws -> (container: ModelContainer, body: GearItem) {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        body.appendGalleryPhoto(Self.jpeg(1), in: context)
        body.appendGalleryPhoto(Self.jpeg(2), in: context).caption = "Top plate"
        body.appendGalleryPhoto(Self.jpeg(3), in: context)
        try context.save()
        let record = try #require(body.maintenanceRecords?.first)
        record.photoData = Self.jpeg(9)
        try context.save()
        return (container, body)
    }

    /// Small lots, so three photos take more than one.
    private func exporter(maximumPackageBytes: Int = Constants.DataLimits.maximumPackageBytes) -> DataExportService {
        DataExportService(settingsStore: TestSupport.makeDefaults(), maximumPackageBytes: maximumPackageBytes, photoBatch: 2)
    }

    private func importer() -> DataImportService {
        DataImportService(settingsStore: TestSupport.makeDefaults(), photoBatch: 2)
    }

    private func exportPackage(_ items: [GearItem], photos: Bool = true) async throws -> URL {
        var configuration = DataExportService.ExportConfiguration(format: .json)
        configuration.includePhotos = photos
        return try await exporter().exportLibrary(configuration: configuration,
                                                  library: LibraryContents(gearItems: items, developmentRecipes: []))
    }

    /// Imports the file at `url` the way the import screen does once it has access to it. (The
    /// screen's own entry point takes a file-picker URL, which a test's scratch file isn't.)
    private func importFile(_ url: URL, into context: ModelContext, strategy: ImportStrategy,
                            with service: DataImportService? = nil) async throws {
        try await (service ?? importer()).apply(try ImportDocument.open(url), to: context, strategy: strategy)
    }

    /// The error an import or an opening threw, if it was one of the import's own.
    private func importError(_ work: () async throws -> Void) async -> ImportError? {
        do {
            try await work()
            return nil
        } catch let error as ImportError {
            return error
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }

    // MARK: - What a package holds

    @Test func aPackageHoldsTheRecordsAndEachPhotoAsAFile() async throws {
        let (container, body) = try makeLibrary()
        let url = try await exportPackage([body])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.pathExtension == "zip")
        #expect(LibraryPackage.looksLikePackage(url))

        let file = try ImportDocument.open(url)
        #expect(file.package != nil)
        #expect(file.photoCount == 3)
        #expect(file.includesPhotos)
        // The records carry no photos of their own: those are files beside them.
        #expect(file.document.gearItems.count == 1)
        #expect(file.document.gearItems[0].photos == nil)
        #expect(file.document.maintenanceRecords[0].photoData == nil)
        #expect(!file.document.includesPhotos, "The JSON alone, lifted out of the zip, says it has none")
        #expect(file.document.loans.count == 1)

        let index = try #require(file.package?.photoIndex)
        #expect(index.photos.count == 3)
        #expect(index.photos.allSatisfy { $0.gearItemID == body.id })
        #expect(index.photos.map(\.order) == [0, 1, 2], "In gallery order")
        #expect(index.photos.map(\.isPrimary) == [true, false, false])
        #expect(index.photos.map(\.caption) == [nil, "Top plate", nil])
        #expect(index.photos.allSatisfy { $0.path.hasPrefix("photos/") && $0.path.hasSuffix(".jpg") })
        let recordID = try #require(body.maintenanceRecords?.first).id
        #expect(index.maintenancePhotos.map(\.recordID) == [recordID])
        try file.verifyPhotos()

        let preview = ImportPreview(fileName: url.lastPathComponent, file: file)
        #expect(preview.photoCount == 3)
        #expect(preview.includesPhotos)
        #expect(preview.gearCount == 1)
        _ = container
    }

    @Test func aPackageRoundTripPutsEveryPhotoBackWhereItWas() async throws {
        let (source, body) = try makeLibrary()
        let url = try await exportPackage([body])
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try TestSupport.makeContainer()
        let context = destination.mainContext
        try await importFile(url, into: context, strategy: .replace)

        let restored = try #require(try context.fetch(FetchDescriptor<GearItem>()).first)
        #expect(restored.id == body.id)
        #expect(restored.make == "Nikon")
        #expect(restored.shutterCountReadings?.count == 2)
        let photos = (restored.photos ?? []).sorted { $0.order < $1.order }
        let originals = (body.photos ?? []).sorted { $0.order < $1.order }
        #expect(photos.map(\.id) == originals.map(\.id))
        #expect(photos.map(\.imageData) == [Self.jpeg(1), Self.jpeg(2), Self.jpeg(3)])
        #expect(photos.map(\.caption) == [nil, "Top plate", nil])
        #expect(photos.map(\.isPrimary) == [true, false, false])
        // Dates travel to the second, as they do in the records.
        for (photo, original) in zip(photos, originals) {
            #expect(abs(photo.dateAdded.timeIntervalSince(original.dateAdded)) < 1)
        }
        #expect(restored.primaryPhotoData == Self.jpeg(1))
        #expect(restored.maintenanceRecords?.first?.photoData == Self.jpeg(9))
        #expect(try context.fetchCount(FetchDescriptor<GearPhoto>()) == 3)
        _ = source
    }

    @Test func importingAPackageTwiceAddsNothing() async throws {
        let (source, body) = try makeLibrary()
        let url = try await exportPackage([body])
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try TestSupport.makeContainer()
        let context = destination.mainContext
        let service = importer()
        try await importFile(url, into: context, strategy: .merge, with: service)
        try await importFile(url, into: context, strategy: .merge, with: service)
        #expect(try context.fetchCount(FetchDescriptor<GearItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<GearPhoto>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<MaintenanceRecord>()) == 1)
        #expect(try context.fetch(FetchDescriptor<GearPhoto>()).filter(\.isPrimary).count == 1)
        _ = source
    }

    @Test func mergingAPackageFillsInThePhotosAnItemIsMissing() async throws {
        let (source, body) = try makeLibrary()
        let url = try await exportPackage([body])
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try TestSupport.makeContainer()
        let context = destination.mainContext
        try await importFile(url, into: context, strategy: .merge)
        // Lose the last photo and the maintenance photo, and change something the merge must keep.
        let item = try #require(try context.fetch(FetchDescriptor<GearItem>()).first)
        let last = try #require(item.photos?.first { $0.order == 2 })
        context.delete(last)
        item.maintenanceRecords?.first?.photoData = nil
        item.notes = "Edited here"
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<GearPhoto>()) == 2)

        try await importFile(url, into: context, strategy: .merge)
        let photos = try context.fetch(FetchDescriptor<GearPhoto>())
        #expect(photos.count == 3, "The missing photo is back, and the two it had aren't doubled")
        #expect(Set(photos.map(\.id)) == Set((body.photos ?? []).map(\.id)))
        #expect(photos.filter(\.isPrimary).count == 1)
        let merged = try #require(try context.fetch(FetchDescriptor<GearItem>()).first)
        #expect(merged.maintenanceRecords?.first?.photoData == Self.jpeg(9))
        #expect(merged.notes == "Edited here", "An item the library has is left as it is")
        _ = source
    }

    @Test func anItemThatKeptItsOwnCoverKeepsIt() async throws {
        let (source, body) = try makeLibrary()
        let url = try await exportPackage([body])
        defer { try? FileManager.default.removeItem(at: url) }

        // The same item, here with a photo of its own as the cover and none of the file's.
        let destination = try TestSupport.makeContainer()
        let context = destination.mainContext
        let recordsOnly = try await exportPackage([body], photos: false)
        defer { try? FileManager.default.removeItem(at: recordsOnly) }
        try await importFile(recordsOnly, into: context, strategy: .merge)
        let item = try #require(try context.fetch(FetchDescriptor<GearItem>()).first)
        let own = item.appendGalleryPhoto(Self.jpeg(7), in: context)
        try context.save()
        #expect(own.isPrimary)

        try await importFile(url, into: context, strategy: .merge)
        let photos = try context.fetch(FetchDescriptor<GearPhoto>())
        #expect(photos.count == 4)
        #expect(photos.filter(\.isPrimary).map(\.id) == [own.id])
        _ = source
    }

    // MARK: - When it stops part-way

    @Test func anImportThatStopsPartWayKeepsTheRecordsAndCanBeRunAgain() async throws {
        let (source, body) = try makeLibrary()
        let url = try await exportPackage([body])
        defer { try? FileManager.default.removeItem(at: url) }

        final class Saves {
            var count = 0
        }
        struct DiskFull: LocalizedError {
            var errorDescription: String? { "The disk is full." }
        }
        // The records save, the first lot of two photos saves, the second lot's save fails.
        let saves = Saves()
        let failing = DataImportService(settingsStore: TestSupport.makeDefaults(), photoBatch: 2) { context in
            saves.count += 1
            if saves.count == 3 { throw DiskFull() }
            try context.save()
        }
        let destination = try TestSupport.makeContainer()
        let context = destination.mainContext
        let error = await importError { try await importFile(url, into: context, strategy: .replace, with: failing) }
        guard case .photosIncomplete(let added, let total, let reason)? = error else {
            Issue.record("Expected the photos to be reported incomplete, got \(String(describing: error))")
            return
        }
        #expect(added == 2)
        #expect(total == 4, "Three gear photos and one on a maintenance record")
        #expect(reason.contains("disk is full"))
        #expect(error?.localizedDescription.contains("2 of 4 photos") == true)
        #expect(error?.localizedDescription.contains("Import the file again") == true)
        // The records are all in, with the photos that made it.
        #expect(try context.fetchCount(FetchDescriptor<GearItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ShutterCountReading>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<GearPhoto>()) == 2)

        // Again, with the disk behaving: the rest go in and nothing is doubled.
        try await importFile(url, into: context, strategy: .merge)
        #expect(try context.fetchCount(FetchDescriptor<GearItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<GearPhoto>()) == 3)
        let item = try #require(try context.fetch(FetchDescriptor<GearItem>()).first)
        #expect(item.maintenanceRecords?.first?.photoData == Self.jpeg(9))
        _ = source
    }

    // MARK: - Without photos, and too large

    @Test func aPackageMadeWithoutPhotosSaysSoAndRestoresTheRecords() async throws {
        let (source, body) = try makeLibrary()
        let url = try await exportPackage([body], photos: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try ImportDocument.open(url)
        #expect(!file.includesPhotos)
        #expect(file.photoCount == 0)
        #expect(file.package?.photoIndex == nil)

        let destination = try TestSupport.makeContainer()
        try await importer().apply(file, to: destination.mainContext, strategy: .replace)
        #expect(try destination.mainContext.fetchCount(FetchDescriptor<GearItem>()) == 1)
        #expect(try destination.mainContext.fetchCount(FetchDescriptor<GearPhoto>()) == 0)
        _ = source
    }

    @Test func aLibraryTooLargeForOneFileIsRefusedOrWrittenWithoutItsPhotos() async throws {
        let container = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: container.mainContext)
        body.appendGalleryPhoto(Self.jpeg(5, count: 200_000), in: container.mainContext)
        try container.mainContext.save()
        let library = LibraryContents(gearItems: [body], developmentRecipes: [])
        let service = exporter(maximumPackageBytes: 100_000)

        // An export says so, and names the fix.
        await #expect(throws: ExportError.self) {
            _ = try await service.exportLibrary(configuration: .init(format: .json), library: library)
        }
        #expect(!service.lastExportDroppedPhotos)

        // A backup would rather have the records than nothing.
        var keepGoing = DataExportService.ExportConfiguration(format: .json)
        keepGoing.dropsPhotosIfTooLarge = true
        let url = try await service.exportLibrary(configuration: keepGoing, library: library)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(service.lastExportDroppedPhotos)
        let file = try ImportDocument.open(url)
        #expect(!file.includesPhotos)
        #expect(file.document.gearItems.count == 1)
        #expect(try Data(contentsOf: url).count < 100_000)

        // Asked for without photos, nothing was dropped.
        var without = DataExportService.ExportConfiguration(format: .json)
        without.includePhotos = false
        let plain = try await service.exportLibrary(configuration: without, library: library)
        defer { try? FileManager.default.removeItem(at: plain) }
        #expect(!service.lastExportDroppedPhotos)

        let message = ExportError.photosTooLarge(limitMegabytes: 3_072, includesPhotos: true).localizedDescription
        #expect(message.contains("3 GB") && message.contains("Photos"))
        #expect(ExportError.sizeText(megabytes: 512) == "512 MB")
    }

    @Test func photosThatAreNotInAStoreYetAreReadFromTheObjects() async throws {
        // An item that was never inserted: there's no store to read its photo through.
        let item = GearItem(category: .lens, make: "Sigma", model: "35mm f/1.4")
        let photo = GearPhoto(imageData: Self.jpeg(4), isPrimary: true)
        item.photos = [photo]
        let url = try await exportPackage([item])
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try ImportDocument.open(url)
        let listed = try #require(file.package?.photoIndex?.photos.first)
        #expect(listed.id == photo.id)
        #expect(listed.gearItemID == item.id)
        #expect(try file.package?.data(for: listed) == Self.jpeg(4))
    }

    // MARK: - Other files through the same door

    @Test func aJSONFileWithPhotosInsideStillImports() async throws {
        let (source, body) = try makeLibrary()
        let url = try await exporter().exportData(configuration: .init(format: .json),
                                                  library: LibraryContents(gearItems: [body], developmentRecipes: []))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.pathExtension == "json")
        #expect(!LibraryPackage.looksLikePackage(url))
        let file = try ImportDocument.open(url)
        #expect(file.package == nil)
        #expect(file.photoCount == 3)
        #expect(file.includesPhotos)

        let destination = try TestSupport.makeContainer()
        try await importFile(url, into: destination.mainContext, strategy: .replace)
        let restored = try #require(try destination.mainContext.fetch(FetchDescriptor<GearItem>()).first)
        #expect(restored.photos?.count == 3)
        #expect(restored.maintenanceRecords?.first?.photoData == Self.jpeg(9))
        _ = source
    }

    @Test func aZipThatIsNotALibraryIsRefusedInWords() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-library-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }

        // Somebody's holiday photos.
        let writer = try ZipWriter(url: url)
        try writer.add("holiday.jpg", Self.jpeg(1))
        try writer.finish()
        guard case .unsupportedFormat? = await importError({ _ = try ImportDocument.open(url) }) else {
            Issue.record("A zip with no library in it should be refused as not the app's")
            return
        }

        // A library file unpacked and zipped again with compression, as a computer's "compress" does.
        let compressed = try #require(Data(base64Encoded: "UEsDBBQAAAAIAMBLa103yO99EQAAAPAAAAAJAAAAaGVsbG8udHh080jNycnXUajKLNBT8BgBbABQSwECFAMUAAAACADAS2tdN8jvfREAAADwAAAACQAAAAAAAAAAAAAAgAEAAAAAaGVsbG8udHh0UEsFBgAAAAABAAEANwAAADgAAAAAAA=="))
        try compressed.write(to: url)
        let rewritten = await importError { _ = try ImportDocument.open(url) }
        guard case .rewrittenArchive? = rewritten else {
            Issue.record("A compressed zip should be refused as changed by another app, got \(String(describing: rewritten))")
            return
        }
        #expect(rewritten?.localizedDescription.contains("zipped again") == true)
        #expect(ImportError.fileTooLarge.localizedDescription.contains("3 GB"))
        #expect(ImportError.fileTooLarge.localizedDescription.contains("256 MB"))
    }

    // MARK: - Backups

    @Test func aBackupIsAPackageAndAnOlderJSONBackupStillRestores() async throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (source, body) = try makeLibrary()
        let library = LibraryContents(gearItems: [body], developmentRecipes: [])

        let manager = BackupManager(directory: directory, defaults: TestSupport.makeDefaults())
        try await manager.createBackup(library: library)
        let backup = try #require(manager.availableBackups.first)
        #expect(backup.fileURL.pathExtension == "zip")
        #expect(backup.includesPhotos == true)
        #expect(LibraryPackage.looksLikePackage(backup.fileURL))
        #expect(!manager.formattedTotalSize.isEmpty)

        let restored = try TestSupport.makeContainer()
        try await manager.restoreBackup(backup, to: restored.mainContext)
        #expect(try restored.mainContext.fetchCount(FetchDescriptor<GearPhoto>()) == 3)
        #expect(try restored.mainContext.fetch(FetchDescriptor<MaintenanceRecord>()).first?.photoData == Self.jpeg(9))

        // A backup as earlier versions wrote it: one JSON file with the photos inside.
        let json = try await exporter().exportData(configuration: .init(format: .json), library: library)
        let legacy = directory.appendingPathComponent("backup_20260101_000000_legacy.json")
        try FileManager.default.moveItem(at: json, to: legacy)
        let reopened = BackupManager(directory: directory, defaults: TestSupport.makeDefaults())
        #expect(reopened.availableBackups.count == 2)
        let old = try #require(reopened.availableBackups.first { $0.fileURL.pathExtension == "json" })
        #expect(old.isRecovered, "Found on disk and listed, its contents unknown until it's opened")

        let fromOld = try TestSupport.makeContainer()
        try await reopened.restoreBackup(old, to: fromOld.mainContext)
        #expect(try fromOld.mainContext.fetchCount(FetchDescriptor<GearItem>()) == 1)
        #expect(try fromOld.mainContext.fetchCount(FetchDescriptor<GearPhoto>()) == 3)
        _ = source
    }
}
