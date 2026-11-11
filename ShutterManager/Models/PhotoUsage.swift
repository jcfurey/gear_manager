//
//  PhotoUsage.swift
//  ShutterManager
//
//  Shots per body and lens from a batch of photos, matched to the inventory. Foundation-only.
//

import Foundation

/// What one photo says about the gear that took it: the part of its metadata the tally reads.
struct PhotoUsageSample: Equatable, Sendable {
    var cameraMake: String?
    var cameraModel: String?
    var bodySerialNumber: String?
    var lensMake: String?
    var lensModel: String?
    var lensSerialNumber: String?
    var shutterCount: Int?
    var dateTaken: Date?
    /// The focal length the photo was taken at, in millimetres.
    var focalLength: Double?
    /// The aperture it was taken at, as an f-number.
    var aperture: Double?

    var namesCamera: Bool { cameraModel != nil || bodySerialNumber != nil }
    var namesLens: Bool { lensModel != nil || lensSerialNumber != nil }
}

/// A gear item as the matcher sees it.
struct PhotoUsageCandidate: Equatable, Sendable, Identifiable {
    let id: UUID
    var make: String
    var model: String
    var serialNumber: String
    var category: GearCategory
}

/// Which inventory item a group of photos came from.
enum PhotoUsageMatch: Equatable, Sendable {
    case item(UUID)
    /// Several items fit and nothing in the photos tells them apart.
    case ambiguous([UUID])
    /// Nothing in the inventory fits. (Not `none`: that reads as `Optional.none`.)
    case unmatched
}

/// The photos one body or lens took.
struct PhotoUsageGroup: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case camera, lens
    }

    let kind: Kind
    let make: String?
    let model: String?
    let serialNumber: String?
    /// The same for the same gear in every batch: a match the user chose is remembered under it.
    let key: String
    var photoCount = 0
    var firstDate: Date?
    var lastDate: Date?
    /// The shutter count of the latest photo that carries one, and when that photo was taken.
    var shutterCount: Int?
    var shutterCountDate: Date?
    /// A lens's shots at each focal length, by whole millimetre.
    var focalLengthCounts: [Int: Int] = [:]
    /// A lens's shots at each aperture, by tenths of an f-number: 28 is f/2.8.
    var apertureCounts: [Int: Int] = [:]
    var match: PhotoUsageMatch = .unmatched

    var id: String { key }

    init(kind: Kind, make: String?, model: String?, serialNumber: String?) {
        self.kind = kind
        self.make = make
        self.model = model
        self.serialNumber = serialNumber
        key = Self.key(kind: kind, make: make, model: model, serialNumber: serialNumber)
    }

    static func key(kind: Kind, make: String?, model: String?, serialNumber: String?) -> String {
        [kind.rawValue, PhotoUsageMatcher.normalizedName(make), PhotoUsageMatcher.normalizedName(model),
         PhotoUsageMatcher.normalizedSerial(serialNumber)].joined(separator: "|")
    }

    /// "Nikon Z6 III" for a camera. A lens's own name usually starts with its line ("NIKKOR Z
    /// 50mm f/1.8 S"), so it stands alone.
    var displayName: String {
        switch kind {
        case .camera:
            let parts = [make, model].compactMap { $0 }
            if !parts.isEmpty { return parts.joined(separator: " ") }
        case .lens:
            if let model { return model }
            if let make { return "\(make) lens" }
        }
        return serialNumber.map { "Serial number \($0)" } ?? "Unnamed"
    }

    fileprivate mutating func count(dateTaken: Date?) {
        photoCount += 1
        guard let dateTaken else { return }
        firstDate = min(firstDate ?? dateTaken, dateTaken)
        lastDate = max(lastDate ?? dateTaken, dateTaken)
    }

    /// Counts a shot's focal length and aperture, where the photo gives them.
    fileprivate mutating func count(focalLength: Double?, aperture: Double?) {
        if let focalLength, focalLength.isFinite, focalLength >= 0.5, focalLength < 100_000 {
            focalLengthCounts[Int(focalLength.rounded()), default: 0] += 1
        }
        if let aperture, aperture.isFinite, aperture >= 0.05, aperture < 1_000 {
            apertureCounts[Int((aperture * 10).rounded()), default: 0] += 1
        }
    }

    /// Keeps the count of the later photo. A count only goes up, so the higher one decides when
    /// a date is missing or two photos share a second.
    fileprivate mutating func note(shutterCount count: Int, dateTaken: Date?) {
        guard let current = shutterCount else {
            shutterCount = count
            shutterCountDate = dateTaken
            return
        }
        let isLater: Bool
        if let dateTaken, let currentDate = shutterCountDate, dateTaken != currentDate {
            isLater = dateTaken > currentDate
        } else {
            isLater = count > current
        }
        if isLater {
            shutterCount = count
            shutterCountDate = dateTaken
        }
    }
}

// MARK: - How a lens was used

extension PhotoUsageGroup {
    /// One focal length or aperture, and how much of the lens's shots were taken at it.
    struct Share: Equatable, Sendable {
        /// Millimetres for a focal length; tenths of an f-number for an aperture.
        let value: Int
        let count: Int
        /// Of the shots that recorded one.
        let fraction: Double

        var percent: Int { Int((fraction * 100).rounded()) }
    }

    /// The focal lengths a zoom ring is marked with. Shots are gathered to the nearest, by ratio.
    static let focalLengthMarks = [8, 10, 12, 14, 16, 18, 20, 24, 28, 35, 40, 50, 60, 70, 85, 100, 135, 200, 300, 400,
                                   500, 600, 800]

    /// The shortest and longest focal lengths used, or nil when the photos don't give any.
    var focalLengthRange: ClosedRange<Int>? {
        guard let shortest = focalLengthCounts.keys.min(), let longest = focalLengthCounts.keys.max() else { return nil }
        return shortest...longest
    }

    /// The focal lengths used most, most first.
    func mostUsedFocalLengths(_ limit: Int = 2) -> [Share] { Self.shares(of: focalLengthCounts, limit: limit) }

    /// The apertures used most, most first.
    func mostUsedApertures(_ limit: Int = 2) -> [Share] { Self.shares(of: apertureCounts, limit: limit) }

    /// Shots gathered to the nearest mark, for every mark from the shortest used to the longest:
    /// a zoom's picture of where on its range it gets used.
    var focalLengthSpread: [Share] {
        let total = focalLengthCounts.values.reduce(0, +)
        guard total > 0 else { return [] }
        var counts: [Int: Int] = [:]
        for (focalLength, count) in focalLengthCounts {
            counts[Self.nearestMark(to: focalLength), default: 0] += count
        }
        guard let first = counts.keys.min(), let last = counts.keys.max() else { return [] }
        return Self.focalLengthMarks.filter { $0 >= first && $0 <= last }
            .map { Share(value: $0, count: counts[$0] ?? 0, fraction: Double(counts[$0] ?? 0) / Double(total)) }
    }

    /// The mark closest to `focalLength` by ratio: 32 mm is nearer 35 than 28.
    static func nearestMark(to focalLength: Int) -> Int {
        let target = log(Double(max(focalLength, 1)))
        return focalLengthMarks.min { abs(log(Double($0)) - target) < abs(log(Double($1)) - target) } ?? focalLength
    }

    /// "24–70 mm, most at 35 mm (41%) and 50 mm (22%)". Nil for a lens used at one focal length
    /// only, which is every prime, or when the photos don't say.
    var focalLengthSummary: String? {
        guard let range = focalLengthRange, range.lowerBound != range.upperBound else { return nil }
        let most = mostUsedFocalLengths().map { "\($0.value) mm (\($0.percent)%)" }
        return "\(range.lowerBound)–\(range.upperBound) mm, most at \(most.joined(separator: " and "))"
    }

    /// "Most at f/2.8 (60%) and f/4 (25%)", or "All at f/8"; nil when the photos don't say.
    var apertureSummary: String? {
        let most = mostUsedApertures()
        guard let first = most.first else { return nil }
        if apertureCounts.count == 1 { return "All at \(Self.apertureText(first.value))" }
        return "Most at " + most.map { "\(Self.apertureText($0.value)) (\($0.percent)%)" }.joined(separator: " and ")
    }

    /// "f/2.8", "f/4", "f/11" from tenths of an f-number.
    static func apertureText(_ tenths: Int) -> String {
        tenths % 10 == 0 ? "f/\(tenths / 10)" : "f/\(tenths / 10).\(tenths % 10)"
    }

    /// The values with the highest counts, most first; ties go to the smaller value.
    private static func shares(of counts: [Int: Int], limit: Int) -> [Share] {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .prefix(max(limit, 0))
            .map { Share(value: $0.key, count: $0.value, fraction: Double($0.value) / Double(total)) }
    }
}

/// A batch of photos, counted by the body and the lens that took them.
struct PhotoUsageSummary: Equatable, Sendable {
    var photoCount = 0
    /// Photos that don't say which camera took them (scans, screenshots, edited exports).
    var unnamedCameraCount = 0
    /// Photos that don't say which lens took them (manual and adapted lenses don't).
    var unnamedLensCount = 0
    var firstDate: Date?
    var lastDate: Date?
    /// Most photos first.
    var cameras: [PhotoUsageGroup] = []
    var lenses: [PhotoUsageGroup] = []

    var groups: [PhotoUsageGroup] { cameras + lenses }

    init() {}

    /// Counts `samples` and matches each body and lens against `candidates`. `remembered` holds
    /// matches the user chose before, by group key; they win over matching by name.
    init(samples: [PhotoUsageSample], candidates: [PhotoUsageCandidate], remembered: [String: UUID] = [:]) {
        var cameraGroups: [String: PhotoUsageGroup] = [:]
        var lensGroups: [String: PhotoUsageGroup] = [:]
        for sample in samples {
            photoCount += 1
            if let date = sample.dateTaken {
                firstDate = min(firstDate ?? date, date)
                lastDate = max(lastDate ?? date, date)
            }
            if sample.namesCamera {
                var group = PhotoUsageGroup(kind: .camera, make: sample.cameraMake, model: sample.cameraModel,
                                            serialNumber: sample.bodySerialNumber)
                group = cameraGroups[group.key] ?? group
                group.count(dateTaken: sample.dateTaken)
                if let count = sample.shutterCount {
                    group.note(shutterCount: count, dateTaken: sample.dateTaken)
                }
                cameraGroups[group.key] = group
            } else {
                unnamedCameraCount += 1
            }
            if sample.namesLens {
                var group = PhotoUsageGroup(kind: .lens, make: sample.lensMake, model: sample.lensModel,
                                            serialNumber: sample.lensSerialNumber)
                group = lensGroups[group.key] ?? group
                group.count(dateTaken: sample.dateTaken)
                group.count(focalLength: sample.focalLength, aperture: sample.aperture)
                lensGroups[group.key] = group
            } else {
                unnamedLensCount += 1
            }
        }
        func finished(_ groups: [String: PhotoUsageGroup]) -> [PhotoUsageGroup] {
            groups.values
                .map { group in
                    var matched = group
                    matched.match = PhotoUsageMatcher.match(group, among: candidates, remembered: remembered)
                    return matched
                }
                .sorted { ($1.photoCount, $0.displayName, $0.key) < ($0.photoCount, $1.displayName, $1.key) }
        }
        cameras = finished(cameraGroups)
        lenses = finished(lensGroups)
    }
}

/// Decides which inventory item a body or lens named in a photo is.
///
/// A serial number settles it. Without one, the names must agree: the same once case, spaces and
/// punctuation are dropped, or one ending in the other ("NIKKOR Z 50mm f/1.8 S" for an item named
/// "Z 50mm f/1.8 S"). An item whose serial number differs from the photo's is another copy.
enum PhotoUsageMatcher {
    /// The shortest name that can match as the ending of a longer one.
    static let minimumLooseLength = 4

    /// Lowercase letters and digits only. Nikon writes "Z 6_2" for the Z6 II.
    static func normalizedName(_ text: String?) -> String {
        guard var name = text?.lowercased() else { return "" }
        for (suffix, numeral) in [("_2", "ii"), ("_3", "iii")] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count)) + numeral
        }
        return String(name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Uppercase letters and digits, without leading zeros (some cameras pad the serial number).
    static func normalizedSerial(_ text: String?) -> String {
        guard let text else { return "" }
        let serial = String(text.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return String(serial.drop { $0 == "0" })
    }

    /// Makes agree when either is unknown, or one starts with the other ("Nikon", "Nikon Corporation").
    static func makesAgree(_ first: String?, _ second: String?) -> Bool {
        let one = normalizedName(first), other = normalizedName(second)
        return one.isEmpty || other.isEmpty || one.hasPrefix(other) || other.hasPrefix(one)
    }

    /// The names something goes by: its model, and its make and model together (an item may
    /// have its whole name in the model field). Nothing without a model: a make names no one item.
    static func nameKeys(make: String?, model: String?) -> Set<String> {
        let modelKey = normalizedName(model)
        guard !modelKey.isEmpty else { return [] }
        return [modelKey, normalizedName(make) + modelKey]
    }

    /// The items that could be a camera, or a lens. "Other" could be either.
    static func pool(for kind: PhotoUsageGroup.Kind, in candidates: [PhotoUsageCandidate]) -> [PhotoUsageCandidate] {
        candidates.filter { candidate in
            switch kind {
            case .camera: return [.cameraBody, .drone, .other].contains(candidate.category)
            case .lens: return [.lens, .other].contains(candidate.category)
            }
        }
    }

    static func match(_ group: PhotoUsageGroup, among candidates: [PhotoUsageCandidate],
                      remembered: [String: UUID] = [:]) -> PhotoUsageMatch {
        let kindPool = pool(for: group.kind, in: candidates)
        if let chosen = remembered[group.key], kindPool.contains(where: { $0.id == chosen }) {
            return .item(chosen)
        }
        let pool = kindPool.filter { makesAgree($0.make, group.make) }
        let named = itemsNamed(make: group.make, model: group.model, in: pool)
        let serial = normalizedSerial(group.serialNumber)

        if !serial.isEmpty {
            let sameSerial = pool.filter { normalizedSerial($0.serialNumber) == serial }
            let sameSerialAndName = sameSerial.filter { candidate in named.contains { $0.id == candidate.id } }
            let settled = sameSerialAndName.isEmpty ? sameSerial : sameSerialAndName
            if settled.count == 1 { return .item(settled[0].id) }
            if settled.count > 1 { return .ambiguous(settled.map(\.id)) }
        }
        // By name. An item with a different serial number is another copy of the same model.
        let open = named.filter { serial.isEmpty || normalizedSerial($0.serialNumber).isEmpty }
        switch open.count {
        case 0: return .unmatched
        case 1: return .item(open[0].id)
        default: return .ambiguous(open.map(\.id))
        }
    }

    /// The items whose name is the photo's; failing that, those where one name ends in the other.
    private static func itemsNamed(make: String?, model: String?, in pool: [PhotoUsageCandidate]) -> [PhotoUsageCandidate] {
        let names = nameKeys(make: make, model: model)
        guard !names.isEmpty else { return [] }
        let exact = pool.filter { !nameKeys(make: $0.make, model: $0.model).isDisjoint(with: names) }
        if !exact.isEmpty { return exact }
        return pool.filter { candidate in
            nameKeys(make: candidate.make, model: candidate.model).contains { own in
                names.contains { name in
                    let shorter = own.count <= name.count ? own : name
                    let longer = own.count <= name.count ? name : own
                    return shorter.count >= minimumLooseLength && longer.hasSuffix(shorter)
                }
            }
        }
    }
}
