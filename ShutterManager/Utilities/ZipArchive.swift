//
//  ZipArchive.swift
//  ShutterManager
//
//  A zip file written and read with Foundation alone: the container a library package travels
//  in. Entries are stored as they are, not compressed, since photos are compressed already; that
//  leaves only the format's bookkeeping, and a file any computer can open.
//  The layout is in docs/PHOTO_MATH_REFERENCES.md, "Library package".
//

import Foundation

enum ZipError: Error, Equatable {
    /// Not a zip file at all.
    case notAZipFile
    /// A zip file whose records disagree with the file: cut short, or changed in transit.
    case damaged
    /// A zip file this reader can't open: compressed, encrypted, split, or in the 64-bit form.
    /// One written by `ZipWriter` never is.
    case unsupported
    /// An entry's bytes don't match the checksum written with them.
    case checksumMismatch(name: String)
    /// More bytes or entries than the format, or the caller's limit, allows.
    case tooLarge
    /// A name that's empty, too long, or already in the file.
    case invalidName(String)
}

/// The zip format's numbers.
enum ZipFormat {
    static let localHeaderSignature: UInt32 = 0x0403_4B50
    static let centralHeaderSignature: UInt32 = 0x0201_4B50
    static let endSignature: UInt32 = 0x0605_4B50
    static let localHeaderLength = 30
    static let centralHeaderLength = 46
    static let endLength = 22

    /// One short of the values the format keeps to mean "see the 64-bit records".
    static let maximumBytes: UInt64 = 0xFFFF_FFFE
    static let maximumEntries = 0xFFFE
    /// The most directory this reader will load: far past what the most entries need.
    static let maximumDirectoryBytes: UInt64 = 64 * 1024 * 1024

    /// Version 2.0, the lowest that knows folders in names.
    static let version: UInt16 = 20
    /// Bit 11: names are UTF-8.
    static let utf8Flag: UInt16 = 0x0800
    static let encryptedFlag: UInt16 = 0x0001
    static let storedMethod: UInt16 = 0
}

/// CRC-32 as zip uses it (the IEEE 802.3 polynomial, reflected).
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    /// The checksum of `data`, or of everything so far when `previous` is the checksum of what
    /// came before it.
    static func checksum(_ data: Data, continuing previous: UInt32 = 0) -> UInt32 {
        var crc = ~previous
        table.withUnsafeBufferPointer { table in
            data.withUnsafeBytes { bytes in
                for byte in bytes {
                    crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
                }
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func append(littleEndian value: UInt32) {
        append(littleEndian: UInt16(value & 0xFFFF))
        append(littleEndian: UInt16(value >> 16))
    }

    /// The 16-bit number at `offset` from the start, or nil past the end.
    func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let base = startIndex + offset
        return UInt16(self[base]) | UInt16(self[base + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32? {
        guard let low = uint16(at: offset), let high = uint16(at: offset + 2) else { return nil }
        return UInt32(low) | UInt32(high) << 16
    }
}

private extension FileHandle {
    /// Exactly `count` bytes from `offset`; fewer means the file ends early.
    func readExactly(_ count: Int, at offset: UInt64) throws -> Data {
        try seek(toOffset: offset)
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard let piece = try read(upToCount: count - data.count), !piece.isEmpty else { throw ZipError.damaged }
            data.append(piece)
        }
        return data
    }
}

// MARK: - Writing

/// Writes a zip file one entry at a time. Each entry is given whole, so its checksum and size
/// go in front of it and the file needs no second pass.
final class ZipWriter {
    private struct Record {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private let handle: FileHandle
    private let maximumBytes: UInt64
    private let time: UInt16
    private let date: UInt16
    private var records: [Record] = []
    private var names = Set<String>()
    private var entryBytes: UInt64 = 0
    private var directoryBytes: UInt64 = 0
    private var isOpen = true

    /// Creates the file at `url`, replacing any there. `date` stamps every entry.
    /// `maximumBytes` is the largest the finished file may be.
    init(url: URL, date: Date = Date(), maximumBytes: UInt64 = ZipFormat.maximumBytes) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        self.maximumBytes = min(maximumBytes, ZipFormat.maximumBytes)
        let stamp = Self.dosStamp(date)
        time = stamp.time
        self.date = stamp.date
    }

    /// The file's size if it were finished now.
    var finishedSize: UInt64 { entryBytes + directoryBytes + UInt64(ZipFormat.endLength) }

    var entryCount: Int { records.count }

    /// Adds `data` under `name`. Throws `ZipError.tooLarge`, having written nothing, when the
    /// finished file would pass the limit.
    func add(_ name: String, _ data: Data) throws {
        guard isOpen else { throw ZipError.damaged }
        let nameBytes = Data(name.utf8)
        guard !nameBytes.isEmpty, nameBytes.count <= Int(UInt16.max), names.insert(name).inserted else {
            throw ZipError.invalidName(name)
        }
        let local = UInt64(ZipFormat.localHeaderLength + nameBytes.count) + UInt64(data.count)
        let central = UInt64(ZipFormat.centralHeaderLength + nameBytes.count)
        guard records.count < ZipFormat.maximumEntries, finishedSize + local + central <= maximumBytes else {
            names.remove(name)
            throw ZipError.tooLarge
        }
        let record = Record(name: nameBytes, crc: CRC32.checksum(data), size: UInt32(data.count), offset: UInt32(entryBytes))
        var header = Data(capacity: ZipFormat.localHeaderLength + nameBytes.count)
        header.append(littleEndian: ZipFormat.localHeaderSignature)
        appendCommonFields(of: record, to: &header)
        header.append(littleEndian: UInt16(nameBytes.count))
        header.append(littleEndian: UInt16(0)) // No extra field.
        header.append(nameBytes)
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)
        records.append(record)
        entryBytes += local
        directoryBytes += central
    }

    /// Writes the directory and closes the file. Without it the file isn't a zip.
    func finish() throws {
        guard isOpen else { return }
        var directory = Data(capacity: Int(directoryBytes) + ZipFormat.endLength)
        for record in records {
            directory.append(littleEndian: ZipFormat.centralHeaderSignature)
            directory.append(littleEndian: ZipFormat.version) // Made by: plain files, no permissions.
            appendCommonFields(of: record, to: &directory)
            directory.append(littleEndian: UInt16(record.name.count))
            directory.append(littleEndian: UInt16(0)) // Extra field.
            directory.append(littleEndian: UInt16(0)) // Comment.
            directory.append(littleEndian: UInt16(0)) // Disk.
            directory.append(littleEndian: UInt16(0)) // Internal attributes.
            directory.append(littleEndian: UInt32(0)) // External attributes.
            directory.append(littleEndian: record.offset)
            directory.append(record.name)
        }
        let count = UInt16(records.count)
        directory.append(littleEndian: ZipFormat.endSignature)
        directory.append(littleEndian: UInt16(0)) // This disk.
        directory.append(littleEndian: UInt16(0)) // The directory's disk.
        directory.append(littleEndian: count)
        directory.append(littleEndian: count)
        directory.append(littleEndian: UInt32(directoryBytes))
        directory.append(littleEndian: UInt32(entryBytes))
        directory.append(littleEndian: UInt16(0)) // Comment.
        try handle.write(contentsOf: directory)
        try close()
    }

    /// Closes the file as it stands, for a writer that's giving up. The caller removes the file.
    func close() throws {
        guard isOpen else { return }
        isOpen = false
        try handle.close()
    }

    /// The fields a local header and a directory record share, from "version needed" to the sizes.
    private func appendCommonFields(of record: Record, to data: inout Data) {
        data.append(littleEndian: ZipFormat.version)
        data.append(littleEndian: ZipFormat.utf8Flag)
        data.append(littleEndian: ZipFormat.storedMethod)
        data.append(littleEndian: time)
        data.append(littleEndian: date)
        data.append(littleEndian: record.crc)
        data.append(littleEndian: record.size) // Compressed.
        data.append(littleEndian: record.size) // Uncompressed: the same, stored.
    }

    /// A date as zip keeps it: two-second steps, years from 1980 to 2107, no time zone. UTC here.
    static func dosStamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max((parts.year ?? 1980) - 1980, 0), 127)
        let day = UInt16(year) << 9 | UInt16(parts.month ?? 1) << 5 | UInt16(parts.day ?? 1)
        let time = UInt16(parts.hour ?? 0) << 11 | UInt16(parts.minute ?? 0) << 5 | UInt16((parts.second ?? 0) / 2)
        return (time, day)
    }
}

// MARK: - Reading

/// Reads a zip file. Opening it reads the directory; an entry's bytes are read when asked for,
/// so a large file is never held whole. Safe to use from more than one task: reads take turns.
final class ZipReader: @unchecked Sendable {
    struct Entry: Equatable, Sendable {
        let name: String
        let size: Int
        let crc: UInt32
        fileprivate let headerOffset: UInt64
    }

    /// The entries, in the directory's order.
    let entries: [Entry]
    let fileSize: UInt64

    private let byName: [String: Entry]
    private let directoryOffset: UInt64
    private let handle: FileHandle
    private let lock = NSLock()
    /// Checksums are worked out over pieces this long, so checking a file doesn't hold it.
    private static let pieceLength = 1024 * 1024

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        do {
            fileSize = try handle.seekToEnd()
            let end = try Self.findEnd(in: handle, fileSize: fileSize)
            guard end.directoryOffset + end.directoryLength <= end.offset,
                  end.directoryLength <= ZipFormat.maximumDirectoryBytes else { throw ZipError.damaged }
            let directory = try handle.readExactly(Int(end.directoryLength), at: end.directoryOffset)
            entries = try Self.parse(directory, count: end.entryCount, directoryOffset: end.directoryOffset)
            directoryOffset = end.directoryOffset
            var lookup: [String: Entry] = [:]
            for entry in entries {
                guard lookup.updateValue(entry, forKey: entry.name) == nil else { throw ZipError.damaged }
            }
            byName = lookup
        } catch {
            try? handle.close()
            throw error
        }
    }

    deinit {
        try? handle.close()
    }

    func entry(named name: String) -> Entry? { byName[name] }

    /// The entry's bytes, checked against its checksum.
    func data(for entry: Entry) throws -> Data {
        let data = try locked {
            try handle.readExactly(entry.size, at: try dataOffset(of: entry))
        }
        guard CRC32.checksum(data) == entry.crc else { throw ZipError.checksumMismatch(name: entry.name) }
        return data
    }

    /// Checks the entry's bytes against its checksum without holding them all.
    func verify(_ entry: Entry) throws {
        var crc: UInt32 = 0
        var done = 0
        let start = try locked { try dataOffset(of: entry) }
        while done < entry.size {
            let length = min(Self.pieceLength, entry.size - done)
            let piece = try locked { try handle.readExactly(length, at: start + UInt64(done)) }
            crc = CRC32.checksum(piece, continuing: crc)
            done += length
        }
        guard crc == entry.crc else { throw ZipError.checksumMismatch(name: entry.name) }
    }

    private func locked<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    /// Where the entry's bytes begin: past its local header, whose name and extra field needn't
    /// be as long as the directory's. Call with the lock held.
    private func dataOffset(of entry: Entry) throws -> UInt64 {
        let header = try handle.readExactly(ZipFormat.localHeaderLength, at: entry.headerOffset)
        guard header.uint32(at: 0) == ZipFormat.localHeaderSignature,
              let nameLength = header.uint16(at: 26), let extraLength = header.uint16(at: 28) else {
            throw ZipError.damaged
        }
        let start = entry.headerOffset + UInt64(ZipFormat.localHeaderLength) + UInt64(nameLength) + UInt64(extraLength)
        guard start + UInt64(entry.size) <= directoryOffset else { throw ZipError.damaged }
        return start
    }

    private struct End {
        let offset: UInt64
        let entryCount: Int
        let directoryLength: UInt64
        let directoryOffset: UInt64
    }

    /// Finds the record that ends a zip file. It's the last thing in the file but for a comment
    /// of up to 65,535 bytes, so it's looked for backwards from the end.
    private static func findEnd(in handle: FileHandle, fileSize: UInt64) throws -> End {
        let tailLength = Int(min(fileSize, UInt64(ZipFormat.endLength + Int(UInt16.max))))
        guard tailLength >= ZipFormat.endLength else { throw ZipError.notAZipFile }
        let tail = try handle.readExactly(tailLength, at: fileSize - UInt64(tailLength))
        var position = tailLength - ZipFormat.endLength
        while position >= 0 {
            if tail.uint32(at: position) == ZipFormat.endSignature,
               let comment = tail.uint16(at: position + 20), position + ZipFormat.endLength + Int(comment) <= tailLength {
                guard let disk = tail.uint16(at: position + 4), let directoryDisk = tail.uint16(at: position + 6),
                      let here = tail.uint16(at: position + 8), let total = tail.uint16(at: position + 10),
                      let length = tail.uint32(at: position + 12), let offset = tail.uint32(at: position + 16) else {
                    throw ZipError.damaged
                }
                // Split across files, or in the 64-bit form, whose real numbers are elsewhere.
                guard disk == 0, directoryDisk == 0, here == total, total != UInt16.max,
                      length != UInt32.max, offset != UInt32.max else { throw ZipError.unsupported }
                return End(offset: fileSize - UInt64(tailLength) + UInt64(position), entryCount: Int(total),
                           directoryLength: UInt64(length), directoryOffset: UInt64(offset))
            }
            position -= 1
        }
        // It starts like a zip but has no end: cut short. Anything else was never one.
        let start = try handle.readExactly(4, at: 0)
        throw start.uint32(at: 0) == ZipFormat.localHeaderSignature ? ZipError.damaged : ZipError.notAZipFile
    }

    private static func parse(_ directory: Data, count: Int, directoryOffset: UInt64) throws -> [Entry] {
        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var position = 0
        for _ in 0..<count {
            guard directory.uint32(at: position) == ZipFormat.centralHeaderSignature,
                  let flags = directory.uint16(at: position + 8), let method = directory.uint16(at: position + 10),
                  let crc = directory.uint32(at: position + 16),
                  let packed = directory.uint32(at: position + 20), let size = directory.uint32(at: position + 24),
                  let nameLength = directory.uint16(at: position + 28), let extraLength = directory.uint16(at: position + 30),
                  let commentLength = directory.uint16(at: position + 32),
                  let offset = directory.uint32(at: position + 42) else { throw ZipError.damaged }
            let nameStart = position + ZipFormat.centralHeaderLength
            let next = nameStart + Int(nameLength) + Int(extraLength) + Int(commentLength)
            guard next <= directory.count else { throw ZipError.damaged }
            guard flags & ZipFormat.encryptedFlag == 0, method == ZipFormat.storedMethod,
                  size != UInt32.max, offset != UInt32.max else { throw ZipError.unsupported }
            guard packed == size, UInt64(offset) + UInt64(ZipFormat.localHeaderLength) <= directoryOffset else {
                throw ZipError.damaged
            }
            let nameBytes = directory.subdata(in: (directory.startIndex + nameStart)..<(directory.startIndex + nameStart + Int(nameLength)))
            entries.append(Entry(name: String(decoding: nameBytes, as: UTF8.self), size: Int(size), crc: crc,
                                 headerOffset: UInt64(offset)))
            position = next
        }
        return entries
    }
}
