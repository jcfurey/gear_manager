//
//  LibraryPackageTests.swift
//  ShutterManagerTests
//
//  The zip file a library travels in: written so any tool can open it, read back whole, and
//  refused plainly when it's damaged or isn't one of the app's. Foundation-only, so it also
//  runs on Linux.
//

import Foundation
import Testing
@testable import ShutterManager

/// A scratch file that goes when the test does.
private final class ScratchFile {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("package-tests-\(UUID().uuidString).zip")

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ data: Data) throws -> URL {
        try data.write(to: url)
        return url
    }

    func zip(date: Date = Date(timeIntervalSince1970: 1_800_000_000), maximumBytes: UInt64 = ZipFormat.maximumBytes,
             _ entries: [(String, Data)]) throws -> URL {
        let writer = try ZipWriter(url: url, date: date, maximumBytes: maximumBytes)
        for (name, data) in entries { try writer.add(name, data) }
        try writer.finish()
        return url
    }
}

struct ZipArchiveTests {
    /// Made with Python's `zipfile`, stored: `hello.txt` and `dir/data.bin`.
    private static let standardZip = Data(base64Encoded: "UEsDBBQAAAAAAMBLa10Zh6BRDAAAAAwAAAAJAAAAaGVsbG8udHh0SGVsbG8sIHppcC4KUEsDBBQAAAAAAMBLa12KfiaRIAAAACAAAAAMAAAAZGlyL2RhdGEuYmluAAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh9QSwECFAMUAAAAAADAS2tdGYegUQwAAAAMAAAACQAAAAAAAAAAAAAAgAEAAAAAaGVsbG8udHh0UEsBAhQDFAAAAAAAwEtrXYp+JpEgAAAAIAAAAAwAAAAAAAAAAAAAAIABMwAAAGRpci9kYXRhLmJpblBLBQYAAAAAAgACAHEAAAB9AAAAAAA=")!
    /// Made with Python's `zipfile`, compressed (deflate): `hello.txt`.
    private static let compressedZip = Data(base64Encoded: "UEsDBBQAAAAIAMBLa103yO99EQAAAPAAAAAJAAAAaGVsbG8udHh080jNycnXUajKLNBT8BgBbABQSwECFAMUAAAACADAS2tdN8jvfREAAADwAAAACQAAAAAAAAAAAAAAgAEAAAAAaGVsbG8udHh0UEsFBgAAAAABAAEANwAAADgAAAAAAA==")!
    /// What `ZipWriter` wrote for one entry, `a.txt` holding "hi", stamped 2027-01-15 08:00 UTC.
    /// Python's `zipfile` and `unzip -t` both accept these bytes.
    private static let pinnedZip = "UEsDBBQAAAgAAABAL156em/tAwAAAAMAAAAFAAAAYS50eHRoaQpQSwECFAAUAAAIAAAAQC9eenpv7QMAAAADAAAABQAAAAAAAAAAAAAAAAAAAAAAYS50eHRQSwUGAAAAAAEAAQAzAAAAJgAAAAAA"

    // MARK: - Checksums

    @Test func checksumsMatchThePublishedValues() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926, "The standard check value")
        #expect(CRC32.checksum(Data("The quick brown fox jumps over the lazy dog".utf8)) == 0x414F_A339)
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test func aChecksumCanBeWorkedOutInPieces() {
        let whole = Data((0..<10_000).map { UInt8($0 % 253) })
        var running: UInt32 = 0
        for start in stride(from: 0, to: whole.count, by: 777) {
            running = CRC32.checksum(whole.subdata(in: start..<min(start + 777, whole.count)), continuing: running)
        }
        #expect(running == CRC32.checksum(whole))
    }

    // MARK: - Writing and reading back

    @Test func whatIsWrittenReadsBack() throws {
        let scratch = ScratchFile()
        let photo = Data((0..<70_000).map { UInt8($0 % 251) })
        let url = try scratch.zip([("library.json", Data("{}".utf8)), ("photos/A.jpg", photo),
                                   ("photos/empty.bin", Data()), ("notes/ünïcode.txt", Data("héllo".utf8))])
        let reader = try ZipReader(url: url)
        #expect(reader.entries.map(\.name) == ["library.json", "photos/A.jpg", "photos/empty.bin", "notes/ünïcode.txt"])
        #expect(reader.entries.map(\.size) == [2, 70_000, 0, 6])
        let entry = try #require(reader.entry(named: "photos/A.jpg"))
        #expect(try reader.data(for: entry) == photo)
        #expect(entry.crc == CRC32.checksum(photo))
        for each in reader.entries { try reader.verify(each) }
        #expect(reader.entry(named: "photos/missing.jpg") == nil)
        #expect(reader.fileSize == UInt64(try Data(contentsOf: url).count))
    }

    @Test func theBytesWrittenAreTheOnesStandardToolsAccept() throws {
        let scratch = ScratchFile()
        let url = try scratch.zip([("a.txt", Data("hi\n".utf8))])
        #expect(try Data(contentsOf: url).base64EncodedString() == Self.pinnedZip,
                "Change the writer and this must be checked again with a standard zip tool")
    }

    @Test func aFileWithNoEntriesIsStillAZip() throws {
        let scratch = ScratchFile()
        let url = try scratch.zip([])
        #expect(try Data(contentsOf: url).count == ZipFormat.endLength)
        #expect(try ZipReader(url: url).entries.isEmpty)
    }

    @Test func aZipFromAStandardToolReads() throws {
        let scratch = ScratchFile()
        let reader = try ZipReader(url: try scratch.write(Self.standardZip))
        #expect(reader.entries.map(\.name) == ["hello.txt", "dir/data.bin"])
        #expect(try reader.data(for: try #require(reader.entry(named: "hello.txt"))) == Data("Hello, zip.\n".utf8))
        #expect(try reader.data(for: try #require(reader.entry(named: "dir/data.bin"))) == Data(0..<32))
    }

    @Test func entriesAreStampedInUTC() {
        // 2027-01-15 08:00:00 UTC.
        let stamp = ZipWriter.dosStamp(Date(timeIntervalSince1970: 1_800_000_000))
        #expect(stamp.date == UInt16(47) << 9 | 1 << 5 | 15)
        #expect(stamp.time == UInt16(8) << 11)
        // Before the format's first year reads as its first year, not as a year far ahead.
        #expect(ZipWriter.dosStamp(Date(timeIntervalSince1970: 0)).date >> 9 == 0)
    }

    // MARK: - Refusing

    @Test func aCompressedZipIsRefusedAsUnsupported() throws {
        let scratch = ScratchFile()
        let url = try scratch.write(Self.compressedZip)
        #expect(throws: ZipError.unsupported) { _ = try ZipReader(url: url) }
    }

    @Test func whatWasNeverAZipIsRefused() throws {
        let scratch = ScratchFile()
        #expect(throws: ZipError.notAZipFile) { _ = try ZipReader(url: try scratch.write(Data("{\"formatVersion\": 1}".utf8))) }
        #expect(throws: ZipError.notAZipFile) { _ = try ZipReader(url: try scratch.write(Data())) }
        #expect(throws: ZipError.notAZipFile) { _ = try ZipReader(url: try scratch.write(Data(repeating: 0, count: 5_000))) }
    }

    @Test func aZipCutShortIsDamaged() throws {
        let scratch = ScratchFile()
        let whole = try Data(contentsOf: try scratch.zip([("library.json", Data(repeating: 65, count: 500))]))
        for missing in [1, 10, 22, 100, 400] {
            let url = try scratch.write(whole.prefix(whole.count - missing))
            #expect(throws: ZipError.damaged, "\(missing) bytes short") { _ = try ZipReader(url: url) }
        }
    }

    @Test func changedBytesFailTheirChecksum() throws {
        let scratch = ScratchFile()
        var bytes = try Data(contentsOf: try scratch.zip([("photos/A.jpg", Data(repeating: 9, count: 3_000_000))]))
        // Well inside the entry, and past the first piece a check reads.
        bytes[2_500_000] ^= 0xFF
        let reader = try ZipReader(url: try scratch.write(bytes))
        let entry = try #require(reader.entry(named: "photos/A.jpg"))
        #expect(throws: ZipError.checksumMismatch(name: "photos/A.jpg")) { _ = try reader.data(for: entry) }
        #expect(throws: ZipError.checksumMismatch(name: "photos/A.jpg")) { try reader.verify(entry) }
    }

    @Test func aDirectoryThatPointsPastTheFileIsDamaged() throws {
        let scratch = ScratchFile()
        var bytes = try Data(contentsOf: try scratch.zip([("a.txt", Data("hi\n".utf8))]))
        // The closing record's offset of the directory: the last 6 bytes but the comment length.
        bytes[bytes.count - 6] = 0xF0
        #expect(throws: ZipError.damaged) { _ = try ZipReader(url: try scratch.write(bytes)) }
    }

    @Test func theWriterStopsAtItsLimit() throws {
        let scratch = ScratchFile()
        let writer = try ZipWriter(url: scratch.url, maximumBytes: 1_000)
        try writer.add("small.bin", Data(repeating: 1, count: 300))
        let before = writer.finishedSize
        #expect(throws: ZipError.tooLarge) { try writer.add("large.bin", Data(repeating: 2, count: 700)) }
        #expect(writer.finishedSize == before, "Nothing of the refused entry was written")
        #expect(writer.entryCount == 1)
        // The name is free again, and something that fits still goes in.
        try writer.add("large.bin", Data(repeating: 2, count: 100))
        try writer.finish()
        let reader = try ZipReader(url: scratch.url)
        #expect(reader.entries.map(\.name) == ["small.bin", "large.bin"])
        #expect(reader.fileSize <= 1_000)
        #expect(reader.fileSize == writer.finishedSize, "The size it promised is the size it wrote")
    }

    @Test func aNameCanBeUsedOnce() throws {
        let scratch = ScratchFile()
        let writer = try ZipWriter(url: scratch.url)
        try writer.add("a.txt", Data())
        #expect(throws: ZipError.invalidName("a.txt")) { try writer.add("a.txt", Data([1])) }
        #expect(throws: ZipError.invalidName("")) { try writer.add("", Data([1])) }
        try writer.finish()
        #expect(try ZipReader(url: scratch.url).entries.count == 1)
    }
}

struct LibraryPackageTests {
    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 3, count: 5_000)
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 4, count: 2_000)
    private static let manifest = Data("{\"formatVersion\": 1}".utf8)
    private static let made = Date(timeIntervalSince1970: 1_800_000_000)

    private static func open(_ url: URL, maximumBytes: Int = 1_000_000, maximumManifestBytes: Int = 100_000,
                             maximumPhotos: Int = 100) throws -> LibraryPackageFile {
        try LibraryPackageFile(url: url, maximumBytes: maximumBytes, maximumManifestBytes: maximumManifestBytes,
                               maximumPhotos: maximumPhotos)
    }

    private static func photo(_ id: UUID, of item: UUID, _ data: Data, order: Int = 0) -> LibraryPackageWriter.Photo {
        LibraryPackageWriter.Photo(id: id, gearItemID: item, caption: order == 0 ? "Front" : nil, order: order,
                                   dateAdded: made, isPrimary: order == 0, data: data)
    }

    // MARK: - A whole package

    @Test func aPackageHoldsItsRecordsAndEachPhoto() async throws {
        let scratch = ScratchFile()
        let item = UUID(), first = UUID(), second = UUID(), record = UUID()
        let writer = try LibraryPackageWriter(url: scratch.url, date: Self.made, maximumBytes: 1_000_000)
        try await writer.add([Self.photo(first, of: item, Self.jpeg), Self.photo(second, of: item, Self.png, order: 1)])
        try await writer.add([LibraryPackageWriter.MaintenancePhoto(recordID: record, data: Self.jpeg)])
        let written = try await writer.finish(manifest: Self.manifest, includesPhotos: true, appName: "Shutter Manager")
        #expect(written.count == 3)

        let package = try Self.open(scratch.url)
        #expect(package.manifest == Self.manifest)
        let index = try #require(package.photoIndex)
        #expect(index == written)
        #expect(index.version == PackagePhotoIndex.currentVersion)
        #expect(index.photos.map(\.id) == [first, second])
        #expect(index.photos.map(\.path) == ["photos/\(first.uuidString).jpg", "photos/\(second.uuidString).png"])
        #expect(index.photos.map(\.bytes) == [Self.jpeg.count, Self.png.count])
        #expect(index.photos[0].gearItemID == item)
        #expect(index.photos[0].caption == "Front")
        #expect(index.photos[0].isPrimary && !index.photos[1].isPrimary)
        #expect(index.photos[1].order == 1)
        #expect(index.photos[0].dateAdded == Self.made)
        #expect(index.maintenancePhotos.map(\.path) == ["maintenance/\(record.uuidString).jpg"])
        #expect(try package.data(for: index.photos[0]) == Self.jpeg)
        #expect(try package.data(for: index.photos[1]) == Self.png)
        #expect(try package.data(for: index.maintenancePhotos[0]) == Self.jpeg)
        try package.verifyPhotos()
        #expect(package.fileSize == (try Data(contentsOf: scratch.url)).count)

        // Whoever opens it without the app finds the pieces named, and a note saying what they are.
        let zip = try ZipReader(url: scratch.url)
        #expect(Set(zip.entries.map(\.name)) == ["library.json", "photos.json", "README.txt",
                                                  "photos/\(first.uuidString).jpg", "photos/\(second.uuidString).png",
                                                  "maintenance/\(record.uuidString).jpg"])
        let note = String(decoding: try zip.data(for: try #require(zip.entry(named: "README.txt"))), as: UTF8.self)
        #expect(note.contains("Shutter Manager library") && note.contains("library.json") && note.contains("Import Data"))
    }

    @Test func aPackageMadeWithoutPhotosSaysSoByHavingNoList() async throws {
        let scratch = ScratchFile()
        let without = try LibraryPackageWriter(url: scratch.url, date: Self.made, maximumBytes: 1_000_000)
        try await without.finish(manifest: Self.manifest, includesPhotos: false, appName: "Shutter Manager")
        #expect(try Self.open(scratch.url).photoIndex == nil)

        // With photos asked for, a library that has none still says they were included.
        let with = try LibraryPackageWriter(url: scratch.url, date: Self.made, maximumBytes: 1_000_000)
        try await with.finish(manifest: Self.manifest, includesPhotos: true, appName: "Shutter Manager")
        let index = try #require(try Self.open(scratch.url).photoIndex)
        #expect(index.count == 0)
    }

    @Test func aPhotoListedTwiceIsWrittenOnce() async throws {
        // A library with doubled records lists the same photo under both copies of its item.
        let scratch = ScratchFile()
        let item = UUID(), id = UUID(), record = UUID()
        let writer = try LibraryPackageWriter(url: scratch.url, date: Self.made, maximumBytes: 1_000_000)
        try await writer.add([Self.photo(id, of: item, Self.jpeg), Self.photo(id, of: item, Self.jpeg)])
        try await writer.add([Self.photo(id, of: item, Self.jpeg)])
        try await writer.add([LibraryPackageWriter.MaintenancePhoto(recordID: record, data: Self.png),
                              LibraryPackageWriter.MaintenancePhoto(recordID: record, data: Self.png)])
        let index = try await writer.finish(manifest: Self.manifest, includesPhotos: true, appName: "Shutter Manager")
        #expect(index.photos.count == 1)
        #expect(index.maintenancePhotos.count == 1)
        try Self.open(scratch.url).verifyPhotos()
    }

    @Test func aPackagePastItsLimitIsRefusedAndRemoved() async throws {
        let scratch = ScratchFile()
        let writer = try LibraryPackageWriter(url: scratch.url, date: Self.made, maximumBytes: 6_000)
        try await writer.add([Self.photo(UUID(), of: UUID(), Self.jpeg)])
        await #expect(throws: ZipError.tooLarge) {
            try await writer.add([Self.photo(UUID(), of: UUID(), Self.jpeg)])
        }
        await writer.cancel()
        #expect(!FileManager.default.fileExists(atPath: scratch.url.path), "A file given up on isn't left behind")
    }

    // MARK: - Opening what isn't right

    @Test func aZipThatIsNotALibraryIsRefused() throws {
        let scratch = ScratchFile()
        #expect(throws: LibraryPackageError.notALibrary) { _ = try Self.open(try scratch.zip([("holiday.jpg", Self.jpeg)])) }
        #expect(throws: LibraryPackageError.notALibrary) { _ = try Self.open(try scratch.write(Data("not a zip".utf8))) }
    }

    @Test func aZipAnotherAppRewroteIsRefusedAsSuch() throws {
        // Unpacked and zipped again with compression, as a computer's own "compress" does.
        let scratch = ScratchFile()
        let compressed = Data(base64Encoded: "UEsDBBQAAAAIAMBLa103yO99EQAAAPAAAAAJAAAAaGVsbG8udHh080jNycnXUajKLNBT8BgBbABQSwECFAMUAAAACADAS2tdN8jvfREAAADwAAAACQAAAAAAAAAAAAAAgAEAAAAAaGVsbG8udHh0UEsFBgAAAAABAAEANwAAADgAAAAAAA==")!
        #expect(throws: LibraryPackageError.rewritten) { _ = try Self.open(try scratch.write(compressed)) }
    }

    @Test func aPackageMissingAPhotoItListsIsDamaged() throws {
        let scratch = ScratchFile()
        let id = UUID()
        func index(bytes: Int) throws -> Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(PackagePhotoIndex(photos: [
                PackagePhoto(id: id, gearItemID: UUID(), caption: nil, order: 0, dateAdded: Self.made, isPrimary: true,
                             path: "photos/\(id.uuidString).jpg", bytes: bytes)
            ]))
        }
        // Listed, but not there.
        var url = try scratch.zip([("library.json", Self.manifest), ("photos.json", try index(bytes: Self.jpeg.count))])
        #expect(throws: LibraryPackageError.damaged) { _ = try Self.open(url) }
        // There, but not the length the list says.
        url = try scratch.zip([("library.json", Self.manifest), ("photos.json", try index(bytes: 12)),
                               ("photos/\(id.uuidString).jpg", Self.jpeg)])
        #expect(throws: LibraryPackageError.damaged) { _ = try Self.open(url) }
        // And right.
        url = try scratch.zip([("library.json", Self.manifest), ("photos.json", try index(bytes: Self.jpeg.count)),
                               ("photos/\(id.uuidString).jpg", Self.jpeg)])
        #expect(try Self.open(url).photoIndex?.photos.count == 1)
    }

    @Test func aListThatIsNotAListIsDamagedAndANewerOneSaysSo() throws {
        let scratch = ScratchFile()
        var url = try scratch.zip([("library.json", Self.manifest), ("photos.json", Data("[1, 2".utf8))])
        #expect(throws: LibraryPackageError.damaged) { _ = try Self.open(url) }
        url = try scratch.zip([("library.json", Self.manifest),
                               ("photos.json", Data("{\"version\": 2, \"somethingNew\": true}".utf8))])
        #expect(throws: LibraryPackageError.newerVersion) { _ = try Self.open(url) }
        // This version's list with keys it doesn't know still reads.
        url = try scratch.zip([("library.json", Self.manifest),
                               ("photos.json", Data("{\"version\": 1, \"photos\": [], \"maintenancePhotos\": [], \"later\": 5}".utf8))])
        #expect(try Self.open(url).photoIndex?.count == 0)
    }

    @Test func limitsAreKeptOnOpening() async throws {
        let scratch = ScratchFile()
        let writer = try LibraryPackageWriter(url: scratch.url, date: Self.made, maximumBytes: 1_000_000)
        try await writer.add([Self.photo(UUID(), of: UUID(), Self.jpeg), Self.photo(UUID(), of: UUID(), Self.png)])
        try await writer.finish(manifest: Self.manifest, includesPhotos: true, appName: "Shutter Manager")
        let size = try Data(contentsOf: scratch.url).count

        #expect(throws: LibraryPackageError.tooLarge) { _ = try Self.open(scratch.url, maximumBytes: size - 1) }
        #expect(throws: LibraryPackageError.tooLarge) { _ = try Self.open(scratch.url, maximumManifestBytes: Self.manifest.count - 1) }
        #expect(throws: LibraryPackageError.tooLarge) { _ = try Self.open(scratch.url, maximumPhotos: 1) }
        #expect(try Self.open(scratch.url, maximumBytes: size, maximumPhotos: 2).photoIndex?.count == 2)
    }

    @Test func aPhotoChangedInTransitIsCaught() async throws {
        let scratch = ScratchFile()
        let writer = try LibraryPackageWriter(url: scratch.url, date: Self.made, maximumBytes: 1_000_000)
        try await writer.add([Self.photo(UUID(), of: UUID(), Self.jpeg)])
        try await writer.finish(manifest: Self.manifest, includesPhotos: true, appName: "Shutter Manager")
        var bytes = try Data(contentsOf: scratch.url)
        // The photo is the first entry: a byte well inside it.
        bytes[2_000] ^= 0xFF
        let package = try Self.open(try scratch.write(bytes))
        let photo = try #require(package.photoIndex?.photos.first)
        #expect(throws: LibraryPackageError.damaged) { _ = try package.data(for: photo) }
        #expect(throws: LibraryPackageError.damaged) { try package.verifyPhotos() }
    }

    // MARK: - Names and telling files apart

    @Test func photosAreNamedForWhatTheyAre() {
        let id = UUID()
        #expect(LibraryPackage.photoPath(id, data: Self.jpeg) == "photos/\(id.uuidString).jpg")
        #expect(LibraryPackage.maintenancePhotoPath(id, data: Self.png) == "maintenance/\(id.uuidString).png")
        #expect(LibraryPackage.fileExtension(for: Data([0, 0, 0, 0x18]) + Data("ftypheic".utf8)) == "heic")
        #expect(LibraryPackage.fileExtension(for: Data("GIF89a".utf8)) == "gif")
        #expect(LibraryPackage.fileExtension(for: Data([0x49, 0x49, 0x2A, 0x00, 8])) == "tiff")
        #expect(LibraryPackage.fileExtension(for: Data([0x4D, 0x4D, 0x00, 0x2A, 0])) == "tiff")
        #expect(LibraryPackage.fileExtension(for: Data([1, 2, 3])) == "bin")
        #expect(LibraryPackage.fileExtension(for: Data()) == "bin")
    }

    @Test func aChosenFileIsToldApartByHowItStarts() throws {
        let scratch = ScratchFile()
        #expect(LibraryPackage.looksLikePackage(try scratch.zip([("library.json", Self.manifest)])))
        #expect(LibraryPackage.looksLikePackage(try scratch.zip([])), "A zip with nothing in it is still a zip")
        #expect(!LibraryPackage.looksLikePackage(try scratch.write(Data("{\"formatVersion\": 1}".utf8))))
        #expect(!LibraryPackage.looksLikePackage(try scratch.write(Data("PK".utf8))))
        #expect(!LibraryPackage.looksLikePackage(try scratch.write(Data())))
        #expect(!LibraryPackage.looksLikePackage(scratch.url.appendingPathExtension("missing")))
    }
}
