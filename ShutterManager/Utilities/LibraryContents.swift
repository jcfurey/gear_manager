//
//  LibraryContents.swift
//  ShutterManager
//
//  The records a full export or backup covers, read in one place.
//

import Foundation
import SwiftData

/// Everything an export or backup writes. Export, backups and the record counts read the library
/// through this type, so a new top-level record type is added here once rather than at every
/// call site. Child records (photos, maintenance, readings, loans, recipe steps) travel with
/// their parents, as do shot lists and template items. Every property but `gearItems` and
/// `developmentRecipes` has a default, so call sites that only deal with those keep compiling as
/// records are added.
struct LibraryContents {
    var gearItems: [GearItem]
    var developmentRecipes: [DevelopmentRecipe]
    var savedPlaces: [SavedPlace] = []
    var shoots: [Shoot] = []
    var kits: [Kit] = []
    var shotListTemplates: [ShotListTemplate] = []
    var filmRolls: [FilmRoll] = []

    static let empty = LibraryContents(gearItems: [], developmentRecipes: [])

    static func fetch(from context: ModelContext) throws -> LibraryContents {
        LibraryContents(
            gearItems: try context.fetch(FetchDescriptor<GearItem>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])),
            developmentRecipes: try context.fetch(FetchDescriptor<DevelopmentRecipe>(sortBy: [SortDescriptor(\.name)])),
            savedPlaces: try context.fetch(FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\.name)])),
            shoots: try context.fetch(FetchDescriptor<Shoot>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])),
            kits: try context.fetch(FetchDescriptor<Kit>(sortBy: [SortDescriptor(\.name)])),
            shotListTemplates: try context.fetch(FetchDescriptor<ShotListTemplate>(sortBy: [SortDescriptor(\.name)])),
            filmRolls: try context.fetch(FetchDescriptor<FilmRoll>(sortBy: [SortDescriptor(\.loadedDate, order: .reverse)])))
    }

    /// Records other than gear items: their child records, recipes with their steps, places,
    /// shoots with their shot lists, kits, templates with their items, and film rolls.
    var otherRecordCount: Int {
        let gearChildren = gearItems.reduce(0) { total, item in
            total + (item.maintenanceRecords?.count ?? 0) + (item.maintenanceReminders?.count ?? 0)
                + (item.shutterCountReadings?.count ?? 0) + (item.loans?.count ?? 0)
        }
        return gearChildren + developmentRecipes.reduce(0) { $0 + 1 + ($1.steps?.count ?? 0) }
            + savedPlaces.count
            + shoots.reduce(0) { $0 + 1 + ($1.shotList?.count ?? 0) }
            + kits.count
            + shotListTemplates.reduce(0) { $0 + 1 + ($1.items?.count ?? 0) }
            + filmRolls.count
    }

    var isEmpty: Bool {
        gearItems.isEmpty && developmentRecipes.isEmpty && savedPlaces.isEmpty && shoots.isEmpty
            && kits.isEmpty && shotListTemplates.isEmpty && filmRolls.isEmpty
    }
}

extension ModelContext {
    /// Deletes every record of every model in `AppSchema`, so nothing is missed when a model is
    /// added. The caller saves.
    func deleteEveryRecord() throws {
        for type in AppSchema.models {
            try deleteAll(type)
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        for model in try fetch(FetchDescriptor<T>()) { delete(model) }
    }
}
