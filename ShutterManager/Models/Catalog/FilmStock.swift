//
//  FilmStock.swift
//  ShutterManager
//
//  Film stocks, stored by stable ID, with each maker's long-exposure (reciprocity) guidance.
//  Foundation-only. Sources: docs/PHOTO_MATH_REFERENCES.md § Film stocks.
//

import Foundation

/// A film stock: its speed, process and the maker's reciprocity guidance.
///
/// IDs are stored in recipes and (from M4) film rolls, synced and exported, so **never rename or
/// remove a built-in ID**. A custom stock encodes its speed, process, optional reciprocity
/// exponent and name in a `custom:` ID, so it resolves on any device without a synced table.
struct FilmStock: Hashable, Identifiable, Sendable {
    enum Process: String, CaseIterable, Identifiable, Sendable {
        case blackAndWhite = "bw"
        case c41 = "c41"
        case e6 = "e6"
        case ecn2 = "ecn2"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .blackAndWhite: return "Black and white"
            case .c41: return "C-41 colour negative"
            case .e6: return "E-6 slide"
            case .ecn2: return "ECN-2 motion picture"
            }
        }

        /// The development template that fits the process.
        var shortName: String {
            switch self {
            case .blackAndWhite: return "B&W"
            case .c41: return "C-41"
            case .e6: return "E-6"
            case .ecn2: return "ECN-2"
            }
        }
    }

    let id: String
    let maker: String
    let name: String
    /// Box speed.
    let iso: Int
    let process: Process
    let reciprocity: ReciprocityModel
    /// What else the maker says about long exposures (development or filter changes), shown with
    /// the corrected time.
    let reciprocityNote: String?
    /// The datasheet the figures come from.
    let source: String?

    var displayName: String { maker.isEmpty ? name : "\(maker) \(name)" }
    var isCustom: Bool { id.hasPrefix(Self.customPrefix) }

    init(id: String, maker: String, name: String, iso: Int, process: Process,
         reciprocity: ReciprocityModel, reciprocityNote: String? = nil, source: String? = nil) {
        self.id = id
        self.maker = maker
        self.name = name
        self.iso = iso
        self.process = process
        self.reciprocity = reciprocity
        self.reciprocityNote = reciprocityNote
        self.source = source
    }

    // MARK: - Lookup

    /// The built-in stock with this ID, or the custom stock it encodes.
    init?(id: String) {
        if let builtIn = Self.builtInByID[id] {
            self = builtIn
        } else if let custom = Self.decodeCustom(id) {
            self = custom
        } else {
            return nil
        }
    }

    // MARK: - Custom stocks

    static let customPrefix = "custom:"

    /// A stock the catalog doesn't have. `exponent` is a power-law reciprocity exponent (Tc = Tm^p
    /// beyond one second) for films whose maker publishes one; without it the calculator shows the
    /// metered time unchanged.
    static func custom(name: String, iso: Int, process: Process, exponent: Double? = nil) -> FilmStock? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100_000).contains(iso) else { return nil }
        if let exponent, !(exponent.isFinite && (1...3).contains(exponent)) { return nil }
        let exponentText = exponent.map { ExposureScale.decimal($0, places: 3) } ?? "0"
        let id = "\(customPrefix)\(iso):\(process.rawValue):\(exponentText):\(trimmed)"
        return decodeCustom(id)
    }

    /// `custom:<iso>:<process>:<exponent or 0>:<name>`. The name is last, so it may contain colons.
    private static func decodeCustom(_ id: String) -> FilmStock? {
        guard id.hasPrefix(customPrefix) else { return nil }
        let parts = id.dropFirst(customPrefix.count).split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, let iso = Int(parts[0]), (1...100_000).contains(iso),
              let process = Process(rawValue: String(parts[1])), let exponent = Double(parts[2]),
              exponent == 0 || (exponent.isFinite && (1...3).contains(exponent)) else { return nil }
        let name = String(parts[3])
        return FilmStock(id: id, maker: "", name: name.isEmpty ? "ISO \(iso) \(process.shortName)" : name,
                         iso: iso, process: process,
                         reciprocity: exponent == 0 ? .unpublished : .powerLaw(exponent: exponent, from: 1))
    }

    // MARK: - Catalog

    /// Every built-in stock, grouped by maker in display order.
    static var builtIns: [FilmStock] { FilmStockCatalog.all }

    private static let builtInByID: [String: FilmStock] =
        Dictionary(uniqueKeysWithValues: FilmStockCatalog.all.map { ($0.id, $0) })

    /// Makers in catalog order, for grouped pickers.
    static var makers: [String] {
        var seen = Set<String>()
        return builtIns.map(\.maker).filter { seen.insert($0).inserted }
    }
}
