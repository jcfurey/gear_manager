//
//  SensorFormat.swift
//  ShutterManager
//
//  Sensor and film formats, stored by stable ID.
//

import Foundation

/// A sensor or film format: its name and image-area size. Crop factor and diagonal derive from
/// the size, so the depth-of-field and field-of-view tools can use any format.
///
/// `GearItem.sensorFormatID` stores `id`. Built-in IDs are stored in libraries, synced and
/// exported, so **never rename or remove one**. A custom format encodes its size and name in a
/// `custom:` ID (`custom:<width>x<height>:<name>`), so it resolves on any device without a
/// synced table.
struct SensorFormat: Hashable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case digital, film, instant
    }

    let id: String
    let name: String
    /// Image-area width and height in millimetres, width the longer side.
    let width: Double
    let height: Double
    let kind: Kind

    /// The full-frame (36 × 24 mm) diagonal that crop factors are measured against.
    static let fullFrameDiagonal = (36.0 * 36.0 + 24.0 * 24.0).squareRoot()

    var diagonal: Double { (width * width + height * height).squareRoot() }

    /// Full-frame diagonal ÷ this format's diagonal: 1.0 for full frame, about 1.5 for APS-C.
    var cropFactor: Double { diagonal > 0 ? Self.fullFrameDiagonal / diagonal : 1 }

    var isCustom: Bool { id.hasPrefix(Self.customPrefix) }

    /// "36 × 24 mm"
    var sizeText: String {
        "\(Self.format(width)) × \(Self.format(height)) mm"
    }

    /// "Full frame · 36 × 24 mm"
    var detailText: String { "\(name) · \(sizeText)" }

    // MARK: - Lookup

    /// The format for a stored ID: a built-in, a decoded custom format, or nil for "" or an ID
    /// this version doesn't know.
    init?(id: String) {
        if let builtIn = Self.builtInByID[id] {
            self = builtIn
        } else if let custom = Self.decodeCustom(id) {
            self = custom
        } else {
            return nil
        }
    }

    private init(id: String, name: String, width: Double, height: Double, kind: Kind) {
        self.id = id
        self.name = name
        self.width = max(width, height)
        self.height = min(width, height)
        self.kind = kind
    }

    // MARK: - Custom formats

    static let customPrefix = "custom:"

    /// A user-defined format. Returns nil unless both sides are between 0.1 and 1000 mm.
    static func custom(name: String, width: Double, height: Double, kind: Kind = .digital) -> SensorFormat? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizes = 0.1...1000.0
        guard sizes.contains(width), sizes.contains(height) else { return nil }
        let long = max(width, height), short = min(width, height)
        let label = trimmed.isEmpty ? "\(format(long)) × \(format(short)) mm" : trimmed
        let id = "\(customPrefix)\(format(long))x\(format(short)):\(kind.rawValue):\(label)"
        return SensorFormat(id: id, name: label, width: long, height: short, kind: kind)
    }

    private static func decodeCustom(_ id: String) -> SensorFormat? {
        guard id.hasPrefix(customPrefix) else { return nil }
        let parts = id.dropFirst(customPrefix.count).split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let size = parts[0].split(separator: "x")
        guard size.count == 2, let width = Double(size[0]), let height = Double(size[1]),
              let kind = Kind(rawValue: String(parts[1])) else { return nil }
        guard var format = custom(name: String(parts[2]), width: width, height: height, kind: kind) else { return nil }
        // Keep the stored ID exactly, even if re-encoding would spell it differently.
        format = SensorFormat(id: id, name: format.name, width: format.width, height: format.height, kind: kind)
        return format
    }

    /// Plain decimal text with no grouping and at most two places, independent of locale, so
    /// custom IDs read back the same everywhere.
    private static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    // MARK: - Built-in formats

    static let fullFrame = SensorFormat(id: "fullFrame", name: "Full frame", width: 36, height: 24, kind: .digital)
    static let apsH = SensorFormat(id: "apsH", name: "APS-H", width: 27.9, height: 18.6, kind: .digital)
    static let apsC = SensorFormat(id: "apsC", name: "APS-C", width: 23.5, height: 15.6, kind: .digital)
    static let apsCCanon = SensorFormat(id: "apsCCanon", name: "APS-C (Canon)", width: 22.3, height: 14.9, kind: .digital)
    static let microFourThirds = SensorFormat(id: "microFourThirds", name: "Micro Four Thirds", width: 17.3, height: 13.0, kind: .digital)
    static let oneInch = SensorFormat(id: "oneInch", name: "1-inch", width: 13.2, height: 8.8, kind: .digital)
    static let type1over1_3 = SensorFormat(id: "type1over1.3", name: "1/1.3-inch", width: 9.6, height: 7.2, kind: .digital)
    static let type1over2_3 = SensorFormat(id: "type1over2.3", name: "1/2.3-inch", width: 6.17, height: 4.55, kind: .digital)
    static let mediumFormat44x33 = SensorFormat(id: "mediumFormat44x33", name: "Medium format 44×33", width: 43.8, height: 32.9, kind: .digital)
    static let mediumFormat54x40 = SensorFormat(id: "mediumFormat54x40", name: "Medium format 54×40", width: 53.4, height: 40.0, kind: .digital)

    static let film35mm = SensorFormat(id: "film35mm", name: "35mm film", width: 36, height: 24, kind: .film)
    static let filmHalfFrame = SensorFormat(id: "filmHalfFrame", name: "Half-frame", width: 24, height: 18, kind: .film)
    static let film645 = SensorFormat(id: "film645", name: "645", width: 56, height: 41.5, kind: .film)
    static let film6x6 = SensorFormat(id: "film6x6", name: "6×6", width: 56, height: 56, kind: .film)
    static let film6x7 = SensorFormat(id: "film6x7", name: "6×7", width: 70, height: 56, kind: .film)
    static let film6x9 = SensorFormat(id: "film6x9", name: "6×9", width: 84, height: 56, kind: .film)
    static let sheet4x5 = SensorFormat(id: "sheet4x5", name: "4×5 sheet", width: 120, height: 95, kind: .film)
    static let sheet8x10 = SensorFormat(id: "sheet8x10", name: "8×10 sheet", width: 245, height: 194, kind: .film)

    static let instaxMini = SensorFormat(id: "instaxMini", name: "Instax Mini", width: 62, height: 46, kind: .instant)
    static let instaxSquare = SensorFormat(id: "instaxSquare", name: "Instax Square", width: 62, height: 62, kind: .instant)
    static let instaxWide = SensorFormat(id: "instaxWide", name: "Instax Wide", width: 99, height: 62, kind: .instant)
    static let polaroid = SensorFormat(id: "polaroid", name: "Polaroid (i-Type/600)", width: 79, height: 79, kind: .instant)

    /// Every built-in format, in picker order.
    static let builtIns: [SensorFormat] = [
        fullFrame, apsH, apsC, apsCCanon, microFourThirds, oneInch, type1over1_3, type1over2_3,
        mediumFormat44x33, mediumFormat54x40,
        film35mm, filmHalfFrame, film645, film6x6, film6x7, film6x9, sheet4x5, sheet8x10,
        instaxMini, instaxSquare, instaxWide, polaroid
    ]

    private static let builtInByID: [String: SensorFormat] =
        Dictionary(uniqueKeysWithValues: builtIns.map { ($0.id, $0) })
}
