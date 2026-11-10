//
//  LibraryDeduplicator.swift
//  ShutterManager
//
//  Finds records the library holds twice and folds each set into one.
//

import Foundation
import SwiftData

/// Folds together records doubled by importing a file before iCloud had finished downloading the
/// same library.
///
/// SwiftData mirrors to CloudKit with no unique constraints, so a record that arrives from
/// iCloud after an import has already added it stays as a second row with the same `id`. This
/// finds those rows and keeps one of each, with everything that hung off the others.
///
/// It runs only when the user asks, and they're told to do it on one device. Nothing in a row
/// says which copy it is, so two devices choosing for themselves could each keep the copy the
/// other deletes, and iCloud would then remove both. That rules out an automatic pass.
@MainActor
enum LibraryDeduplicator {
    /// Extra copies, by kind: a record held three times counts as two.
    struct Report: Equatable {
        var gear = 0
        var recipes = 0
        var places = 0
        var shoots = 0
        var kits = 0
        var templates = 0
        var rolls = 0
        /// Records that belong to another: photos, maintenance, shutter counts, loans, recipe
        /// steps, shots and template items.
        var parts = 0

        var total: Int { gear + recipes + places + shoots + kits + templates + rolls + parts }
        var isEmpty: Bool { total == 0 }

        /// "3 gear items", "1 shoot", "12 photos and history records": only the kinds found.
        var lines: [String] {
            func line(_ count: Int, _ one: String, _ many: String) -> String? {
                count == 0 ? nil : (count == 1 ? "1 \(one)" : "\(count) \(many)")
            }
            return [
                line(gear, "gear item", "gear items"),
                line(shoots, "shoot", "shoots"),
                line(kits, "kit", "kits"),
                line(rolls, "film roll", "film rolls"),
                line(recipes, "development recipe", "development recipes"),
                line(templates, "shot-list template", "shot-list templates"),
                line(places, "saved place", "saved places"),
                line(parts, "photo, history record or list entry", "photos, history records and list entries")
            ].compactMap { $0 }
        }
    }

    // MARK: - Finding

    /// Counts the extra copies without changing anything.
    static func find(in context: ModelContext) throws -> Report {
        var report = Report()
        report.gear = extras(try all(GearItem.self, in: context), id: \.id)
        report.recipes = extras(try all(DevelopmentRecipe.self, in: context), id: \.id)
        report.places = extras(try all(SavedPlace.self, in: context), id: \.id)
        report.shoots = extras(try all(Shoot.self, in: context), id: \.id)
        report.kits = extras(try all(Kit.self, in: context), id: \.id)
        report.templates = extras(try all(ShotListTemplate.self, in: context), id: \.id)
        report.rolls = extras(try all(FilmRoll.self, in: context), id: \.id)
        report.parts = extras(try all(GearPhoto.self, in: context), id: \.id)
            + extras(try all(MaintenanceRecord.self, in: context), id: \.id)
            + extras(try all(MaintenanceReminder.self, in: context), id: \.id)
            + extras(try all(ShutterCountReading.self, in: context), id: \.id)
            + extras(try all(GearLoan.self, in: context), id: \.id)
            + extras(try all(DevelopmentStep.self, in: context), id: \.id)
            + extras(try all(ShotListItem.self, in: context), id: \.id)
            + extras(try all(ShotListTemplateItem.self, in: context), id: \.id)
        return report
    }

    // MARK: - Merging

    /// Folds each set of doubles into one record and returns what was removed. The caller saves,
    /// or rolls back.
    ///
    /// Of each set, the copy changed most recently is kept (where the record keeps that date),
    /// then the one with the most hanging off it. It takes over whatever the others had that it
    /// lacks: history, photos, list entries, and their places on shoots, in kits and on rolls.
    @discardableResult
    static func merge(in context: ModelContext) throws -> Report {
        var report = Report()

        // Gear first: shoots, kits and rolls point at it.
        for group in doubles(try all(GearItem.self, in: context), id: \.id) {
            let keep = survivor(of: group) { ($0.dateModified, Self.weight(of: $0)) }
            for extra in group where extra !== keep {
                report.parts += adopt(extra.photos, existing: keep.photos, id: \.id, in: context) { $0.gearItem = keep }
                report.parts += adopt(extra.maintenanceRecords, existing: keep.maintenanceRecords, id: \.id, in: context) { $0.gearItem = keep }
                report.parts += adopt(extra.maintenanceReminders, existing: keep.maintenanceReminders, id: \.id, in: context) { $0.gearItem = keep }
                report.parts += adopt(extra.shutterCountReadings, existing: keep.shutterCountReadings, id: \.id, in: context) { $0.gearItem = keep }
                report.parts += adopt(extra.loans, existing: keep.loans, id: \.id, in: context) { $0.gearItem = keep }
                for shoot in extra.shoots ?? [] {
                    shoot.gear = replacing(extra, with: keep, in: shoot.gear)
                }
                for kit in extra.kits ?? [] {
                    kit.gear = replacing(extra, with: keep, in: kit.gear)
                }
                for roll in extra.filmRolls ?? [] {
                    roll.camera = keep
                }
                context.delete(extra)
                report.gear += 1
            }
        }

        for group in doubles(try all(Shoot.self, in: context), id: \.id) {
            let keep = survivor(of: group) { ($0.dateModified, ($0.shotList?.count ?? 0) + ($0.gear?.count ?? 0)) }
            for extra in group where extra !== keep {
                report.parts += adopt(extra.shotList, existing: keep.shotList, id: \.id, in: context) { $0.shoot = keep }
                keep.gear = union(keep.gear, extra.gear)
                keep.packedIDs.formUnion(extra.packedIDs)
                for roll in extra.filmRolls ?? [] {
                    roll.shoot = keep
                }
                context.delete(extra)
                report.shoots += 1
            }
        }

        for group in doubles(try all(Kit.self, in: context), id: \.id) {
            let keep = survivor(of: group) { $0.gear?.count ?? 0 }
            for extra in group where extra !== keep {
                keep.gear = union(keep.gear, extra.gear)
                context.delete(extra)
                report.kits += 1
            }
        }

        for group in doubles(try all(DevelopmentRecipe.self, in: context), id: \.id) {
            let keep = survivor(of: group) { ($0.dateModified, $0.steps?.count ?? 0) }
            for extra in group where extra !== keep {
                report.parts += adopt(extra.steps, existing: keep.steps, id: \.id, in: context) { $0.recipe = keep }
                context.delete(extra)
                report.recipes += 1
            }
        }

        for group in doubles(try all(ShotListTemplate.self, in: context), id: \.id) {
            let keep = survivor(of: group) { $0.items?.count ?? 0 }
            for extra in group where extra !== keep {
                report.parts += adopt(extra.items, existing: keep.items, id: \.id, in: context) { $0.template = keep }
                context.delete(extra)
                report.templates += 1
            }
        }

        // A roll that names its camera and shoot is the fuller copy.
        for group in doubles(try all(FilmRoll.self, in: context), id: \.id) {
            let keep = survivor(of: group) { ($0.camera == nil ? 0 : 1) + ($0.shoot == nil ? 0 : 1) }
            for extra in group where extra !== keep {
                context.delete(extra)
                report.rolls += 1
            }
        }

        for group in doubles(try all(SavedPlace.self, in: context), id: \.id) {
            for extra in group.dropFirst() {
                context.delete(extra)
                report.places += 1
            }
        }

        // What's left: a part doubled under one owner, or with no owner at all.
        report.parts += try removeExtraParts(GearPhoto.self, id: \.id, in: context) { $0.gearItem }
        report.parts += try removeExtraParts(MaintenanceRecord.self, id: \.id, in: context) { $0.gearItem }
        report.parts += try removeExtraParts(MaintenanceReminder.self, id: \.id, in: context) { $0.gearItem }
        report.parts += try removeExtraParts(ShutterCountReading.self, id: \.id, in: context) { $0.gearItem }
        report.parts += try removeExtraParts(GearLoan.self, id: \.id, in: context) { $0.gearItem }
        report.parts += try removeExtraParts(DevelopmentStep.self, id: \.id, in: context) { $0.recipe }
        report.parts += try removeExtraParts(ShotListItem.self, id: \.id, in: context) { $0.shoot }
        report.parts += try removeExtraParts(ShotListTemplateItem.self, id: \.id, in: context) { $0.template }
        return report
    }

    // MARK: - Pieces

    /// Every record of a type that isn't already marked for deletion.
    private static func all<M: PersistentModel>(_ type: M.Type, in context: ModelContext) throws -> [M] {
        try context.fetch(FetchDescriptor<M>()).filter { !$0.isDeleted }
    }

    /// The sets of records that share an ID.
    private static func doubles<M>(_ records: [M], id: KeyPath<M, UUID>) -> [[M]] {
        Dictionary(grouping: records) { $0[keyPath: id] }.values.filter { $0.count > 1 }
    }

    /// How many records are extra copies of another.
    private static func extras<M>(_ records: [M], id: KeyPath<M, UUID>) -> Int {
        records.count - Set(records.map { $0[keyPath: id] }).count
    }

    /// The copy to keep: the one that ranks highest, the first of equals.
    private static func survivor<M, Rank: Comparable>(of group: [M], rank: (M) -> Rank) -> M {
        var best = group[0]
        var bestRank = rank(best)
        for candidate in group.dropFirst() {
            let candidateRank = rank(candidate)
            if candidateRank > bestRank {
                best = candidate
                bestRank = candidateRank
            }
        }
        return best
    }

    private static func survivor<M, First: Comparable, Second: Comparable>(of group: [M], rank: (M) -> (First, Second)) -> M {
        var best = group[0]
        var bestRank = rank(best)
        for candidate in group.dropFirst() {
            let candidateRank = rank(candidate)
            if candidateRank > bestRank {
                best = candidate
                bestRank = candidateRank
            }
        }
        return best
    }

    private static func weight(of item: GearItem) -> Int {
        (item.photos?.count ?? 0) + (item.maintenanceRecords?.count ?? 0) + (item.maintenanceReminders?.count ?? 0)
            + (item.shutterCountReadings?.count ?? 0) + (item.loans?.count ?? 0)
            + (item.shoots?.count ?? 0) + (item.kits?.count ?? 0) + (item.filmRolls?.count ?? 0)
    }

    /// Hands the kept record each part of an extra copy that it doesn't have itself, and deletes
    /// the parts it does. Returns how many were deleted.
    private static func adopt<Part: PersistentModel>(_ parts: [Part]?, existing: [Part]?, id: KeyPath<Part, UUID>,
                                                      in context: ModelContext, attach: (Part) -> Void) -> Int {
        var held = Set((existing ?? []).map { $0[keyPath: id] })
        var removed = 0
        for part in parts ?? [] {
            if held.insert(part[keyPath: id]).inserted {
                attach(part)
            } else {
                context.delete(part)
                removed += 1
            }
        }
        return removed
    }

    /// `gear` with `extra` taken out and `keep` in its place, once.
    private static func replacing(_ extra: GearItem, with keep: GearItem, in gear: [GearItem]?) -> [GearItem] {
        var result = (gear ?? []).filter { $0 !== extra }
        if !result.contains(where: { $0 === keep }) { result.append(keep) }
        return result
    }

    /// Both lists' gear, each item once.
    private static func union(_ first: [GearItem]?, _ second: [GearItem]?) -> [GearItem] {
        var result = first ?? []
        for item in second ?? [] where !item.isDeleted && !result.contains(where: { $0 === item }) {
            result.append(item)
        }
        return result
    }

    /// Deletes the extra copies of a part, keeping the one whose owner is still in the library.
    private static func removeExtraParts<Part: PersistentModel, Owner: PersistentModel>(
        _ type: Part.Type, id: KeyPath<Part, UUID>, in context: ModelContext, ownerOf: (Part) -> Owner?
    ) throws -> Int {
        var removed = 0
        for group in doubles(try all(type, in: context), id: id) {
            let keep = survivor(of: group) { part -> Int in
                guard let owner = ownerOf(part) else { return 0 }
                return owner.isDeleted ? -1 : 1
            }
            for extra in group where extra !== keep {
                context.delete(extra)
                removed += 1
            }
        }
        return removed
    }
}
