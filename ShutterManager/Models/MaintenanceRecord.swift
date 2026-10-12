//
//  MaintenanceRecord.swift
//  ShutterManager
//
//  Maintenance history and scheduled maintenance reminders.
//

import Foundation
import SwiftData

/// A record of maintenance done on a piece of gear.
@Model
final class MaintenanceRecord {
    var id: UUID = UUID()
    var gearItem: GearItem?
    /// A `MaintenanceType` raw value, stored as text so a type added in a later version reads as
    /// `.other` here instead of failing to decode; see `type`.
    var typeID: String = "other"
    var date: Date = Date()
    var cost: Decimal?
    var notes: String?
    /// The user, a technician, or a shop.
    var performedBy: String?
    var nextDueDate: Date?
    /// Before/after photo. Stored outside the SQLite store to keep it compact.
    @Attribute(.externalStorage) var photoData: Data?
    var isCompleted: Bool = true

    init(
        gearItem: GearItem? = nil,
        type: MaintenanceType,
        date: Date = Date(),
        cost: Decimal? = nil,
        notes: String? = nil,
        performedBy: String? = nil,
        nextDueDate: Date? = nil,
        photoData: Data? = nil,
        isCompleted: Bool = true
    ) {
        self.id = UUID()
        self.gearItem = gearItem
        self.typeID = type.rawValue
        self.date = date
        self.cost = cost
        self.notes = notes
        self.performedBy = performedBy
        self.nextDueDate = nextDueDate
        self.photoData = photoData
        self.isCompleted = isCompleted
    }

    var type: MaintenanceType {
        get { MaintenanceType(storedID: typeID) }
        set { typeID = newValue.rawValue }
    }

    var isOverdue: Bool {
        guard let nextDue = nextDueDate else { return false }
        return nextDue < Date() && !isCompleted
    }

    /// Days until next maintenance is due (negative if overdue), in calendar days.
    var daysUntilDue: Int? {
        guard let nextDue = nextDueDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                       to: calendar.startOfDay(for: nextDue)).day
    }
}

/// Kinds of maintenance. The raw values are stored, synced and exported: **never rename or
/// remove one**; add new cases freely (older versions read them as `.other`).
enum MaintenanceType: String, CaseIterable, Codable, Identifiable {
    case sensorCleaning
    case cleaning
    case firmwareUpdate
    case calibration
    case cla
    case shutterReplacement
    case repair
    case inspection
    case other

    var id: String { rawValue }

    init(storedID: String) {
        self = MaintenanceType(rawValue: storedID) ?? .other
    }

    var displayName: String {
        switch self {
        case .sensorCleaning: return "Sensor Cleaning"
        case .cleaning: return "Cleaning"
        case .firmwareUpdate: return "Firmware Update"
        case .calibration: return "Calibration"
        case .cla: return "Clean, Lube & Adjust"
        case .shutterReplacement: return "Shutter Replacement"
        case .repair: return "Repair"
        case .inspection: return "Inspection"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .sensorCleaning: return "sparkles"
        case .cleaning: return "bubbles.and.sparkles"
        case .firmwareUpdate: return "arrow.down.circle"
        case .calibration: return "scope"
        case .cla: return "gearshape.2"
        case .shutterReplacement: return "camera.shutter.button"
        case .repair: return "wrench.and.screwdriver"
        case .inspection: return "magnifyingglass"
        case .other: return "ellipsis.circle"
        }
    }

    var category: MaintenanceCategory {
        switch self {
        case .sensorCleaning, .cleaning, .firmwareUpdate: return .routine
        case .calibration, .cla: return .service
        case .shutterReplacement, .repair: return .repair
        case .inspection, .other: return .other
        }
    }

    /// Suggested days between occurrences, for the reminder picker's default.
    var recommendedFrequency: Int? {
        switch self {
        case .sensorCleaning: return 180
        case .cleaning: return 90
        case .inspection: return 365
        default: return nil
        }
    }
}

enum MaintenanceCategory: String, CaseIterable, Codable {
    case routine = "Routine"
    case service = "Service"
    case repair = "Repair"
    case other = "Other"

    var color: String {
        switch self {
        case .routine: return "blue"
        case .service: return "purple"
        case .repair: return "red"
        case .other: return "gray"
        }
    }
}

/// A scheduled maintenance reminder.
@Model
final class MaintenanceReminder {
    var id: UUID = UUID()
    var gearItem: GearItem?
    /// A `MaintenanceType` raw value; see `MaintenanceRecord.typeID`.
    var typeID: String = "other"
    var dueDate: Date = Date()
    var isActive: Bool = true
    /// Days between occurrences; nil for a one-shot reminder.
    var recurringInterval: Int?
    var lastNotified: Date?
    var notes: String?

    init(
        gearItem: GearItem? = nil,
        type: MaintenanceType,
        dueDate: Date,
        isActive: Bool = true,
        recurringInterval: Int? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.gearItem = gearItem
        self.typeID = type.rawValue
        self.dueDate = dueDate
        self.isActive = isActive
        self.recurringInterval = recurringInterval
        self.notes = notes
    }

    var type: MaintenanceType {
        get { MaintenanceType(storedID: typeID) }
        set { typeID = newValue.rawValue }
    }

    /// Days until due (negative if overdue), in calendar days.
    var daysUntilDue: Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                       to: calendar.startOfDay(for: dueDate)).day ?? 0
    }

    var isOverdue: Bool { daysUntilDue < 0 }

    /// Moves a recurring reminder that's due to its next occurrence after `now` on its own
    /// schedule (due date + a whole number of intervals). No-op for one-shot reminders and for
    /// reminders not yet due.
    func updateForNextOccurrence(now: Date = Date(), calendar: Calendar = .current) {
        guard let interval = recurringInterval, interval > 0, dueDate <= now else { return }
        dueDate = Self.nextOccurrence(after: dueDate, intervalDays: interval, now: now, calendar: calendar)
    }

    /// The smallest `dueDate + k × intervalDays` (k ≥ 1, in calendar days) later than `now`.
    ///
    /// Computed arithmetically rather than stepping one interval at a time, so a reminder with
    /// an ancient due date and a 1-day interval doesn't loop once per elapsed day. The
    /// correction loops only absorb daylight-saving edge cases.
    static func nextOccurrence(after dueDate: Date, intervalDays interval: Int, now: Date,
                               calendar: Calendar = .current) -> Date {
        guard interval > 0, dueDate <= now else { return dueDate }
        func occurrence(_ k: Int) -> Date {
            let (days, overflow) = k.multipliedReportingOverflow(by: interval)
            guard !overflow else { return .distantFuture }
            return calendar.date(byAdding: .day, value: days, to: dueDate)
                ?? min(dueDate.addingTimeInterval(Double(days) * 86_400), .distantFuture)
        }
        let elapsedDays = max(0, calendar.dateComponents([.day], from: dueDate, to: now).day ?? 0)
        var k = elapsedDays / interval + 1
        while occurrence(k) <= now { k += 1 }
        while k > 1, occurrence(k - 1) > now { k -= 1 }
        return occurrence(k)
    }
}

// MARK: - Collections

extension Array where Element == MaintenanceRecord {
    var totalCost: Decimal {
        compactMap(\.cost).reduce(0, +)
    }

    func records(for category: MaintenanceCategory) -> [MaintenanceRecord] {
        filter { $0.type.category == category }
    }

    func recent(days: Int) -> [MaintenanceRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return filter { $0.date >= cutoff }
    }

    var overdue: [MaintenanceRecord] { filter(\.isOverdue) }

    func lastMaintenance(ofType type: MaintenanceType) -> MaintenanceRecord? {
        filter { $0.type == type && $0.isCompleted }.max { $0.date < $1.date }
    }
}
