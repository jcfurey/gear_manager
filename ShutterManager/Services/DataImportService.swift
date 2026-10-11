//
//  DataImportService.swift
//  ShutterManager
//
//  Imports an export or backup file, merging into the library or replacing it.
//

import Foundation
import SwiftData

/// Imports `LibraryExport` files. The whole file is decoded and validated off the main actor
/// before anything changes, and the import writes through an isolated context with autosave off
/// and one final save, so a failure leaves the library as it was.
@MainActor
final class DataImportService {
    /// Where imported settings are written; injectable so tests use a scratch suite.
    private let settingsStore: UserDefaults
    private let saveChanges: (ModelContext) throws -> Void

    init(settingsStore: UserDefaults = .standard,
         saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.settingsStore = settingsStore
        self.saveChanges = saveChanges
    }

    /// Posted after an import or restore commits, so reminders and caches can reconcile.
    static let didImportNotification = Notification.Name("LibraryImportDidCommit")

    // MARK: - Preview

    func previewImport(from url: URL) async throws -> ImportPreview {
        guard url.startAccessingSecurityScopedResource() else { throw ImportError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        let document = try await Task.detached { try ImportDocument.decode(ImportDocument.read(url)) }.value
        return ImportPreview(fileName: url.lastPathComponent, document: document)
    }

    // MARK: - Import

    func importData(from url: URL, to modelContext: ModelContext, strategy: ImportStrategy = .merge) async throws {
        guard url.startAccessingSecurityScopedResource() else { throw ImportError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        let data = try await Task.detached { try ImportDocument.read(url) }.value
        try await importData(from: data, to: modelContext, strategy: strategy)
    }

    /// Imports already-loaded file data. Separate from the URL overload so the pipeline can be
    /// exercised without a document-picker URL.
    func importData(from data: Data, to modelContext: ModelContext, strategy: ImportStrategy = .merge) async throws {
        let document = try await Task.detached { try ImportDocument.decode(data) }.value
        try await apply(document, to: modelContext, strategy: strategy)
    }

    /// Commits through an isolated context. Failed work is discarded without rolling back deleted
    /// parent/child graphs in the live UI context (which can trap in SwiftData). Settings are
    /// applied only after the records save.
    func apply(_ document: LibraryExport, to modelContext: ModelContext, strategy: ImportStrategy) async throws {
        try await Task.detached { try ImportDocument.validate(document) }.value
        // Preserve pending UI edits before the import's transaction boundary.
        try modelContext.save()
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        try write(document, to: context, strategy: strategy)
        if let settings = document.settings {
            ImportedSettings.apply(settings, to: settingsStore)
        }
        modelContext.processPendingChanges()
        NotificationCenter.default.post(name: Self.didImportNotification, object: nil)
    }

    private func write(_ document: LibraryExport, to context: ModelContext, strategy: ImportStrategy) throws {
        if strategy == .replace {
            // Every model in the schema, children included, so orphans go too and a new model
            // can't be missed.
            try context.deleteEveryRecord()
        }

        // Gear first, keeping a lookup of every item a child record can link to: the ones
        // inserted here, plus (when merging) the ones already in the library.
        var gearByID: [UUID: GearItem] = [:]
        if strategy == .merge {
            gearByID = try context.fetch(FetchDescriptor<GearItem>()).reduce(into: [:]) { $0[$1.id] = $1 }
        }
        for dto in document.gearItems where gearByID[dto.id] == nil {
            let item = dto.toGearItem()
            context.insert(item)
            gearByID[item.id] = item
        }

        let existing = try strategy == .merge ? ExistingIDs(in: context) : ExistingIDs()
        for dto in document.maintenanceRecords where !existing.maintenanceRecords.contains(dto.id) {
            context.insert(dto.toMaintenanceRecord(gearByID: gearByID))
        }
        for dto in document.maintenanceReminders where !existing.maintenanceReminders.contains(dto.id) {
            context.insert(dto.toMaintenanceReminder(gearByID: gearByID))
        }
        for dto in document.shutterCountReadings where !existing.shutterCountReadings.contains(dto.id) {
            context.insert(dto.toReading(gearByID: gearByID))
        }
        for dto in document.loans where !existing.loans.contains(dto.id) {
            context.insert(dto.toLoan(gearByID: gearByID))
        }
        // A recipe merges whole: one already in the library keeps its own steps.
        for dto in document.recipes where !existing.developmentRecipes.contains(dto.id) {
            let (recipe, steps) = dto.toRecipe()
            context.insert(recipe)
            steps.forEach(context.insert)
        }
        try saveChanges(context)
    }

    /// IDs already in the library, so a merge skips records it has (one fetch per type instead
    /// of one per record).
    private struct ExistingIDs {
        var maintenanceRecords: Set<UUID> = []
        var maintenanceReminders: Set<UUID> = []
        var shutterCountReadings: Set<UUID> = []
        var loans: Set<UUID> = []
        var developmentRecipes: Set<UUID> = []

        init() {}

        init(in context: ModelContext) throws {
            maintenanceRecords = Set(try context.fetch(FetchDescriptor<MaintenanceRecord>()).map(\.id))
            maintenanceReminders = Set(try context.fetch(FetchDescriptor<MaintenanceReminder>()).map(\.id))
            shutterCountReadings = Set(try context.fetch(FetchDescriptor<ShutterCountReading>()).map(\.id))
            loans = Set(try context.fetch(FetchDescriptor<GearLoan>()).map(\.id))
            developmentRecipes = Set(try context.fetch(FetchDescriptor<DevelopmentRecipe>()).map(\.id))
        }
    }
}

// MARK: - Supporting Types

enum ImportStrategy {
    /// Add what the library doesn't have; keep everything it does.
    case merge
    /// Delete the library, then import.
    case replace
}

/// What a file contains, shown before importing.
struct ImportPreview {
    let fileName: String
    let exportDate: Date
    let appVersion: String
    let gearCount: Int
    let photoCount: Int
    let maintenanceCount: Int
    let shutterCountCount: Int
    let loanCount: Int
    let recipeCount: Int
    let hasSettings: Bool
    let includesPhotos: Bool

    init(fileName: String, document: LibraryExport) {
        self.fileName = fileName
        exportDate = document.metadata.exportDate
        appVersion = document.metadata.appVersion
        gearCount = document.gearItems.count
        photoCount = document.gearItems.reduce(0) { $0 + ($1.photos?.count ?? 0) }
        maintenanceCount = document.maintenanceRecords.count + document.maintenanceReminders.count
        shutterCountCount = document.shutterCountReadings.count
        loanCount = document.loans.count
        recipeCount = document.recipes.count
        hasSettings = document.settings != nil
        includesPhotos = document.includesPhotos
    }

    var totalItems: Int { gearCount + maintenanceCount + shutterCountCount + loanCount + recipeCount }

    var formattedDate: String { exportDate.formatted(date: .abbreviated, time: .shortened) }
}
