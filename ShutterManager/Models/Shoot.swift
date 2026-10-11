//
//  Shoot.swift
//  ShutterManager
//
//  The shoot log: when and where, for whom, the gear taken and the shots to get.
//

import Foundation
import SwiftData

/// A planned or past shoot.
///
/// The place is copied in (name, coordinates and time zone) rather than linked to a `SavedPlace`,
/// so deleting or renaming a saved place never changes a shoot.
@Model
final class Shoot {
    var id: UUID = UUID()
    var title: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    /// A `ShootType` raw value, stored as text (see `type`).
    var typeID: String = "other"
    var client: String = ""
    var notes: String = ""
    var placeName: String = ""
    /// Degrees, north positive; nil when the shoot has no place.
    var latitude: Double? = nil
    /// Degrees, east positive; nil when the shoot has no place.
    var longitude: Double? = nil
    /// An IANA identifier; "" means the device's time zone.
    var timeZoneIdentifier: String = ""
    /// The gear ticked off in the packing check: item IDs, one per line.
    var packedGearIDs: String = ""
    /// Minutes before golden hour to send a heads-up; 0 means none.
    var goldenHourAlertMinutes: Int = 0
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    /// The gear for this shoot. Many-to-many: `GearItem.shoots` is the other side, and deleting
    /// either end only unlinks them.
    @Relationship(inverse: \GearItem.shoots)
    var gear: [GearItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \ShotListItem.shoot)
    var shotList: [ShotListItem]? = []

    /// Film rolls shot here. Deleting the shoot keeps the rolls.
    @Relationship(deleteRule: .nullify, inverse: \FilmRoll.shoot)
    var filmRolls: [FilmRoll]? = []

    init(title: String = "", startDate: Date = Date(), endDate: Date? = nil, type: ShootType = .other,
         client: String = "", notes: String = "") {
        self.id = UUID()
        self.title = title
        self.startDate = startDate
        self.endDate = max(endDate ?? startDate.addingTimeInterval(Constants.Shoots.defaultDuration), startDate)
        self.typeID = type.rawValue
        self.client = client
        self.notes = notes
        self.dateCreated = Date()
        self.dateModified = Date()
    }
}

extension Shoot {
    var type: ShootType {
        get { ShootType(storedID: typeID) }
        set { typeID = newValue.rawValue }
    }

    /// The title, or the type's name for an untitled shoot.
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil ?? type.displayName
    }

    /// The shoot's place, or nil when it has none (or its coordinates are off the globe).
    var place: PlaceValue? {
        get {
            guard let latitude, let longitude else { return nil }
            let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
            guard coordinate.isValid else { return nil }
            return PlaceValue(name: placeName, coordinate: coordinate, timeZoneIdentifier: timeZoneIdentifier)
        }
        set {
            placeName = newValue?.name ?? ""
            latitude = newValue?.coordinate.latitude
            longitude = newValue?.coordinate.longitude
            timeZoneIdentifier = newValue?.timeZoneIdentifier ?? ""
        }
    }

    /// The place's time zone, or the device's.
    var timeZone: TimeZone { place?.timeZone ?? .current }

    /// Start to end; an end before the start counts as the start.
    var interval: DateInterval { DateInterval(start: startDate, end: max(endDate, startDate)) }

    /// Still to come, or under way.
    func isUpcoming(at now: Date = Date()) -> Bool { endDate >= now }

    var orderedShotList: [ShotListItem] {
        (shotList ?? []).sorted { ($0.order, $0.title) < ($1.order, $1.title) }
    }

    var shotListProgress: (done: Int, total: Int) {
        let items = shotList ?? []
        return (items.filter(\.isDone).count, items.count)
    }

    /// The gear, grouped by category and then by name.
    var orderedGear: [GearItem] { (gear ?? []).gearSorted(by: .category) }

    // MARK: Packing

    /// The IDs ticked off in the packing check.
    var packedIDs: Set<UUID> {
        get { Set(packedGearIDs.split(whereSeparator: \.isNewline).compactMap { UUID(uuidString: String($0)) }) }
        set { packedGearIDs = newValue.map(\.uuidString).sorted().joined(separator: "\n") }
    }

    func isPacked(_ item: GearItem) -> Bool { packedIDs.contains(item.id) }

    func setPacked(_ packed: Bool, for item: GearItem) {
        var ids = packedIDs
        if packed { ids.insert(item.id) } else { ids.remove(item.id) }
        packedIDs = ids
    }

    /// Ticked-off items among the shoot's current gear (an item taken off the shoot stops
    /// counting).
    var packingProgress: (packed: Int, total: Int) {
        let gear = gear ?? []
        let packed = packedIDs
        return (gear.filter { packed.contains($0.id) }.count, gear.count)
    }

    func markModified() { dateModified = Date() }
}

/// One shot to get on a shoot. Items are copies, never links to a template, so editing a
/// template later leaves past shoots alone.
@Model
final class ShotListItem {
    var id: UUID = UUID()
    var shoot: Shoot?
    var title: String = ""
    var notes: String = ""
    var order: Int = 0
    var isDone: Bool = false

    init(shoot: Shoot? = nil, title: String = "", notes: String = "", order: Int = 0, isDone: Bool = false) {
        self.id = UUID()
        self.shoot = shoot
        self.title = title
        self.notes = notes
        self.order = order
        self.isDone = isDone
    }
}

/// What kind of shoot it is. Raw values are stored: never rename or remove one. An ID from a
/// newer version reads as `.other` and is kept as it is.
enum ShootType: String, CaseIterable, Identifiable, Sendable {
    case portrait, wedding, event, family, landscape, astro, street, travel, wildlife, sports
    case product, realEstate, commercial, video, personal, other

    var id: String { rawValue }

    init(storedID: String) {
        self = ShootType(rawValue: storedID) ?? .other
    }

    var displayName: String {
        switch self {
        case .portrait: return "Portrait"
        case .wedding: return "Wedding"
        case .event: return "Event"
        case .family: return "Family"
        case .landscape: return "Landscape"
        case .astro: return "Astro"
        case .street: return "Street"
        case .travel: return "Travel"
        case .wildlife: return "Wildlife"
        case .sports: return "Sports"
        case .product: return "Product"
        case .realEstate: return "Real estate"
        case .commercial: return "Commercial"
        case .video: return "Video"
        case .personal: return "Personal"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .portrait: return "person.crop.square"
        case .wedding: return "heart"
        case .event: return "party.popper"
        case .family: return "figure.2.and.child.holdinghands"
        case .landscape: return "mountain.2"
        case .astro: return "moon.stars"
        case .street: return "building.2"
        case .travel: return "airplane"
        case .wildlife: return "bird"
        case .sports: return "figure.run"
        case .product: return "shippingbox"
        case .realEstate: return "house"
        case .commercial: return "briefcase"
        case .video: return "video"
        case .personal: return "camera"
        case .other: return "camera.aperture"
        }
    }
}

// MARK: - Gear usage and readiness

extension GearItem {
    /// Shoots this item went on that have started; planned ones don't count as use yet.
    func pastShoots(at now: Date = Date()) -> [Shoot] {
        (shoots ?? []).filter { $0.startDate <= now }
    }

    /// The next shoot this item is down for, if any.
    func nextShoot(at now: Date = Date()) -> Shoot? {
        (shoots ?? []).filter { $0.startDate > now }.min { $0.startDate < $1.startDate }
    }

    /// When this item last went on a shoot.
    func lastUsed(at now: Date = Date()) -> Date? {
        pastShoots(at: now).map(\.startDate).max()
    }

    /// Why this item might not be ready for `shoot`: lent out, a rental due back before the shoot
    /// ends, or needing service or a sensor cleaning.
    func packingIssues(for shoot: Shoot) -> [String] {
        var issues: [String] = []
        if let loan = openLoan {
            let due = loan.dueDate.map { " (due back \($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""
            switch loan.direction {
            case .lentOut:
                issues.append(loan.summary + due)
            case .rentedIn:
                if let dueDate = loan.dueDate,
                   Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: shoot.endDate) {
                    issues.append("Rental due back \(dueDate.formatted(date: .abbreviated, time: .omitted)), before the shoot ends")
                }
            }
        }
        if serviceNeeded { issues.append("Needs service") }
        if isSensorCleaningDue { issues.append("Sensor cleaning due") }
        return issues
    }
}
