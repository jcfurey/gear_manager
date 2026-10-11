//
//  Kit.swift
//  ShutterManager
//
//  Saved sets of gear ("wedding", "astro") to add to a shoot in one go.
//

import Foundation
import SwiftData

/// A named set of gear. Adding a kit to a shoot adds its gear to the shoot's packing list.
@Model
final class Kit {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    /// An SF Symbol name from `Kit.symbols`.
    var symbol: String = "bag"
    var dateCreated: Date = Date()

    /// Many-to-many: `GearItem.kits` is the other side, and deleting either end only unlinks them.
    @Relationship(inverse: \GearItem.kits)
    var gear: [GearItem]? = []

    init(name: String = "", notes: String = "", symbol: String = "bag") {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.symbol = symbol
        self.dateCreated = Date()
    }

    /// The symbols a kit can show.
    static let symbols = ["bag", "backpack", "suitcase", "suitcase.rolling", "camera", "heart", "moon.stars", "mountain.2",
                          "person.crop.square", "video", "airplane", "star"]

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil ?? "Untitled Kit"
    }

    /// The gear, grouped by category and then by name.
    var orderedGear: [GearItem] { (gear ?? []).gearSorted(by: .category) }
}

extension Shoot {
    /// Adds `kit`'s gear that isn't on the shoot yet. Returns how many items were added.
    @discardableResult
    func add(_ kit: Kit) -> Int {
        let existing = Set((gear ?? []).map(\.id))
        let new = (kit.gear ?? []).filter { !existing.contains($0.id) }
        gear = (gear ?? []) + new
        return new.count
    }
}

/// An editable copy of a kit. Written to the kit only on Save.
struct KitDraft: Equatable {
    var name = ""
    var notes = ""
    var symbol = "bag"
    var gearIDs: Set<UUID> = []

    init() {}

    init(kit: Kit) {
        name = kit.name
        notes = kit.notes
        symbol = kit.symbol
        gearIDs = Set((kit.gear ?? []).map(\.id))
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Writes the draft into `kit`, linking the items of `gear` it names. The caller saves.
    func apply(to kit: Kit, gear: [GearItem]) {
        kit.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        kit.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        kit.symbol = symbol
        kit.gear = gear.filter { gearIDs.contains($0.id) }
    }
}
