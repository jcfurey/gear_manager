//
//  GearItem.swift
//  ShutterManager
//
//  One piece of gear in the inventory.
//

import SwiftData
import Foundation

/// A piece of photography gear: a body, lens, flash, tripod, filter, drone, battery, card…
///
/// Mirrored to the user's private CloudKit database, so every attribute has a default and every
/// relationship is optional (see `AppSchema`). Category-specific details are flat fields that
/// read as "not set" at `0` or `""`; `GearCategory` says which apply to which kind of gear.
@Model
final class GearItem {
    /// Not a `.unique` constraint: CloudKit mirroring forbids unique attributes, and import
    /// de-duplicates by id explicitly.
    var id: UUID = UUID()

    /// When the item was added. Drives the default newest-first ordering.
    var dateAdded: Date = Date()

    /// When the item was last edited. Stamped on Done in the detail editor.
    var dateModified: Date = Date()

    /// A `GearCategory` raw value. Stored as text so a category added in a later version reads
    /// as `.other` here instead of failing to decode; see `gearCategory`.
    var category: String = "other"

    var make: String?
    var model: String?
    var serialNumber: String?
    /// Year the item was made, when known.
    var manufacturingYear: Int? = nil
    /// Universal Product Code from a barcode scan.
    var upcCode: String?
    var notes: String?

    // MARK: Value

    var purchaseDate: Date?
    var purchasePrice: Decimal?
    /// What the user thinks it's worth now, if they've said.
    var currentValue: Decimal?

    // MARK: Service

    var serviceNeeded: Bool = false
    var serviceNotes: String?

    /// Days between sensor cleanings. `0` means not tracked.
    var sensorCleaningIntervalDays: Int = 0
    /// When the sensor was last cleaned: the anchor for the next-due date. Saved together with
    /// the maintenance record that logs the cleaning (`MaintenanceService`).
    var lastSensorCleaningDate: Date?
    /// Time of day this item's reminders fire (sensor cleaning, loan due back).
    var reminderHour: Int = 10
    var reminderMinute: Int = 0

    // MARK: Camera details ("" or 0 = not set)

    /// The lens mount: a `LensMount` suggestion or any typed name.
    var mount: String = ""
    /// A `SensorFormat` ID: the body's sensor or film format, or the format a lens is made for.
    var sensorFormatID: String = ""
    /// Image size in pixels, for pixel pitch (the NPF rule) and megapixels.
    var resolutionWidthPx: Int = 0
    var resolutionHeightPx: Int = 0
    /// Focal length range in millimetres; equal for a prime.
    var focalLengthMin: Double = 0
    var focalLengthMax: Double = 0
    /// Maximum aperture (f-number) at the wide and long ends; equal for a constant aperture.
    var maxApertureWide: Double = 0
    var maxApertureTele: Double = 0
    /// Minimum focus distance in metres.
    var minFocusDistance: Double = 0
    /// Filter thread diameter in millimetres.
    var filterThread: Double = 0
    /// An ND filter's strength in stops.
    var filterStops: Double = 0
    /// A flash's guide number in metres at ISO 100.
    var guideNumber: Double = 0
    var firmwareVersion: String = ""
    /// The manufacturer's rated shutter life, in actuations.
    var ratedShutterLife: Int = 0
    /// Battery charge cycles so far, and the rated number.
    var chargeCycles: Int = 0
    var ratedChargeCycles: Int = 0
    /// Memory card capacity in GB, type (SD, CFexpress Type B…) and speed rating (V90, UHS-II…).
    var capacityGB: Double = 0
    var cardType: String = ""
    var speedRating: String = ""

    /// Reference links, one URL per line: manuals, reviews, forum threads.
    var referenceLinks: String = ""

    // MARK: Relationships
    // CloudKit mirroring requires every relationship to have an inverse; cascading deletes keep
    // a deleted item from leaving orphans behind.

    @Relationship(deleteRule: .cascade, inverse: \GearPhoto.gearItem)
    var photos: [GearPhoto]? = []

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceRecord.gearItem)
    var maintenanceRecords: [MaintenanceRecord]? = []

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceReminder.gearItem)
    var maintenanceReminders: [MaintenanceReminder]? = []

    @Relationship(deleteRule: .cascade, inverse: \ShutterCountReading.gearItem)
    var shutterCountReadings: [ShutterCountReading]? = []

    @Relationship(deleteRule: .cascade, inverse: \GearLoan.gearItem)
    var loans: [GearLoan]? = []

    /// Shoots this item is down for. Many-to-many; `Shoot.gear` declares the inverse.
    var shoots: [Shoot]? = []

    /// Kits this item is in. Many-to-many; `Kit.gear` declares the inverse.
    var kits: [Kit]? = []

    /// Film rolls loaded in this camera. Deleting the camera keeps the rolls.
    @Relationship(deleteRule: .nullify, inverse: \FilmRoll.camera)
    var filmRolls: [FilmRoll]? = []

    init(category: GearCategory = .other,
         dateAdded: Date = Date(),
         make: String? = nil,
         model: String? = nil,
         serialNumber: String? = nil,
         purchaseDate: Date? = nil,
         purchasePrice: Decimal? = nil,
         currentValue: Decimal? = nil,
         notes: String? = nil) {
        self.category = category.rawValue
        self.dateAdded = dateAdded
        self.dateModified = dateAdded
        self.make = make
        self.model = model
        self.serialNumber = serialNumber
        self.purchaseDate = purchaseDate
        self.purchasePrice = purchasePrice
        self.currentValue = currentValue
        self.notes = notes
    }
}

// MARK: - Identity and photos

extension GearItem {
    var gearCategory: GearCategory {
        get { GearCategory(storedID: category) }
        set { category = newValue.rawValue }
    }

    /// "Nikon Z6 III", from whichever of make and model is set; the category name when neither is.
    var displayName: String {
        let components = [make, model].compactMap { $0?.nonEmptyOrNil }
        return components.isEmpty ? gearCategory.displayName : components.joined(separator: " ")
    }

    /// The cover photo's data: the primary photo, else the first by order.
    var primaryPhotoData: Data? {
        let photos = photos ?? []
        return (photos.first(where: \.isPrimary) ?? photos.min(by: { $0.order < $1.order }))?.imageData
    }

    var totalPhotoCount: Int { photos?.count ?? 0 }

    /// Inserts a new gallery photo after the existing ones; the first photo becomes the cover.
    /// The caller saves.
    @discardableResult
    func appendGalleryPhoto(_ imageData: Data, in context: ModelContext) -> GearPhoto {
        let existing = photos ?? []
        let photo = GearPhoto(imageData: imageData, order: (existing.map(\.order).max() ?? -1) + 1,
                              isPrimary: existing.isEmpty)
        photo.gearItem = self
        context.insert(photo)
        return photo
    }

    /// Parsed, tappable reference links: one per line, a bare domain becomes https://, blank
    /// lines are skipped, and duplicates are dropped (the detail screen identifies rows by URL).
    var referenceLinkURLs: [URL] {
        var seen = Set<URL>()
        return referenceLinks
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { raw in URL(string: raw.contains("://") ? raw : "https://\(raw)") }
            .filter { seen.insert($0).inserted }
    }

    /// A make / model search string for the marketplace links. Empty when there's nothing
    /// identifying to search for, so the UI can hide them.
    var marketplaceSearchQuery: String {
        [make, model].compactMap { $0?.nonEmptyOrNil }.joined(separator: " ")
    }

    /// Stamp `dateModified` to now — call after committing edits.
    func markModified() { dateModified = Date() }
}

// MARK: - Camera details

extension GearItem {
    /// The stored format, or nil when unset or unknown to this version.
    var sensorFormat: SensorFormat? {
        sensorFormatID.isEmpty ? nil : SensorFormat(id: sensorFormatID)
    }

    var hasFocalLength: Bool { focalLengthMin > 0 || focalLengthMax > 0 }

    /// A prime when only one focal length is set or both match.
    var isPrimeLens: Bool {
        hasFocalLength && (focalLengthMax <= 0 || focalLengthMin <= 0 || focalLengthMin == focalLengthMax)
    }

    /// "50 mm" or "24–70 mm"; nil when unset.
    var focalLengthText: String? { Self.focalLengthText(min: focalLengthMin, max: focalLengthMax) }

    /// "f/1.8" or "f/3.5–5.6"; nil when unset.
    var maxApertureText: String? { Self.apertureText(wide: maxApertureWide, tele: maxApertureTele) }

    /// "50 mm" or "24–70 mm" from a range where 0 means unset; nil when neither is set.
    static func focalLengthText(min shortest: Double, max longest: Double) -> String? {
        guard shortest > 0 || longest > 0 else { return nil }
        let short = shortest > 0 ? shortest : longest
        let long = Swift.max(longest, short)
        return short == long ? "\(trimmed(short)) mm" : "\(trimmed(short))–\(trimmed(long)) mm"
    }

    /// "f/1.8" or "f/3.5–5.6" where 0 means unset; nil when neither is set.
    static func apertureText(wide: Double, tele: Double) -> String? {
        guard wide > 0 || tele > 0 else { return nil }
        let wideEnd = wide > 0 ? wide : tele
        let teleEnd = tele > 0 ? tele : wideEnd
        return wideEnd == teleEnd ? "f/\(trimmed(wideEnd))" : "f/\(trimmed(wideEnd))–\(trimmed(teleEnd))"
    }

    /// "24–70 mm f/2.8", for lens lists and pickers; nil when neither is set.
    var lensSummary: String? {
        let parts = [focalLengthText, maxApertureText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Megapixels from the stored resolution; nil when unset.
    var megapixels: Double? {
        guard resolutionWidthPx > 0, resolutionHeightPx > 0 else { return nil }
        return Double(resolutionWidthPx) * Double(resolutionHeightPx) / 1_000_000
    }

    /// Pixel pitch in micrometres, from the format's width and the horizontal resolution.
    var pixelPitchMicrons: Double? {
        guard let format = sensorFormat, resolutionWidthPx > 0 else { return nil }
        return format.width * 1000 / Double(max(resolutionWidthPx, resolutionHeightPx))
    }

    /// Up to two decimals, no trailing zeros, in the user's locale: "50", "2.8", "4,5".
    static func trimmed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

// MARK: - Shutter, sensor cleaning, batteries

extension GearItem {
    /// The most recent shutter-count reading (the larger count wins a same-day tie).
    var latestShutterReading: ShutterCountReading? {
        (shutterCountReadings ?? []).max { ($0.date, $0.count) < ($1.date, $1.count) }
    }

    /// Share of the rated shutter life used, from the latest reading; nil without both.
    var shutterLifeUsed: Double? {
        guard ratedShutterLife > 0, let latest = latestShutterReading else { return nil }
        return Double(latest.count) / Double(ratedShutterLife)
    }

    var isNearShutterLife: Bool {
        (shutterLifeUsed ?? 0) >= Constants.Shutter.nearEndOfLifeFraction
    }

    /// When the sensor is next due for cleaning, given an interval and a last-cleaned date.
    var nextSensorCleaningDate: Date? {
        guard sensorCleaningIntervalDays > 0, let last = lastSensorCleaningDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: sensorCleaningIntervalDays, to: last)
    }

    /// True when the next cleaning is due today or earlier. Compares calendar days, as the
    /// reminder and badges treat the due date as a whole day.
    var isSensorCleaningDue: Bool {
        guard let next = nextSensorCleaningDate else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: next) <= calendar.startOfDay(for: Date())
    }

    /// Share of the rated charge cycles used; nil without both.
    var chargeCyclesUsed: Double? {
        guard ratedChargeCycles > 0 else { return nil }
        return Double(chargeCycles) / Double(ratedChargeCycles)
    }
}

// MARK: - Loans

extension GearItem {
    /// The loan that hasn't been returned yet, if any (the most recent if data ever has two).
    var openLoan: GearLoan? {
        (loans ?? []).filter(\.isOpen).max { $0.outDate < $1.outDate }
    }

    var isOnLoan: Bool { openLoan != nil }

    var isLoanOverdue: Bool { openLoan?.isOverdue ?? false }
}

// MARK: - Value

extension GearItem {
    /// What the item is worth for totals and sorting: the current value if set, else the
    /// purchase price; nil when neither is.
    var effectiveValue: Decimal? { currentValue ?? purchasePrice }
}

extension Sequence where Element == GearItem {
    /// Sum of `effectiveValue` over the items; items with no value add nothing.
    var totalEffectiveValue: Decimal {
        reduce(Decimal.zero) { $0 + ($1.effectiveValue ?? .zero) }
    }
}

// MARK: - Sorting

/// User-selectable ordering for gear lists and pickers. `recentlyAdded` is the default.
enum GearSortOption: String, CaseIterable, Identifiable {
    case recentlyAdded = "Recently Added"
    case name = "Name"
    case category = "Category"
    case valueHighToLow = "Value (High to Low)"

    var id: String { rawValue }
}

extension Sequence where Element == GearItem {
    /// Gear ordered by the given option. Value resolves `effectiveValue` once per item.
    func gearSorted(by option: GearSortOption) -> [GearItem] {
        switch option {
        case .recentlyAdded:
            return sorted { $0.dateAdded > $1.dateAdded }
        case .name:
            return sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .category:
            return sorted {
                let first = $0.gearCategory.displayName, second = $1.gearCategory.displayName
                return first == second
                    ? $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    : first < second
            }
        case .valueHighToLow:
            return map { ($0, $0.effectiveValue ?? .zero) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
    }
}
