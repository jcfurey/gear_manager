//
//  LibraryExport.swift
//  ShutterManager
//
//  The JSON export and backup format, and the DTOs that mirror each model.
//

import Foundation

/// A whole-library export or backup. Every record type is a flat array; child records name
/// their gear item by `gearItemID`.
///
/// Compatibility rules, which keep every file the app ever wrote importable:
/// - Fields added later are optional (or decode with a default), so older files still decode.
/// - Newer files carry keys this version doesn't know; decoding ignores them.
/// - Stored IDs (categories, formats, maintenance types) travel as text, never as enums, so a
///   value added by a newer version doesn't fail the whole file.
struct LibraryExport: Codable {
    /// Bumped only for a change older readers can't handle by ignoring keys.
    static let currentFormatVersion = 1

    var formatVersion: Int = LibraryExport.currentFormatVersion
    let metadata: ExportMetadata
    // `var` (here and on the DTOs' Double fields) so `replaceUnrestorableNumbers()` can rewrite them.
    var gearItems: [GearItemDTO]
    var maintenanceRecords: [MaintenanceRecordDTO]
    var maintenanceReminders: [MaintenanceReminderDTO]
    var shutterCountReadings: [ShutterCountReadingDTO]
    var loans: [GearLoanDTO]
    /// Added in 1.0 development (M2); absent from earlier files, so optional.
    var developmentRecipes: [DevelopmentRecipeDTO]? = nil
    let settings: [String: String]?
    /// Whether photos were included, so a restore can warn before replacing photos with none.
    let includesPhotos: Bool

    /// Total records, for previews and the record-count limit.
    var recordCount: Int {
        gearItems.count + maintenanceRecords.count + maintenanceReminders.count
            + shutterCountReadings.count + loans.count
            + gearItems.reduce(0) { $0 + ($1.photos?.count ?? 0) }
            + recipes.reduce(0) { $0 + 1 + $1.steps.count }
    }

    /// `developmentRecipes`, empty for files written before recipes existed.
    var recipes: [DevelopmentRecipeDTO] { developmentRecipes ?? [] }
}

/// Header written into every export file.
struct ExportMetadata: Codable {
    let appName: String
    let appVersion: String
    let exportDate: Date
    let format: ExportFormat
}

/// Data file formats. PDF reports are separate (see `EnhancedExportFormat`).
enum ExportFormat: String, CaseIterable, Codable {
    case json
    case csv

    var displayName: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

/// Every format the export screen offers.
enum EnhancedExportFormat: String, CaseIterable, Codable {
    case json, csv, pdf

    var displayName: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }

    var icon: String {
        switch self {
        case .json: return "doc.text"
        case .csv: return "tablecells"
        case .pdf: return "doc.richtext"
        }
    }

    var description: String {
        switch self {
        case .json: return "Complete library. Use this to move to another device or keep a copy"
        case .csv: return "Spreadsheet of your gear, for Numbers, Excel or Google Sheets"
        case .pdf: return "A printable inventory with serial numbers and values"
        }
    }
}

// MARK: - Gear

/// Codable mirror of a gallery photo.
struct GearPhotoDTO: Codable {
    let id: UUID
    let imageData: Data
    let caption: String?
    let order: Int
    let dateAdded: Date
    let isPrimary: Bool

    init(from photo: GearPhoto) {
        id = photo.id
        imageData = photo.imageData
        caption = photo.caption
        order = photo.order
        dateAdded = photo.dateAdded
        isPrimary = photo.isPrimary
    }

    func toGearPhoto() -> GearPhoto {
        let photo = GearPhoto(imageData: imageData, caption: caption, order: order, isPrimary: isPrimary)
        photo.id = id
        photo.dateAdded = dateAdded
        return photo
    }
}

/// Codable mirror of `GearItem`. Money is Double on the wire and goes back to `Decimal` through
/// `Decimal(roundTripping:)`, which avoids binary-float artifacts. Camera fields are optional so
/// a hand-trimmed or older file still imports, with model defaults for what's missing.
struct GearItemDTO: Codable {
    let id: UUID
    let category: String
    let dateAdded: Date
    let dateModified: Date?
    let make: String?
    let model: String?
    let serialNumber: String?
    let manufacturingYear: Int?
    let upcCode: String?
    let notes: String?
    let purchaseDate: Date?
    var purchasePrice: Double?
    var currentValue: Double?
    let serviceNeeded: Bool?
    let serviceNotes: String?
    let sensorCleaningIntervalDays: Int?
    let lastSensorCleaningDate: Date?
    let reminderHour: Int?
    let reminderMinute: Int?
    let mount: String?
    let sensorFormatID: String?
    let resolutionWidthPx: Int?
    let resolutionHeightPx: Int?
    var focalLengthMin: Double?
    var focalLengthMax: Double?
    var maxApertureWide: Double?
    var maxApertureTele: Double?
    var minFocusDistance: Double?
    var filterThread: Double?
    var filterStops: Double?
    var guideNumber: Double?
    let firmwareVersion: String?
    let ratedShutterLife: Int?
    let chargeCycles: Int?
    let ratedChargeCycles: Int?
    var capacityGB: Double?
    let cardType: String?
    let speedRating: String?
    let referenceLinks: String?
    let photos: [GearPhotoDTO]?

    /// `includePhotos: false` leaves out the gallery, for size-sensitive exports and backups.
    init(from item: GearItem, includePhotos: Bool = true) {
        id = item.id
        category = item.category
        dateAdded = item.dateAdded
        dateModified = item.dateModified
        make = item.make
        model = item.model
        serialNumber = item.serialNumber
        manufacturingYear = item.manufacturingYear
        upcCode = item.upcCode
        notes = item.notes
        purchaseDate = item.purchaseDate
        purchasePrice = item.purchasePrice?.doubleValue
        currentValue = item.currentValue?.doubleValue
        serviceNeeded = item.serviceNeeded
        serviceNotes = item.serviceNotes
        sensorCleaningIntervalDays = item.sensorCleaningIntervalDays
        lastSensorCleaningDate = item.lastSensorCleaningDate
        reminderHour = item.reminderHour
        reminderMinute = item.reminderMinute
        mount = item.mount
        sensorFormatID = item.sensorFormatID
        resolutionWidthPx = item.resolutionWidthPx
        resolutionHeightPx = item.resolutionHeightPx
        focalLengthMin = item.focalLengthMin
        focalLengthMax = item.focalLengthMax
        maxApertureWide = item.maxApertureWide
        maxApertureTele = item.maxApertureTele
        minFocusDistance = item.minFocusDistance
        filterThread = item.filterThread
        filterStops = item.filterStops
        guideNumber = item.guideNumber
        firmwareVersion = item.firmwareVersion
        ratedShutterLife = item.ratedShutterLife
        chargeCycles = item.chargeCycles
        ratedChargeCycles = item.ratedChargeCycles
        capacityGB = item.capacityGB
        cardType = item.cardType
        speedRating = item.speedRating
        referenceLinks = item.referenceLinks
        photos = includePhotos ? item.photos?.map(GearPhotoDTO.init(from:)) : nil
    }

    var displayName: String {
        let name = [make, model].compactMap { $0?.nonEmptyOrNil }.joined(separator: " ")
        return name.isEmpty ? GearCategory(storedID: category).displayName : name
    }

    /// A new, unmanaged `GearItem` with this DTO's values and photos. The caller inserts it.
    func toGearItem() -> GearItem {
        let item = GearItem(dateAdded: dateAdded)
        item.id = id
        applyFields(to: item)
        item.dateModified = dateModified ?? dateAdded
        if let photos {
            item.photos = photos.map { $0.toGearPhoto() }
        }
        return item
    }

    /// Writes every editable field to `item`: everything except its identity, `dateAdded`,
    /// `dateModified` and relationships. The single field list for import, editing and rollback,
    /// so a new field can't be missed by one of them. Money goes through `Double`; callers that
    /// copy between live items set the exact `Decimal`s afterwards (see `copyEditableFields`).
    func applyFields(to item: GearItem) {
        // Kept as text, so a category from a newer version survives the round trip.
        item.category = category
        item.make = make
        item.model = model
        item.serialNumber = serialNumber
        item.manufacturingYear = manufacturingYear
        item.upcCode = upcCode
        item.notes = notes
        item.purchaseDate = purchaseDate
        item.purchasePrice = purchasePrice.map { Decimal(roundTripping: $0) }
        item.currentValue = currentValue.map { Decimal(roundTripping: $0) }
        item.serviceNeeded = serviceNeeded ?? false
        item.serviceNotes = serviceNotes
        item.sensorCleaningIntervalDays = max(0, sensorCleaningIntervalDays ?? 0)
        item.lastSensorCleaningDate = lastSensorCleaningDate
        // Validation bounds only magnitudes; notification scheduling needs a real clock time.
        item.reminderHour = min(max(reminderHour ?? Constants.Maintenance.defaultReminderHour, 0), 23)
        item.reminderMinute = min(max(reminderMinute ?? 0, 0), 59)
        item.mount = mount ?? ""
        item.sensorFormatID = sensorFormatID ?? ""
        item.resolutionWidthPx = resolutionWidthPx ?? 0
        item.resolutionHeightPx = resolutionHeightPx ?? 0
        item.focalLengthMin = focalLengthMin ?? 0
        item.focalLengthMax = focalLengthMax ?? 0
        item.maxApertureWide = maxApertureWide ?? 0
        item.maxApertureTele = maxApertureTele ?? 0
        item.minFocusDistance = minFocusDistance ?? 0
        item.filterThread = filterThread ?? 0
        item.filterStops = filterStops ?? 0
        item.guideNumber = guideNumber ?? 0
        item.firmwareVersion = firmwareVersion ?? ""
        item.ratedShutterLife = ratedShutterLife ?? 0
        item.chargeCycles = chargeCycles ?? 0
        item.ratedChargeCycles = ratedChargeCycles ?? 0
        item.capacityGB = capacityGB ?? 0
        item.cardType = cardType ?? ""
        item.speedRating = speedRating ?? ""
        item.referenceLinks = referenceLinks ?? ""
    }
}

extension GearItem {
    /// Copies every editable field from `other` (see `GearItemDTO.applyFields`), with the
    /// money fields copied exactly: `Decimal → Double → Decimal` isn't exact for every amount
    /// (0.07 comes back as 0.0699…), so going through the DTO alone would drift stored prices
    /// on every edit.
    func copyEditableFields(from other: GearItem) {
        GearItemDTO(from: other, includePhotos: false).applyFields(to: self)
        purchasePrice = other.purchasePrice
        currentValue = other.currentValue
    }

    /// An unmanaged copy of `item`'s editable fields, for an editor's draft or a rollback
    /// snapshot. It has no photos or child records, and is never inserted.
    static func detachedCopy(of item: GearItem) -> GearItem {
        let copy = GearItem(dateAdded: item.dateAdded)
        copy.id = item.id
        copy.copyEditableFields(from: item)
        copy.dateModified = item.dateModified
        return copy
    }
}

// MARK: - Child records

struct MaintenanceRecordDTO: Codable {
    let id: UUID
    let gearItemID: UUID?
    let type: String
    let date: Date
    var cost: Double?
    let notes: String?
    let performedBy: String?
    let nextDueDate: Date?
    let photoData: Data?
    let isCompleted: Bool

    init(from record: MaintenanceRecord, includePhotos: Bool = true) {
        id = record.id
        gearItemID = record.gearItem?.id
        type = record.typeID
        date = record.date
        cost = record.cost?.doubleValue
        notes = record.notes
        performedBy = record.performedBy
        nextDueDate = record.nextDueDate
        photoData = includePhotos ? record.photoData : nil
        isCompleted = record.isCompleted
    }

    func toMaintenanceRecord(gearByID: [UUID: GearItem]) -> MaintenanceRecord {
        let record = MaintenanceRecord(gearItem: gearItemID.flatMap { gearByID[$0] }, type: .other, date: date,
                                       cost: cost.map { Decimal(roundTripping: $0) }, notes: notes,
                                       performedBy: performedBy, nextDueDate: nextDueDate,
                                       photoData: photoData, isCompleted: isCompleted)
        record.id = id
        record.typeID = type
        return record
    }
}

struct MaintenanceReminderDTO: Codable {
    let id: UUID
    let gearItemID: UUID?
    let type: String
    let dueDate: Date
    let isActive: Bool
    let recurringInterval: Int?
    let lastNotified: Date?
    let notes: String?

    init(from reminder: MaintenanceReminder) {
        id = reminder.id
        gearItemID = reminder.gearItem?.id
        type = reminder.typeID
        dueDate = reminder.dueDate
        isActive = reminder.isActive
        recurringInterval = reminder.recurringInterval
        lastNotified = reminder.lastNotified
        notes = reminder.notes
    }

    func toMaintenanceReminder(gearByID: [UUID: GearItem]) -> MaintenanceReminder {
        let reminder = MaintenanceReminder(gearItem: gearItemID.flatMap { gearByID[$0] }, type: .other,
                                           dueDate: dueDate, isActive: isActive,
                                           recurringInterval: recurringInterval, notes: notes)
        reminder.id = id
        reminder.typeID = type
        reminder.lastNotified = lastNotified
        return reminder
    }
}

struct ShutterCountReadingDTO: Codable {
    let id: UUID
    let gearItemID: UUID?
    let date: Date
    let count: Int
    let source: String
    let note: String?

    init(from reading: ShutterCountReading) {
        id = reading.id
        gearItemID = reading.gearItem?.id
        date = reading.date
        count = reading.count
        source = reading.sourceID
        note = reading.note
    }

    func toReading(gearByID: [UUID: GearItem]) -> ShutterCountReading {
        let reading = ShutterCountReading(gearItem: gearItemID.flatMap { gearByID[$0] }, date: date,
                                          count: count, note: note ?? "")
        reading.id = id
        reading.sourceID = source
        return reading
    }
}

struct GearLoanDTO: Codable {
    let id: UUID
    let gearItemID: UUID?
    let direction: String
    let person: String
    let contact: String?
    let outDate: Date
    let dueDate: Date?
    let returnedDate: Date?
    let notes: String?

    init(from loan: GearLoan) {
        id = loan.id
        gearItemID = loan.gearItem?.id
        direction = loan.directionID
        person = loan.person
        contact = loan.contact
        outDate = loan.outDate
        dueDate = loan.dueDate
        returnedDate = loan.returnedDate
        notes = loan.notes
    }

    func toLoan(gearByID: [UUID: GearItem]) -> GearLoan {
        let loan = GearLoan(gearItem: gearItemID.flatMap { gearByID[$0] }, person: person,
                            contact: contact ?? "", outDate: outDate, dueDate: dueDate, notes: notes ?? "")
        loan.id = id
        loan.directionID = direction
        loan.returnedDate = returnedDate
        return loan
    }
}

// MARK: - Development recipes

/// A recipe with its steps nested: steps belong to exactly one recipe and never move.
struct DevelopmentRecipeDTO: Codable {
    let id: UUID
    let name: String
    let filmStockID: String?
    let developer: String?
    let dilution: String?
    var temperatureCelsius: Double?
    let notes: String?
    let dateCreated: Date
    let dateModified: Date?
    let steps: [DevelopmentStepDTO]

    init(from recipe: DevelopmentRecipe) {
        id = recipe.id
        name = recipe.name
        filmStockID = recipe.filmStockID
        developer = recipe.developer
        dilution = recipe.dilution
        temperatureCelsius = recipe.temperatureCelsius
        notes = recipe.notes
        dateCreated = recipe.dateCreated
        dateModified = recipe.dateModified
        steps = recipe.orderedSteps.map(DevelopmentStepDTO.init(from:))
    }

    /// The recipe and its steps, not yet inserted anywhere.
    func toRecipe() -> (recipe: DevelopmentRecipe, steps: [DevelopmentStep]) {
        let recipe = DevelopmentRecipe(name: name, filmStockID: filmStockID ?? "", developer: developer ?? "",
                                       dilution: dilution ?? "", temperatureCelsius: temperatureCelsius ?? 20,
                                       notes: notes ?? "")
        recipe.id = id
        recipe.dateCreated = dateCreated
        recipe.dateModified = dateModified ?? dateCreated
        return (recipe, steps.map { $0.toStep(recipe: recipe) })
    }
}

struct DevelopmentStepDTO: Codable {
    let id: UUID
    let name: String
    let order: Int
    let durationSeconds: Int
    let agitationInitialSeconds: Int?
    let agitationIntervalSeconds: Int?
    let agitationDurationSeconds: Int?
    let notes: String?

    init(from step: DevelopmentStep) {
        id = step.id
        name = step.name
        order = step.order
        durationSeconds = step.durationSeconds
        agitationInitialSeconds = step.agitationInitialSeconds
        agitationIntervalSeconds = step.agitationIntervalSeconds
        agitationDurationSeconds = step.agitationDurationSeconds
        notes = step.notes
    }

    func toStep(recipe: DevelopmentRecipe) -> DevelopmentStep {
        let step = DevelopmentStep(recipe: recipe, name: name, order: order, durationSeconds: durationSeconds,
                                   notes: notes ?? "")
        step.id = id
        step.agitationInitialSeconds = agitationInitialSeconds ?? 0
        step.agitationIntervalSeconds = agitationIntervalSeconds ?? 0
        step.agitationDurationSeconds = agitationDurationSeconds ?? 0
        return step
    }
}

// MARK: - Unrestorable numbers

extension LibraryExport {
    /// Replaces every `Double` the restore path would reject — NaN, ±∞, or a magnitude past the
    /// `Constants.DataLimits` bound `ImportDocument.validate()` applies to that field — with the
    /// field's default (nil, or 0 for "not set"). Returns how many it replaced.
    ///
    /// `JSONEncoder` refuses NaN/±∞ and backup verification rejects anything `validate()` would,
    /// so one such value in the store would otherwise make every backup fail. Validation stays
    /// strict because it protects the app from untrusted files; export writes only what it can
    /// read back. Keep the two in step when adding a `Double` field.
    mutating func replaceUnrestorableNumbers() -> Int {
        typealias Limits = Constants.DataLimits
        var replaced = 0
        func restorable(_ value: inout Double?, limit: Double) {
            guard let number = value, !number.isFinite || abs(number) > limit else { return }
            value = nil
            replaced += 1
        }
        for i in gearItems.indices {
            restorable(&gearItems[i].purchasePrice, limit: Limits.maximumMoney)
            restorable(&gearItems[i].currentValue, limit: Limits.maximumMoney)
            restorable(&gearItems[i].focalLengthMin, limit: Limits.maximumMeasurement)
            restorable(&gearItems[i].focalLengthMax, limit: Limits.maximumMeasurement)
            restorable(&gearItems[i].maxApertureWide, limit: Limits.maximumMeasurement)
            restorable(&gearItems[i].maxApertureTele, limit: Limits.maximumMeasurement)
            restorable(&gearItems[i].minFocusDistance, limit: Limits.maximumMeasurement)
            restorable(&gearItems[i].filterThread, limit: Limits.maximumMeasurement)
            restorable(&gearItems[i].filterStops, limit: Limits.maximumMeasurement)
            restorable(&gearItems[i].guideNumber, limit: Limits.maximumMeasurement)
            restorable(&gearItems[i].capacityGB, limit: Limits.maximumMeasurement)
        }
        for i in maintenanceRecords.indices {
            restorable(&maintenanceRecords[i].cost, limit: Limits.maximumMoney)
        }
        if var recipes = developmentRecipes {
            for i in recipes.indices {
                restorable(&recipes[i].temperatureCelsius, limit: Limits.maximumMeasurement)
            }
            developmentRecipes = recipes
        }
        return replaced
    }
}
