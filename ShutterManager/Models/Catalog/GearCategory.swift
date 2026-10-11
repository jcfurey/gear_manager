//
//  GearCategory.swift
//  ShutterManager
//
//  The gear categories, stored by stable ID.
//

import Foundation

/// What kind of gear an item is. `GearItem.category` stores the raw value.
///
/// The raw values are stored in every library, synced through CloudKit and written to exports,
/// so **never rename or remove one**. New categories are fine: add a case with a new raw value.
/// An app version that doesn't know a category reads it as `.other` (see `init(storedID:)`) and
/// keeps the stored ID untouched, so a library edited on a newer device stays intact.
enum GearCategory: String, CaseIterable, Identifiable, Codable {
    case cameraBody
    case lens
    case lighting
    case support
    case filter
    case drone
    case audio
    case power
    case memoryCard
    case bag
    case accessory
    case other

    var id: String { rawValue }

    /// The category for a stored ID, or `.other` for one this version doesn't know.
    init(storedID: String) {
        self = GearCategory(rawValue: storedID) ?? .other
    }

    var displayName: String {
        switch self {
        case .cameraBody: return "Camera Body"
        case .lens: return "Lens"
        case .lighting: return "Flash & Lighting"
        case .support: return "Support"
        case .filter: return "Filter"
        case .drone: return "Drone"
        case .audio: return "Audio"
        case .power: return "Battery & Power"
        case .memoryCard: return "Memory Card"
        case .bag: return "Bag & Case"
        case .accessory: return "Accessory"
        case .other: return "Other"
        }
    }

    /// Example items, for pickers and empty states.
    var examples: String {
        switch self {
        case .cameraBody: return "Digital and film cameras"
        case .lens: return "Primes, zooms, adapters, teleconverters"
        case .lighting: return "Flashes, strobes, LED panels, modifiers"
        case .support: return "Tripods, monopods, gimbals, sliders"
        case .filter: return "ND, polarizer, UV, graduated"
        case .drone: return "Drones and their cameras"
        case .audio: return "Microphones and recorders"
        case .power: return "Batteries, chargers, power banks"
        case .memoryCard: return "SD, CFexpress, microSD"
        case .bag: return "Bags, cases, inserts"
        case .accessory: return "Straps, remotes, cleaning kits"
        case .other: return "Anything else"
        }
    }

    var systemImage: String {
        switch self {
        case .cameraBody: return "camera"
        case .lens: return "camera.aperture"
        case .lighting: return "bolt"
        case .support: return "camera.on.rectangle"
        case .filter: return "circle.lefthalf.filled"
        case .drone: return "airplane"
        case .audio: return "mic"
        case .power: return "battery.100"
        case .memoryCard: return "sdcard"
        case .bag: return "bag"
        case .accessory: return "wrench.and.screwdriver"
        case .other: return "shippingbox"
        }
    }

    // MARK: - Which details apply

    /// Has a lens mount (bodies take lenses; lenses and adapters fit one).
    var hasMount: Bool { self == .cameraBody || self == .lens }

    /// Has a sensor or film format.
    var hasSensorFormat: Bool { self == .cameraBody || self == .drone }

    /// Has firmware worth tracking.
    var hasFirmware: Bool { [.cameraBody, .lens, .lighting, .drone, .audio].contains(self) }

    /// Has a shutter whose actuations wear it out.
    var hasShutter: Bool { self == .cameraBody }

    /// Has a sensor that collects dust.
    var hasSensorCleaning: Bool { self == .cameraBody || self == .drone }

    /// Has a battery with charge cycles.
    var hasChargeCycles: Bool { self == .power || self == .drone }
}
