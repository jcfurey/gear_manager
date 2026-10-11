//
//  MaintenanceService.swift
//  ShutterManager
//
//  Logs maintenance and completes reminders, saving history and due dates together.
//

import Foundation
import SwiftData

/// A completed maintenance event updates history and due-date state in the same save.
@MainActor
enum MaintenanceService {
    @discardableResult
    static func log(for item: GearItem, type: MaintenanceType, date: Date,
                    cost: Decimal? = nil, notes: String? = nil, performedBy: String? = nil,
                    reminderInterval: Int? = nil, reminderNotes: String? = nil, context: ModelContext,
                    saveChanges: (ModelContext) throws -> Void = { try $0.save() }) throws -> MaintenanceRecord {
        try context.save()
        let relationships = GearRelationshipSnapshot(item)
        let previousCleaningDate = item.lastSensorCleaningDate
        let previousModifiedDate = item.dateModified
        let previousReminders = (item.maintenanceReminders ?? []).map { ($0, $0.isActive, $0.dueDate) }
        let nextDue = reminderInterval.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: date) }
        let record = MaintenanceRecord(type: type, date: date, cost: cost, notes: notes,
            performedBy: performedBy, nextDueDate: nextDue)
        do {
            record.gearItem = item
            context.insert(record)
            let pending = (item.maintenanceReminders ?? []).filter { $0.type == type && $0.isActive }
            if let nextDue, let reminderInterval {
                // A new cycle was asked for: it replaces this type's reminders, keeping their notes.
                let carriedNotes = reminderNotes ?? pending.lazy.compactMap(\.notes).first
                for reminder in pending { reminder.isActive = false }
                context.insert(MaintenanceReminder(gearItem: item, type: type, dueDate: nextDue,
                    recurringInterval: reminderInterval, notes: carriedNotes))
            } else {
                // The work is done: one-shot reminders are complete, and recurring ones restart
                // their cycle from it rather than ending. Never earlier than already scheduled: a
                // backdated record mustn't make one overdue.
                for reminder in pending {
                    if let interval = reminder.recurringInterval, interval > 0,
                       let next = Calendar.current.date(byAdding: .day, value: interval, to: date) {
                        reminder.dueDate = max(reminder.dueDate, next)
                    } else {
                        reminder.isActive = false
                    }
                }
            }
            if type == .sensorCleaning {
                item.lastSensorCleaningDate = max(item.lastSensorCleaningDate ?? .distantPast, date)
            }
            item.markModified()
            try saveChanges(context)
            return record
        } catch {
            relationships.restore()
            context.rollback()
            relationships.restore()
            // Restore observable values too: an in-memory SwiftData store can retain them after rollback.
            item.lastSensorCleaningDate = previousCleaningDate
            item.dateModified = previousModifiedDate
            for (reminder, active, due) in previousReminders {
                reminder.isActive = active
                reminder.dueDate = due
            }
            throw error
        }
    }

    /// Marks a reminder as done (Maintenance screen → swipe "Done") and saves.
    ///
    /// - `.sensorCleaning`: logs a cleaning dated `date` through `log` — exactly as if the user
    ///   had added a sensor-cleaning record — so history, `lastSensorCleaningDate` and the
    ///   recurring reminder commit in one save. A recurring reminder is replaced by the next
    ///   cycle counted from `date` (carrying its interval and notes); a one-shot one is
    ///   deactivated. Returns the new record; the caller reschedules the item's reminders.
    /// - Other types: a recurring reminder rolls forward to its next occurrence (counted from
    ///   `date` when completed ahead of schedule); a one-shot reminder deactivates. Returns nil.
    ///
    /// Throws, with every change undone, when the save fails.
    @discardableResult
    static func complete(_ reminder: MaintenanceReminder, for item: GearItem, on date: Date = Date(),
                         context: ModelContext,
                         saveChanges: (ModelContext) throws -> Void = { try $0.save() }) throws -> MaintenanceRecord? {
        let interval = reminder.recurringInterval.flatMap { $0 > 0 ? $0 : nil }
        if reminder.type == .sensorCleaning {
            return try log(for: item, type: .sensorCleaning, date: date, reminderInterval: interval,
                           reminderNotes: reminder.notes, context: context, saveChanges: saveChanges)
        }

        try context.save()
        let previousDueDate = reminder.dueDate
        let previousActive = reminder.isActive
        if let interval {
            if reminder.dueDate <= date {
                reminder.updateForNextOccurrence(now: date)
            } else {
                // Completed ahead of schedule — the work was just done, so the next cycle
                // starts now rather than at the old anchor.
                reminder.dueDate = Calendar.current.date(byAdding: .day, value: interval, to: date) ?? reminder.dueDate
            }
        } else {
            reminder.isActive = false
        }
        do {
            try saveChanges(context)
            return nil
        } catch {
            context.rollback()
            reminder.dueDate = previousDueDate
            reminder.isActive = previousActive
            throw error
        }
    }
}
