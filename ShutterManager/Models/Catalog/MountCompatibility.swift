//
//  MountCompatibility.swift
//  ShutterManager
//
//  Which lenses go on which bodies: the same mount, a maker's own adapter, or room for a plain
//  one. Foundation-only. Sources are in docs/PHOTO_MATH_REFERENCES.md ("Lens mounts").
//

import Foundation

// MARK: - Flange distances and adapters' names

extension LensMount {
    /// Flange focal distance in millimetres, from the mount's face to the film or sensor, by
    /// `normalized` mount name. A lens focuses to infinity only at its own mount's distance, so
    /// these decide what can be adapted without glass.
    static let flangeDistances: [String: Double] = [
        // Mirrorless
        "canon rf": 20.0, "canon ef-m": 18.0, "nikon z": 16.0, "sony e": 18.0, "fujifilm x": 17.7,
        "fujifilm g": 26.7, "l-mount": 20.0, "micro four thirds": 19.25, "hasselblad xcd": 18.14,
        "nikon 1": 17.0, "samsung nx": 25.5,
        // SLR
        "canon ef": 44.0, "canon ef-s": 44.0, "nikon f": 46.5, "sony a": 44.5, "pentax k": 45.46,
        "four thirds": 38.67, "sigma sa": 44.0, "pentax 645": 70.87, "pentax 67": 84.95,
        "hasselblad h": 61.63,
        // Classic and film
        "leica m": 27.8, "leica r": 47.0, "canon fd": 42.0, "minolta md": 43.5, "olympus om": 46.0,
        "contax/yashica": 45.5, "m42": 45.46, "m39": 28.8, "hasselblad v": 74.9, "mamiya 645": 63.3,
        "mamiya rb67": 112.0, "mamiya rz67": 105.0
    ]

    static func flangeDistance(of mount: String) -> Double? {
        flangeDistances[normalized(mount)]
    }

    /// The mount name for a camera whose lens doesn't come off.
    static let fixedLens = "Fixed lens"

    static func isFixedLens(_ mount: String) -> Bool {
        normalized(mount) == normalized(fixedLens)
    }

    // MARK: Adapters

    /// An adapter's two mounts: the lenses it takes and the bodies it goes on.
    struct AdapterMounts: Equatable, Sendable {
        let lens: String
        let body: String
    }

    /// An adapter's mount is written "Canon EF → Canon RF", the lens side first. It lives in
    /// `GearItem.mount` like any other mount, so it syncs and exports with no new field, and an
    /// app version that doesn't know the form shows it as text. **Never change the form.**
    static func adapterName(lens: String, body: String) -> String {
        "\(lens.trimmingCharacters(in: .whitespaces)) → \(body.trimmingCharacters(in: .whitespaces))"
    }

    /// The two mounts in an adapter's mount name, or nil when it's an ordinary mount. A typed
    /// "->" reads the same as the arrow.
    static func adapterMounts(in mount: String) -> AdapterMounts? {
        for separator in ["→", "->"] {
            let parts = mount.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                return AdapterMounts(lens: parts[0], body: parts[1])
            }
        }
        return nil
    }

    static func isAdapter(_ mount: String) -> Bool { adapterMounts(in: mount) != nil }
}

// MARK: - How a lens fits a body

/// An adapter a camera or lens maker sells, or sold, for its own system. Each is a spacer with
/// no glass in it, so the lens keeps its focal length and reaches infinity.
struct MakerAdapter: Equatable, Sendable {
    /// The maker and the name it gives the adapter.
    let name: String
    /// `LensMount` names of the lenses it takes.
    let lensMounts: [String]
    /// The `LensMount` name of the bodies it goes on.
    let bodyMount: String
}

/// How a lens goes on a body.
enum MountFit: Equatable, Sendable {
    /// The same mount, or a lens line the body takes as it is.
    case native
    /// The camera's maker, or the lens's, sells an adapter for this pair.
    case makerAdapter(MakerAdapter)
    /// No maker's adapter, but the lens sits `room` mm further out than the body's mount needs:
    /// space for an adapter with no glass in it, if one is made for the pair.
    case plainAdapter(room: Double)
    /// The lens would sit `shortfall` mm too far from the sensor (0 when the mounts are merely
    /// too close for an adapter to fit between). It needs an adapter with glass, or it won't
    /// focus to infinity.
    case noPlainAdapter(shortfall: Double)
    /// The lens can't go on this body though the mounts are related.
    case blocked(reason: String)
    /// The camera's lens doesn't come off.
    case fixedLens
    /// A mount isn't set, or isn't one the catalog knows.
    case unknown
}

enum MountCompatibility {
    /// The least a lens's flange distance must exceed the body's for a plain adapter to fit
    /// between them. The thinnest in common use is the ring that puts screw-mount (M39) Leica
    /// lenses on an M body, across the 1 mm between 28.8 and 27.8.
    static let minimumAdapterRoom = 1.0

    /// Lens lines a body takes with no adapter though the names differ: lens mount, body mount.
    static let nativePairs: [(lens: String, body: String)] = [
        ("Canon EF", "Canon EF-S")
    ]

    /// Pairs that share a bayonet but don't go together: lens mount, body mount, why.
    static let blockedPairs: [(lens: String, body: String, reason: String)] = [
        ("Canon EF-S", "Canon EF", "EF-S lenses reach further into the camera and don't mount on full-frame EF bodies.")
    ]

    /// Makers' own adapters, each from the maker's page cited in docs/PHOTO_MATH_REFERENCES.md.
    /// Only what the maker says is listed: Sigma's converters are for Sigma's lenses, so the
    /// Canon EF versions aren't claimed for every EF lens, and an adapter whose maker couldn't be
    /// confirmed is left to the flange distances. Some are no longer sold new.
    static let makerAdapters: [MakerAdapter] = [
        MakerAdapter(name: "Canon Mount Adapter EF-EOS R", lensMounts: ["Canon EF", "Canon EF-S"], bodyMount: "Canon RF"),
        MakerAdapter(name: "Canon Mount Adapter EF-EOS M", lensMounts: ["Canon EF", "Canon EF-S"], bodyMount: "Canon EF-M"),
        MakerAdapter(name: "Nikon Mount Adapter FTZ II", lensMounts: ["Nikon F"], bodyMount: "Nikon Z"),
        MakerAdapter(name: "Nikon Mount Adapter FT1", lensMounts: ["Nikon F"], bodyMount: "Nikon 1"),
        MakerAdapter(name: "Sony LA-EA5 Mount Adaptor", lensMounts: ["Sony A"], bodyMount: "Sony E"),
        MakerAdapter(name: "Olympus Four Thirds Adapter MMF-3", lensMounts: ["Four Thirds"], bodyMount: "Micro Four Thirds"),
        MakerAdapter(name: "Olympus OM Adapter MF-1", lensMounts: ["Olympus OM"], bodyMount: "Four Thirds"),
        MakerAdapter(name: "Olympus OM Adapter MF-2", lensMounts: ["Olympus OM"], bodyMount: "Micro Four Thirds"),
        MakerAdapter(name: "Leica M-Adapter L", lensMounts: ["Leica M"], bodyMount: "L-Mount"),
        MakerAdapter(name: "Leica R-Adapter L", lensMounts: ["Leica R"], bodyMount: "L-Mount"),
        MakerAdapter(name: "Leica R-Adapter M", lensMounts: ["Leica R"], bodyMount: "Leica M"),
        MakerAdapter(name: "Hasselblad XH Lens Adapter", lensMounts: ["Hasselblad H"], bodyMount: "Hasselblad XCD"),
        MakerAdapter(name: "Hasselblad XV Lens Adapter", lensMounts: ["Hasselblad V"], bodyMount: "Hasselblad XCD"),
        MakerAdapter(name: "Hasselblad CF Adapter", lensMounts: ["Hasselblad V"], bodyMount: "Hasselblad H"),
        MakerAdapter(name: "Fujifilm M Mount Adapter", lensMounts: ["Leica M"], bodyMount: "Fujifilm X"),
        MakerAdapter(name: "Fujifilm H Mount Adapter G", lensMounts: ["Hasselblad H"], bodyMount: "Fujifilm G"),
        MakerAdapter(name: "Sigma Mount Converter MC-21 (SA-L)", lensMounts: ["Sigma SA"], bodyMount: "L-Mount"),
        MakerAdapter(name: "Sigma Mount Converter MC-11 (SA-E)", lensMounts: ["Sigma SA"], bodyMount: "Sony E"),
        MakerAdapter(name: "Pentax Mount Adapter K", lensMounts: ["M42"], bodyMount: "Pentax K"),
        MakerAdapter(name: "Pentax Adapter K for 645-System Lenses", lensMounts: ["Pentax 645"], bodyMount: "Pentax K"),
        MakerAdapter(name: "Pentax Adapter K for 67-System Lenses", lensMounts: ["Pentax 67"], bodyMount: "Pentax K"),
        MakerAdapter(name: "Pentax Adapter 645 for 67-System Lenses", lensMounts: ["Pentax 67"], bodyMount: "Pentax 645")
    ]

    /// How a lens with `lensMount` goes on a body with `bodyMount`.
    static func fit(lensMount: String, bodyMount: String) -> MountFit {
        let lens = LensMount.normalized(lensMount), body = LensMount.normalized(bodyMount)
        guard !lens.isEmpty, !body.isEmpty else { return .unknown }
        if LensMount.isFixedLens(lensMount) || LensMount.isFixedLens(bodyMount) { return .fixedLens }
        if lens == body { return .native }
        func same(_ name: String, _ normalizedName: String) -> Bool { LensMount.normalized(name) == normalizedName }

        if nativePairs.contains(where: { same($0.lens, lens) && same($0.body, body) }) { return .native }
        if let blocked = blockedPairs.first(where: { same($0.lens, lens) && same($0.body, body) }) {
            return .blocked(reason: blocked.reason)
        }
        if let adapter = makerAdapters.first(where: { adapter in
            same(adapter.bodyMount, body) && adapter.lensMounts.contains(where: { same($0, lens) })
        }) {
            return .makerAdapter(adapter)
        }
        guard let lensFlange = LensMount.flangeDistances[lens], let bodyFlange = LensMount.flangeDistances[body] else {
            return .unknown
        }
        // Rounded to a hundredth of a millimetre, the precision the distances are given to.
        let room = ((lensFlange - bodyFlange) * 100).rounded() / 100
        return room >= minimumAdapterRoom ? .plainAdapter(room: room) : .noPlainAdapter(shortfall: max(-room, 0))
    }

    /// Whether an adapter with these two mounts puts a lens with `lensMount` on a body with
    /// `bodyMount`. A maker's adapter takes every lens line it's made for, whichever one the
    /// user named it by: an adapter entered as "Canon EF → Canon RF" takes EF-S lenses too.
    static func adapter(_ adapter: LensMount.AdapterMounts, joins lensMount: String, to bodyMount: String) -> Bool {
        guard fit(lensMount: adapter.body, bodyMount: bodyMount) == .native else { return false }
        if fit(lensMount: lensMount, bodyMount: adapter.lens) == .native { return true }
        let lens = LensMount.normalized(lensMount), adapterLens = LensMount.normalized(adapter.lens)
        let adapterBody = LensMount.normalized(adapter.body)
        return makerAdapters.contains(where: { maker in
            LensMount.normalized(maker.bodyMount) == adapterBody
                && maker.lensMounts.contains(where: { LensMount.normalized($0) == adapterLens })
                && maker.lensMounts.contains(where: { LensMount.normalized($0) == lens })
        })
    }
}

// MARK: - A lens and a body from the inventory

/// A lens, body or adapter as the compatibility list sees it.
struct MountedGear: Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var mount: String
    var category: GearCategory
    /// A body's sensor or film format, or the format a lens is made for.
    var format: SensorFormat?

    /// Its two mounts, when it's an adapter.
    var adapterMounts: LensMount.AdapterMounts? { LensMount.adapterMounts(in: mount) }
}

/// How one lens goes on one body, with the adapters the user owns taken into account.
struct LensBodyFit: Equatable, Sendable {
    /// Where a pairing is listed, best first.
    enum Group: Int, CaseIterable, Sendable {
        case fits, ownedAdapter, adapter, doesNotFit, cannotTell

        var title: String {
            switch self {
            case .fits: return "Fits"
            case .ownedAdapter: return "With an Adapter You Have"
            case .adapter: return "With an Adapter"
            case .doesNotFit: return "Doesn't Fit"
            case .cannotTell: return "Can't Tell"
            }
        }
    }

    let fit: MountFit
    /// The user's adapters that join the two mounts, by name.
    let ownedAdapters: [String]
    /// The lens is made for a smaller format than the body's: that format's name.
    let smallerFormat: String?

    /// A lens "covers" a format a little larger than its own: APS-C is a couple of millimetres
    /// wider from one maker than from another, and a lens made for the smaller covers both.
    static let coverageTolerance = 0.9

    init(lens: MountedGear, body: MountedGear, adapters: [MountedGear] = []) {
        fit = MountCompatibility.fit(lensMount: lens.mount, bodyMount: body.mount)
        ownedAdapters = adapters.compactMap { adapter in
            guard let mounts = adapter.adapterMounts,
                  MountCompatibility.adapter(mounts, joins: lens.mount, to: body.mount) else { return nil }
            return adapter.name
        }
        if let lensFormat = lens.format, let bodyFormat = body.format,
           lensFormat.diagonal < bodyFormat.diagonal * Self.coverageTolerance {
            smallerFormat = lensFormat.name
        } else {
            smallerFormat = nil
        }
    }

    var group: Group {
        if fit == .native { return .fits }
        if !ownedAdapters.isEmpty { return .ownedAdapter }
        switch fit {
        case .native: return .fits
        case .makerAdapter, .plainAdapter: return .adapter
        case .noPlainAdapter, .blocked, .fixedLens: return .doesNotFit
        case .unknown: return .cannotTell
        }
    }

    /// One or two sentences on how the lens goes on, for the list. Empty for a plain fit.
    var explanation: String {
        var sentences: [String] = []
        switch group {
        case .fits:
            break
        case .ownedAdapter:
            sentences.append("Goes on with your \(ownedAdapters.joined(separator: " or ")).")
        case .adapter, .doesNotFit, .cannotTell:
            switch fit {
            case .native:
                break
            case .makerAdapter(let adapter):
                sentences.append("Needs the \(adapter.name).")
            case .plainAdapter(let room):
                sentences.append("There's \(Self.millimetres(room)) of room between the mounts for a plain adapter, if one is made for this pair. A lens with no aperture ring needs an adapter that passes its electronics.")
            case .noPlainAdapter(let shortfall):
                sentences.append(shortfall > 0
                    ? "The lens would sit \(Self.millimetres(shortfall)) too far from the sensor to focus at infinity. An adapter needs its own glass."
                    : "The two mounts are too close for an adapter to fit between them.")
            case .blocked(let reason):
                sentences.append(reason)
            case .fixedLens:
                sentences.append("The camera's lens doesn't come off.")
            case .unknown:
                sentences.append("One of the mounts isn't one the app knows.")
            }
        }
        if let smallerFormat, group != .doesNotFit, group != .cannotTell {
            sentences.append("Made for \(smallerFormat): expect a crop or dark corners on this body.")
        }
        return sentences.joined(separator: " ")
    }

    /// "2.5 mm", "28 mm": up to two decimals.
    static func millimetres(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        return "\(text) mm"
    }
}

/// The inventory's lenses for a body, or bodies for a lens, grouped by how they go together.
struct CompatibilityList: Equatable, Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        let gear: MountedGear
        let fit: LensBodyFit
        var id: UUID { gear.id }
    }

    struct Section: Equatable, Sendable, Identifiable {
        let group: LensBodyFit.Group
        let entries: [Entry]
        var id: Int { group.rawValue }
    }

    /// What a piece of gear is, as far as compatibility goes.
    enum Role: Sendable {
        case body, lens, adapter
    }

    let role: Role
    let sections: [Section]

    var isEmpty: Bool { sections.isEmpty }

    /// The role `gear` plays, or nil when compatibility doesn't apply: no mount, or neither a
    /// body nor a lens.
    static func role(of gear: MountedGear) -> Role? {
        guard !LensMount.normalized(gear.mount).isEmpty else { return nil }
        if gear.adapterMounts != nil { return .adapter }
        switch gear.category {
        case .cameraBody: return .body
        case .lens: return .lens
        default: return nil
        }
    }

    /// Pairs `subject` with every lens (for a body) or body (for a lens) in `inventory` that has
    /// a mount set. An adapter is paired with nothing: it shows in the other lists.
    init(subject: MountedGear, inventory: [MountedGear]) {
        let subjectRole = Self.role(of: subject) ?? .adapter
        role = subjectRole
        let adapters = inventory.filter { Self.role(of: $0) == .adapter }
        let others: [MountedGear]
        switch subjectRole {
        case .body: others = inventory.filter { Self.role(of: $0) == .lens }
        case .lens: others = inventory.filter { Self.role(of: $0) == .body }
        case .adapter: others = []
        }
        let entries = others.filter { $0.id != subject.id }.map { other in
            Entry(gear: other, fit: subjectRole == .body
                  ? LensBodyFit(lens: other, body: subject, adapters: adapters)
                  : LensBodyFit(lens: subject, body: other, adapters: adapters))
        }
        sections = LensBodyFit.Group.allCases.compactMap { group in
            let members = entries.filter { $0.fit.group == group }
                .sorted { ($0.gear.name.lowercased(), $0.gear.id.uuidString) < ($1.gear.name.lowercased(), $1.gear.id.uuidString) }
            return members.isEmpty ? nil : Section(group: group, entries: members)
        }
    }
}

// MARK: - Packing

extension CompatibilityList {
    /// Why a lens can't be used with the gear it's packed with, in a few words, or nil when it
    /// can. Nothing is said without a body to judge by, or on a guess (a mount the catalog
    /// doesn't know).
    static func packingIssue(for gear: MountedGear, among packed: [MountedGear]) -> String? {
        guard role(of: gear) == .lens else { return nil }
        let bodies = packed.filter { role(of: $0) == .body && !LensMount.isFixedLens($0.mount) }
        guard !bodies.isEmpty else { return nil }
        let adapters = packed.filter { role(of: $0) == .adapter }
        let fits = bodies.map { LensBodyFit(lens: gear, body: $0, adapters: adapters) }
        // One body it works on is enough.
        let fine: [LensBodyFit.Group] = [.fits, .ownedAdapter, .cannotTell]
        if fits.contains(where: { fine.contains($0.group) }) { return nil }
        for fit in fits {
            if case .makerAdapter(let adapter) = fit.fit {
                return "Needs the \(adapter.name), which isn't on this shoot"
            }
        }
        if fits.contains(where: { $0.group == .adapter }) {
            return "Needs an adapter for the bodies on this shoot"
        }
        return "Doesn't fit a body on this shoot"
    }
}
