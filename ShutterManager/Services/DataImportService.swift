//
//  DataImportService.swift
//  ShutterManager
//
//  Imports a library package, a JSON export or a backup, merging into the library or replacing
//  it.
//

import Foundation
import SwiftData

/// Imports library files. The records are decoded and validated off the main actor before
/// anything changes, and written through an isolated context with autosave off and one final
/// save, so a failure leaves the library as it was.
///
/// A package's photos come after that save, a few at a time (`addPhotos`): all of them in one
/// save would need all of them in memory. If that stops part-way the records are in and some
/// photos aren't, and importing the file again adds the rest.
@MainActor
final class DataImportService {
    /// Where imported settings are written; injectable so tests use a scratch suite.
    private let settingsStore: UserDefaults
    private let saveChanges: (ModelContext) throws -> Void
    /// How many of a package's photos are read and saved at a time.
    private let photoBatch: Int

    init(settingsStore: UserDefaults = .standard, photoBatch: Int = Constants.DataLimits.packagePhotoBatch,
         saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.settingsStore = settingsStore
        self.photoBatch = max(photoBatch, 1)
        self.saveChanges = saveChanges
    }

    /// Posted after an import or restore commits, so reminders and caches can reconcile.
    static let didImportNotification = Notification.Name("LibraryImportDidCommit")

    // MARK: - Preview

    func previewImport(from url: URL) async throws -> ImportPreview {
        guard url.startAccessingSecurityScopedResource() else { throw ImportError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        let file = try await Task.detached { try ImportDocument.open(url) }.value
        return ImportPreview(fileName: url.lastPathComponent, file: file)
    }

    // MARK: - Import

    func importData(from url: URL, to modelContext: ModelContext, strategy: ImportStrategy = .merge) async throws {
        // Held until the last photo is in: a package's photos are read from the file as they go.
        guard url.startAccessingSecurityScopedResource() else { throw ImportError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        let file = try await Task.detached { try ImportDocument.open(url) }.value
        try await apply(file, to: modelContext, strategy: strategy)
    }

    /// Imports already-loaded file data. Separate from the URL overload so the pipeline can be
    /// exercised without a document-picker URL.
    func importData(from data: Data, to modelContext: ModelContext, strategy: ImportStrategy = .merge) async throws {
        let document = try await Task.detached { try ImportDocument.decode(data) }.value
        try await apply(document, to: modelContext, strategy: strategy)
    }

    /// Imports an opened file: its records, then (for a package) its photos.
    func apply(_ file: ImportFile, to modelContext: ModelContext, strategy: ImportStrategy) async throws {
        // The records are in, and announced, before the photos start: a replace has just removed
        // what other screens were showing, and they mustn't wait on the photos to hear of it.
        try await apply(file.document, to: modelContext, strategy: strategy)
        guard let package = file.package, let index = package.photoIndex, index.count > 0 else { return }
        // Announced again when the photos are in, or as far in as they got, so covers and
        // galleries are drawn afresh.
        defer {
            modelContext.processPendingChanges()
            NotificationCenter.default.post(name: Self.didImportNotification, object: nil)
        }
        try await addPhotos(index, from: package, to: modelContext)
    }

    /// Imports records that are already in hand (a JSON file's, with any photos inside them).
    func apply(_ document: LibraryExport, to modelContext: ModelContext, strategy: ImportStrategy) async throws {
        try await commit(document, to: modelContext, strategy: strategy)
        modelContext.processPendingChanges()
        NotificationCenter.default.post(name: Self.didImportNotification, object: nil)
    }

    /// Commits through an isolated context. Failed work is discarded without rolling back deleted
    /// parent/child graphs in the live UI context (which can trap in SwiftData). Settings are
    /// applied only after the records save.
    private func commit(_ document: LibraryExport, to modelContext: ModelContext, strategy: ImportStrategy) async throws {
        try await Task.detached { try ImportDocument.validate(document) }.value
        // Preserve pending UI edits before the import's transaction boundary.
        try modelContext.save()
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        try write(document, to: context, strategy: strategy)
        if let settings = document.settings {
            ImportedSettings.apply(settings, to: settingsStore)
        }
    }

    // MARK: - A package's photos

    /// Adds a package's photos to records already in the library, `photoBatch` at a time. Each
    /// lot is read from the file off the main actor, written through a context of its own, saved
    /// and let go, so memory stays small however many there are.
    ///
    /// A gear photo already in the library (by ID) is left alone, and a maintenance record that
    /// has a photo keeps it. That makes this safe to run again over an import that stopped
    /// part-way, and it's why merging a package also fills in photos an item was missing.
    private func addPhotos(_ index: PackagePhotoIndex, from package: LibraryPackageFile,
                           to modelContext: ModelContext) async throws {
        let container = modelContext.container
        var added = 0
        var total = index.count
        do {
            var known = FetchDescriptor<GearPhoto>()
            known.propertiesToFetch = [\.id]
            let lookup = ModelContext(container)
            // The context has to outlive the reading of what it fetched.
            let present = try withExtendedLifetime(lookup) { Set(try lookup.fetch(known).map(\.id)) }
            let pending = index.photos.filter { !present.contains($0.id) }
            total = pending.count + index.maintenancePhotos.count

            for start in stride(from: 0, to: pending.count, by: photoBatch) {
                let lot = Array(pending[start..<min(start + photoBatch, pending.count)])
                let loaded = try await Task.detached { try lot.map { try package.data(for: $0) } }.value
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let ids = Array(Set(lot.map(\.gearItemID)))
                var itemByID: [UUID: GearItem] = [:]
                for item in try context.fetch(FetchDescriptor<GearItem>(predicate: #Predicate { ids.contains($0.id) }))
                where itemByID[item.id] == nil {
                    itemByID[item.id] = item
                }
                var count = 0
                for (entry, data) in zip(lot, loaded) {
                    // A photo whose item isn't in the library has nothing to hang on.
                    guard let item = itemByID[entry.gearItemID] else { continue }
                    // An item that kept its own photos keeps its own cover.
                    let hasCover = (item.photos ?? []).contains(where: \.isPrimary)
                    let photo = GearPhoto(imageData: data, caption: entry.caption, order: entry.order,
                                          isPrimary: entry.isPrimary && !hasCover)
                    photo.id = entry.id
                    photo.dateAdded = entry.dateAdded
                    context.insert(photo)
                    photo.gearItem = item
                    count += 1
                }
                try saveChanges(context)
                added += count
            }

            for start in stride(from: 0, to: index.maintenancePhotos.count, by: photoBatch) {
                let lot = Array(index.maintenancePhotos[start..<min(start + photoBatch, index.maintenancePhotos.count)])
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let ids = lot.map(\.recordID)
                let records = try context.fetch(FetchDescriptor<MaintenanceRecord>(predicate: #Predicate { ids.contains($0.id) }))
                // Only the photos that are wanted are read from the file.
                let wanted = lot.filter { entry in records.contains { $0.id == entry.recordID && $0.photoData == nil } }
                let loaded = try await Task.detached { try wanted.map { try package.data(for: $0) } }.value
                for (entry, data) in zip(wanted, loaded) {
                    for record in records where record.id == entry.recordID && record.photoData == nil {
                        record.photoData = data
                    }
                }
                try saveChanges(context)
                // Counted whether or not it was needed: either way it's in the library now.
                added += lot.count
            }
        } catch let error as LibraryPackageError {
            throw ImportError.photosIncomplete(added: added, total: total, reason: ImportError(error).localizedDescription)
        } catch {
            throw ImportError.photosIncomplete(added: added, total: total, reason: error.localizedDescription)
        }
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

        // Each ID is added as its record goes in, so a file that lists a record twice (an export
        // of a library that already had duplicates) inserts it once.
        var existing = try strategy == .merge ? ExistingIDs(in: context) : ExistingIDs()
        for dto in document.maintenanceRecords where existing.maintenanceRecords.insert(dto.id).inserted {
            context.insert(dto.toMaintenanceRecord(gearByID: gearByID))
        }
        for dto in document.maintenanceReminders where existing.maintenanceReminders.insert(dto.id).inserted {
            context.insert(dto.toMaintenanceReminder(gearByID: gearByID))
        }
        for dto in document.shutterCountReadings where existing.shutterCountReadings.insert(dto.id).inserted {
            context.insert(dto.toReading(gearByID: gearByID))
        }
        for dto in document.loans where existing.loans.insert(dto.id).inserted {
            context.insert(dto.toLoan(gearByID: gearByID))
        }
        for dto in document.places where existing.savedPlaces.insert(dto.id).inserted {
            if let place = dto.toPlace() { context.insert(place) }
        }
        // A recipe merges whole: one already in the library keeps its own steps.
        for dto in document.recipes where existing.developmentRecipes.insert(dto.id).inserted {
            let (recipe, steps) = dto.toRecipe()
            context.insert(recipe)
            steps.forEach(context.insert)
        }
        // Shoots and templates merge whole too, like recipes. Rolls link to shoots, so shoots
        // come first, with a lookup of every shoot a roll can name.
        var shootByID: [UUID: Shoot] = [:]
        if strategy == .merge {
            shootByID = try context.fetch(FetchDescriptor<Shoot>()).reduce(into: [:]) { $0[$1.id] = $1 }
        }
        for dto in document.shootList where shootByID[dto.id] == nil {
            let (shoot, shotList) = dto.toShoot(gearByID: gearByID)
            context.insert(shoot)
            shotList.forEach(context.insert)
            shootByID[shoot.id] = shoot
        }
        for dto in document.kitList where existing.kits.insert(dto.id).inserted {
            context.insert(dto.toKit(gearByID: gearByID))
        }
        for dto in document.templateList where existing.shotListTemplates.insert(dto.id).inserted {
            let (template, items) = dto.toTemplate()
            context.insert(template)
            items.forEach(context.insert)
        }
        for dto in document.rollList where existing.filmRolls.insert(dto.id).inserted {
            context.insert(dto.toRoll(gearByID: gearByID, shootByID: shootByID))
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
        var savedPlaces: Set<UUID> = []
        var kits: Set<UUID> = []
        var shotListTemplates: Set<UUID> = []
        var filmRolls: Set<UUID> = []

        init() {}

        init(in context: ModelContext) throws {
            maintenanceRecords = Set(try context.fetch(FetchDescriptor<MaintenanceRecord>()).map(\.id))
            maintenanceReminders = Set(try context.fetch(FetchDescriptor<MaintenanceReminder>()).map(\.id))
            shutterCountReadings = Set(try context.fetch(FetchDescriptor<ShutterCountReading>()).map(\.id))
            loans = Set(try context.fetch(FetchDescriptor<GearLoan>()).map(\.id))
            developmentRecipes = Set(try context.fetch(FetchDescriptor<DevelopmentRecipe>()).map(\.id))
            savedPlaces = Set(try context.fetch(FetchDescriptor<SavedPlace>()).map(\.id))
            kits = Set(try context.fetch(FetchDescriptor<Kit>()).map(\.id))
            shotListTemplates = Set(try context.fetch(FetchDescriptor<ShotListTemplate>()).map(\.id))
            filmRolls = Set(try context.fetch(FetchDescriptor<FilmRoll>()).map(\.id))
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
    let placeCount: Int
    let shootCount: Int
    let kitCount: Int
    let templateCount: Int
    let filmRollCount: Int
    let hasSettings: Bool
    let includesPhotos: Bool

    /// A chosen file's contents: a package's photos are counted from its list, a JSON file's
    /// from its records.
    init(fileName: String, file: ImportFile) {
        self.init(fileName: fileName, document: file.document, photoCount: file.photoCount,
                  includesPhotos: file.includesPhotos)
    }

    init(fileName: String, document: LibraryExport, photoCount: Int? = nil, includesPhotos: Bool? = nil) {
        self.fileName = fileName
        exportDate = document.metadata.exportDate
        appVersion = document.metadata.appVersion
        gearCount = document.gearItems.count
        self.photoCount = photoCount ?? document.gearItems.reduce(0) { $0 + ($1.photos?.count ?? 0) }
        maintenanceCount = document.maintenanceRecords.count + document.maintenanceReminders.count
        shutterCountCount = document.shutterCountReadings.count
        loanCount = document.loans.count
        recipeCount = document.recipes.count
        placeCount = document.places.count
        shootCount = document.shootList.count
        kitCount = document.kitList.count
        templateCount = document.templateList.count
        filmRollCount = document.rollList.count
        hasSettings = document.settings != nil
        self.includesPhotos = includesPhotos ?? document.includesPhotos
    }

    var totalItems: Int {
        gearCount + maintenanceCount + shutterCountCount + loanCount + recipeCount + placeCount
            + shootCount + kitCount + templateCount + filmRollCount
    }

    var formattedDate: String { exportDate.formatted(date: .abbreviated, time: .shortened) }
}
