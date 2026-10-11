//
//  AppSchema.swift
//  ShutterManager
//
//  The persisted model graph, in one place.
//

import SwiftData

/// Every persisted SwiftData model type the app registers.
///
/// The app container, the preview container and the test container all build from this one
/// list, so adding a `@Model` here registers it everywhere at once. CI checks that every
/// `@Model` is listed (`Tools/ci/check_conventions.py`).
///
/// CloudKit rules for anything added here: no `@Attribute(.unique)`, a default on every
/// non-optional attribute, optional relationships with inverses, and no `.deny` delete rules.
/// A new model or attribute also needs its CloudKit schema deployed to Production before a
/// release that uses it.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        GearItem.self, GearPhoto.self,
        MaintenanceRecord.self, MaintenanceReminder.self,
        ShutterCountReading.self, GearLoan.self,
        DevelopmentRecipe.self, DevelopmentStep.self,
        SavedPlace.self
    ]

    /// The full schema, built from `models`.
    static var schema: Schema { Schema(models) }
}
