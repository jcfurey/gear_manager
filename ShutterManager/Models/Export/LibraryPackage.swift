//
//  LibraryPackage.swift
//  ShutterManager
//
//  The file a whole library travels in: a zip holding the records as JSON and each photo as a
//  file of its own. Photos are written and read one at a time, so a library's size isn't bounded
//  by what fits in memory, and the file opens on any computer. Foundation-only.
//
//  Inside:
//    library.json      every record, as a `LibraryExport` with no photos in it
//    photos.json       which item or record each photo belongs to (absent: made without photos)
//    photos/<id>.jpg   gear photos, named by their IDs
//    maintenance/<id>.jpg   maintenance records' photos, named by the records' IDs
//    README.txt        what the file is, for whoever opens it
//

import Foundation

/// A gear photo in a package: everything about it but its bytes, which are the entry at `path`.
struct PackagePhoto: Codable, Equatable, Sendable {
    let id: UUID
    let gearItemID: UUID
    let caption: String?
    let order: Int
    let dateAdded: Date
    let isPrimary: Bool
    let path: String
    let bytes: Int
}

/// A maintenance record's photo in a package.
struct PackageMaintenancePhoto: Codable, Equatable, Sendable {
    let recordID: UUID
    let path: String
    let bytes: Int
}

/// `photos.json`: the photos a package carries, and whose they are.
struct PackagePhotoIndex: Codable, Equatable, Sendable {
    /// Rises only for a change an older reader can't handle by ignoring keys.
    static let currentVersion = 1

    var version = PackagePhotoIndex.currentVersion
    var photos: [PackagePhoto] = []
    var maintenancePhotos: [PackageMaintenancePhoto] = []

    var count: Int { photos.count + maintenancePhotos.count }
}

enum LibraryPackageError: Error, Equatable {
    /// A zip file, but not one of the app's: it has no `library.json`.
    case notALibrary
    /// A zip file another app has rewritten: compressed, encrypted or in the 64-bit form.
    case rewritten
    /// Cut short, or its contents don't match what it says it holds.
    case damaged
    /// Written by a newer version, in a form this one can't read.
    case newerVersion
    /// Larger than the limit it was opened with.
    case tooLarge
}

enum LibraryPackage {
    static let fileExtension = "zip"
    static let manifestName = "library.json"
    static let photoIndexName = "photos.json"
    static let readMeName = "README.txt"

    /// The entry a gear photo goes in. The extension follows what the bytes are, so the photos
    /// open as photos for whoever unpacks the file.
    static func photoPath(_ id: UUID, data: Data) -> String {
        "photos/\(id.uuidString).\(fileExtension(for: data))"
    }

    static func maintenancePhotoPath(_ recordID: UUID, data: Data) -> String {
        "maintenance/\(recordID.uuidString).\(fileExtension(for: data))"
    }

    /// The image type `data` starts like, as a file extension; "bin" for anything else.
    static func fileExtension(for data: Data) -> String {
        let start = [UInt8](data.prefix(12))
        func begins(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            start.count >= offset + bytes.count && Array(start[offset..<(offset + bytes.count)]) == bytes
        }
        if begins([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if begins([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if begins(Array("ftyp".utf8), at: 4) { return "heic" }
        if begins(Array("GIF8".utf8)) { return "gif" }
        if begins([0x49, 0x49, 0x2A, 0x00]) || begins([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        return "bin"
    }

    /// Whether the file at `url` starts the way a zip does. A cheap look before deciding how to
    /// read a file someone has chosen: anything else is taken for JSON.
    static func looksLikePackage(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let start = try? handle.read(upToCount: 4), start.count == 4 else { return false }
        let bytes = [UInt8](start)
        // "PK", then the mark of a first entry or (in a zip with none) of the closing record.
        return bytes[0] == 0x50 && bytes[1] == 0x4B
            && ((bytes[2] == 0x03 && bytes[3] == 0x04) || (bytes[2] == 0x05 && bytes[3] == 0x06))
    }

    /// What the file says about itself to someone who opens it without the app.
    static func readMe(appName: String, date: Date) -> String {
        let made = ISO8601DateFormatter().string(from: date)
        return """
            \(appName) library

            This file is a copy of a \(appName) library, made \(made).

            library.json   Every record: gear, maintenance, shoots and the rest.
            photos.json    Which item or record each photo belongs to.
            photos/        Gear photos, named by their IDs.
            maintenance/   Maintenance photos, named by their records' IDs.

            To bring it back, choose this file in \(appName): Settings, Import Data.
            Keep the file as it is. One that has been unpacked and zipped again by another
            app may not import.

            """
    }
}

// MARK: - Writing

/// Writes a package: photos as they're handed over, then the index, the records and the note.
/// An actor, so the screen that feeds it never waits on the disk.
actor LibraryPackageWriter {
    private let zip: ZipWriter
    private let url: URL
    private let date: Date
    private var index = PackagePhotoIndex()
    private var photoIDs = Set<UUID>()
    private var recordIDs = Set<UUID>()

    /// Starts the file at `url`. `maximumBytes` is the largest the finished file may be.
    init(url: URL, date: Date = Date(), maximumBytes: Int) throws {
        self.url = url
        self.date = date
        zip = try ZipWriter(url: url, date: date, maximumBytes: UInt64(max(maximumBytes, 0)))
    }

    /// A gear photo to add: what the index says of it, and its bytes.
    struct Photo: Sendable {
        let id: UUID
        let gearItemID: UUID
        let caption: String?
        let order: Int
        let dateAdded: Date
        let isPrimary: Bool
        let data: Data
    }

    struct MaintenancePhoto: Sendable {
        let recordID: UUID
        let data: Data
    }

    /// Adds gear photos. One whose ID is already in the file is skipped: a library with doubled
    /// records lists it twice, and it's one photo.
    func add(_ photos: [Photo]) throws {
        for photo in photos where photoIDs.insert(photo.id).inserted {
            let path = LibraryPackage.photoPath(photo.id, data: photo.data)
            try zip.add(path, photo.data)
            index.photos.append(PackagePhoto(id: photo.id, gearItemID: photo.gearItemID, caption: photo.caption,
                                             order: photo.order, dateAdded: photo.dateAdded, isPrimary: photo.isPrimary,
                                             path: path, bytes: photo.data.count))
        }
    }

    func add(_ photos: [MaintenancePhoto]) throws {
        for photo in photos where recordIDs.insert(photo.recordID).inserted {
            let path = LibraryPackage.maintenancePhotoPath(photo.recordID, data: photo.data)
            try zip.add(path, photo.data)
            index.maintenancePhotos.append(PackageMaintenancePhoto(recordID: photo.recordID, path: path, bytes: photo.data.count))
        }
    }

    /// Writes the index (when the package is one with photos, even if the library has none),
    /// the records and the note, and closes the file. Returns the photos written.
    @discardableResult
    func finish(manifest: Data, includesPhotos: Bool, appName: String) throws -> PackagePhotoIndex {
        if includesPhotos {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try zip.add(LibraryPackage.photoIndexName, try encoder.encode(index))
        }
        try zip.add(LibraryPackage.manifestName, manifest)
        try zip.add(LibraryPackage.readMeName, Data(LibraryPackage.readMe(appName: appName, date: date).utf8))
        try zip.finish()
        return index
    }

    /// Gives up: closes the file and removes what was written.
    func cancel() {
        try? zip.close()
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Reading

/// A package opened for reading: its records and its list of photos are read at once, each
/// photo's bytes when asked for.
final class LibraryPackageFile: Sendable {
    /// `library.json`, as written.
    let manifest: Data
    /// The photos the package carries; nil for one made without photos.
    let photoIndex: PackagePhotoIndex?
    let fileSize: Int

    private let zip: ZipReader
    private let entries: [String: ZipReader.Entry]

    /// Opens the package at `url` and checks that it holds what it lists.
    /// - Parameters:
    ///   - maximumBytes: the largest file to open.
    ///   - maximumManifestBytes: the largest `library.json` to read.
    ///   - maximumPhotos: the most photos its index may list.
    init(url: URL, maximumBytes: Int, maximumManifestBytes: Int, maximumPhotos: Int) throws {
        do {
            zip = try ZipReader(url: url)
        } catch let error as ZipError {
            throw Self.packageError(for: error)
        }
        guard zip.fileSize <= UInt64(max(maximumBytes, 0)) else { throw LibraryPackageError.tooLarge }
        fileSize = Int(zip.fileSize)
        do {
            guard let manifestEntry = zip.entry(named: LibraryPackage.manifestName) else {
                throw LibraryPackageError.notALibrary
            }
            guard manifestEntry.size <= maximumManifestBytes else { throw LibraryPackageError.tooLarge }
            manifest = try zip.data(for: manifestEntry)

            var found: [String: ZipReader.Entry] = [:]
            if let indexEntry = zip.entry(named: LibraryPackage.photoIndexName) {
                guard indexEntry.size <= maximumManifestBytes else { throw LibraryPackageError.tooLarge }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let indexData = try zip.data(for: indexEntry)
                guard let version = try? decoder.decode(Version.self, from: indexData) else {
                    throw LibraryPackageError.damaged
                }
                guard version.version <= PackagePhotoIndex.currentVersion else { throw LibraryPackageError.newerVersion }
                guard var index = try? decoder.decode(PackagePhotoIndex.self, from: indexData) else {
                    throw LibraryPackageError.damaged
                }
                guard index.count <= maximumPhotos else { throw LibraryPackageError.tooLarge }
                // Listed twice is one photo; the first listing stands.
                var photoIDs = Set<UUID>()
                index.photos = index.photos.filter { photoIDs.insert($0.id).inserted }
                var recordIDs = Set<UUID>()
                index.maintenancePhotos = index.maintenancePhotos.filter { recordIDs.insert($0.recordID).inserted }
                // Every photo listed has to be there, and as long as the list says.
                for (path, bytes) in index.photos.map({ ($0.path, $0.bytes) }) + index.maintenancePhotos.map({ ($0.path, $0.bytes) }) {
                    guard let entry = zip.entry(named: path), entry.size == bytes else { throw LibraryPackageError.damaged }
                    found[path] = entry
                }
                photoIndex = index
            } else {
                photoIndex = nil
            }
            entries = found
        } catch let error as ZipError {
            throw Self.packageError(for: error)
        }
    }

    /// Just enough of the index to tell whether this version can read the rest.
    private struct Version: Decodable {
        let version: Int
    }

    func data(for photo: PackagePhoto) throws -> Data {
        try data(at: photo.path)
    }

    func data(for photo: PackageMaintenancePhoto) throws -> Data {
        try data(at: photo.path)
    }

    /// Reads every photo through and checks it against its checksum, holding none of them: what a
    /// backup does before it's listed.
    func verifyPhotos() throws {
        do {
            for entry in entries.values { try zip.verify(entry) }
        } catch let error as ZipError {
            throw Self.packageError(for: error)
        }
    }

    private func data(at path: String) throws -> Data {
        guard let entry = entries[path] else { throw LibraryPackageError.damaged }
        do {
            return try zip.data(for: entry)
        } catch let error as ZipError {
            throw Self.packageError(for: error)
        }
    }

    private static func packageError(for error: ZipError) -> LibraryPackageError {
        switch error {
        case .notAZipFile: return .notALibrary
        case .unsupported: return .rewritten
        case .tooLarge: return .tooLarge
        case .damaged, .checksumMismatch, .invalidName: return .damaged
        }
    }
}
