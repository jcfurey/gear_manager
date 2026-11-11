//
//  PhotoUsageRecorder.swift
//  ShutterManager
//
//  Writes what a batch of photos showed into the library: shutter counts, missing gear, and the
//  gear used on a shoot.
//

import Foundation
import SwiftData

/// What the user wants done with a body or lens named in the photos.
enum PhotoUsageAssignment: Hashable, Sendable {
    /// Counted, but nothing is written for it. (Not `none`: that reads as `Optional.none`.)
    case leftOut
    /// Add it to the inventory.
    case new
    /// It's this inventory item.
    case item(UUID)
}

/// Works out and saves what a batch of photos adds to the library, in one save.
///
/// Nothing here stores a tally: an item's use comes from the shoot log, so the photos become a
/// shoot (or add their gear to one), and a body's wear comes from its shutter-count readings.
@MainActor
struct PhotoUsageRecorder {
    enum ShootChoice {
        case noShoot
        /// Log a new shoot over the photos' dates.
        case new(title: String)
        /// Add the gear used to a shoot that's already in the log.
        case existing(Shoot)
    }

    /// What a save writes.
    struct Outcome: Equatable {
        var gearAdded = 0
        var readingsAdded = 0
        /// Items put on the shoot: on a new one, or newly on an existing one.
        var gearLinked = 0
        var shootAdded = false

        var isEmpty: Bool { gearAdded == 0 && readingsAdded == 0 && gearLinked == 0 && !shootAdded }

        /// "add 2 items to your inventory", "record 1 shutter count", "log a shoot with 3 items".
        var parts: [String] {
            var parts: [String] = []
            if gearAdded > 0 {
                parts.append("add \(gearAdded == 1 ? "1 item" : "\(gearAdded) items") to your inventory")
            }
            if readingsAdded > 0 {
                parts.append("record \(readingsAdded == 1 ? "1 shutter count" : "\(readingsAdded) shutter counts")")
            }
            let linked = gearLinked == 1 ? "1 item" : "\(gearLinked) items"
            if shootAdded {
                parts.append(gearLinked > 0 ? "log a shoot with \(linked)" : "log a shoot")
            } else if gearLinked > 0 {
                parts.append("add \(linked) to the shoot")
            }
            return parts
        }
    }

    var summary: PhotoUsageSummary
    /// By group key. A group with no entry is left out.
    var assignments: [String: PhotoUsageAssignment]
    var recordsShutterCounts = true
    var shoot: ShootChoice = .noShoot

    /// Each group starts as the item the matcher found; anything unsure waits for the user.
    static func initialAssignments(for summary: PhotoUsageSummary) -> [String: PhotoUsageAssignment] {
        var assignments: [String: PhotoUsageAssignment] = [:]
        for group in summary.groups {
            if case .item(let id) = group.match { assignments[group.key] = .item(id) }
        }
        return assignments
    }

    // MARK: - Planning

    /// One body or lens that's going into the library, or is already there.
    private struct Entry {
        let group: PhotoUsageGroup
        /// Nil for gear to add.
        let item: GearItem?
        var addsReading = false
    }

    private func entries(in items: [GearItem]) -> [Entry] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var readings = Set<String>()
        return summary.groups.compactMap { group -> Entry? in
            var entry: Entry
            switch assignments[group.key] ?? .leftOut {
            case .leftOut: return nil
            case .new: entry = Entry(group: group, item: nil)
            case .item(let id):
                guard let item = byID[id] else { return nil }
                entry = Entry(group: group, item: item)
            }
            if recordsShutterCounts, group.kind == .camera, let count = group.shutterCount {
                if let item = entry.item {
                    // Only a body has a shutter-count history, and a count it already has adds
                    // nothing: choosing the same photos twice records them once.
                    entry.addsReading = item.gearCategory.hasShutter
                        && !(item.shutterCountReadings ?? []).contains(where: { $0.count == count })
                        && readings.insert("\(item.id)|\(count)").inserted
                } else {
                    entry.addsReading = true
                }
            }
            return entry
        }
    }

    /// The existing items among `entries`, once each.
    private func existingItems(in entries: [Entry]) -> [GearItem] {
        var seen = Set<UUID>()
        return entries.compactMap(\.item).filter { seen.insert($0.id).inserted }
    }

    private func outcome(of entries: [Entry]) -> Outcome {
        var outcome = Outcome()
        outcome.gearAdded = entries.filter { $0.item == nil }.count
        outcome.readingsAdded = entries.filter(\.addsReading).count
        let existing = existingItems(in: entries)
        switch shoot {
        case .noShoot:
            break
        case .new:
            // A shoot needs a date, and only the photos can give one.
            if summary.firstDate != nil {
                outcome.shootAdded = true
                outcome.gearLinked = existing.count + outcome.gearAdded
            }
        case .existing(let shoot):
            let onShoot = Set((shoot.gear ?? []).map(\.id))
            outcome.gearLinked = existing.filter { !onShoot.contains($0.id) }.count + outcome.gearAdded
        }
        return outcome
    }

    /// What `save` would write, without writing it.
    func preview(items: [GearItem]) -> Outcome {
        outcome(of: entries(in: items))
    }

    // MARK: - Saving

    /// Writes everything in one save. Returns what was written, or nil when the save failed and
    /// was undone.
    func save(in context: ModelContext, items: [GearItem], now: Date = Date()) -> Outcome? {
        let planned = entries(in: items)
        let result = outcome(of: planned)
        guard !result.isEmpty else { return result }

        let snapshots = existingItems(in: planned).map { GearRelationshipSnapshot($0) }
        var existingShoot: Shoot?
        if case .existing(let shoot) = shoot { existingShoot = shoot }
        let gearBefore = existingShoot?.gear

        var used: [GearItem] = []
        for entry in planned {
            let item: GearItem
            if let existing = entry.item {
                item = existing
            } else {
                item = GearItem(category: entry.group.kind == .camera ? .cameraBody : .lens, dateAdded: now,
                                make: entry.group.make, model: entry.group.model,
                                serialNumber: entry.group.serialNumber)
                context.insert(item)
            }
            if entry.addsReading, let count = entry.group.shutterCount {
                context.insert(ShutterCountReading(gearItem: item, date: entry.group.shutterCountDate ?? now,
                                                   count: count, source: .photo))
                item.markModified()
            }
            if !used.contains(where: { $0 === item }) { used.append(item) }
        }

        switch shoot {
        case .noShoot:
            break
        case .new(let title):
            if let start = summary.firstDate {
                let logged = Shoot(title: title.trimmingCharacters(in: .whitespacesAndNewlines), startDate: start,
                                   endDate: summary.lastDate ?? start,
                                   notes: "Logged from \(summary.photoCount == 1 ? "1 photo" : "\(summary.photoCount) photos").")
                context.insert(logged)
                logged.gear = used
            }
        case .existing(let shoot):
            let onShoot = Set((shoot.gear ?? []).map(\.id))
            let added = used.filter { !onShoot.contains($0.id) }
            if !added.isEmpty {
                shoot.gear = (shoot.gear ?? []) + added
                shoot.markModified()
            }
        }

        guard context.saveOrLog() else {
            // Detach the new readings while they're still valid, undo, then put back whatever
            // the observed arrays kept (see `GearRelationshipSnapshot`).
            snapshots.forEach { $0.restore() }
            context.rollback()
            snapshots.forEach { $0.restore() }
            existingShoot?.gear = gearBefore
            return nil
        }
        return result
    }
}
