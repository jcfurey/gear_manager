//
//  NotificationManager.swift
//  ShutterManager
//
//  Local notifications for gear reminders: sensor cleaning due, and loans due back.
//

import Foundation
import UserNotifications
import os

/// Schedules and reconciles gear reminders.
///
/// Every reminder is derived from the library (an item's next sensor-cleaning date, a loan's due
/// date) and fires at that item's reminder time. `refreshGearReminders(for:)` reconciles the
/// whole set after anything that can change it from outside the editors: launch, foreground,
/// import, restore and CloudKit changes from other devices.
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "NotificationManager")

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// The Settings toggle for gear reminders.
    @Published var gearRemindersEnabled = false

    private let authorizationProvider: () async -> UNAuthorizationStatus
    private let requestAuthorizationHandler: () async throws -> Bool
    private let deliverRequest: (UNNotificationRequest) async throws -> Void
    private let pendingRequests: () async -> [UNNotificationRequest]
    private let removeRequests: ([String]) -> Void
    private let defaults: UserDefaults
    private var queueTail: Task<Void, Never>?

    init(defaults: UserDefaults = .standard,
         authorizationProvider: (() async -> UNAuthorizationStatus)? = nil,
         requestAuthorization: (() async throws -> Bool)? = nil,
         deliverRequest: ((UNNotificationRequest) async throws -> Void)? = nil,
         pendingRequests: (() async -> [UNNotificationRequest])? = nil,
         removeRequests: (([String]) -> Void)? = nil) {
        self.defaults = defaults
        self.authorizationProvider = authorizationProvider ?? {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
        self.requestAuthorizationHandler = requestAuthorization ?? {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        self.deliverRequest = deliverRequest ?? { try await UNUserNotificationCenter.current().add($0) }
        self.pendingRequests = pendingRequests ?? { await UNUserNotificationCenter.current().pendingNotificationRequests() }
        self.removeRequests = removeRequests ?? { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: $0) }
        reloadPreferences()
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            authorizationStatus = try await requestAuthorizationHandler() ? .authorized : .denied
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            authorizationStatus = .denied
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await authorizationProvider()
    }

    private var canDeliver: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: - Preferences

    func updateGearRemindersEnabled(_ enabled: Bool) {
        gearRemindersEnabled = enabled
        defaults.set(enabled, forKey: Constants.UserDefaultsKeys.gearRemindersEnabled)
        if !enabled { enqueue { [self] in await clearAllGearReminders() } }
    }

    private func reloadPreferences() {
        gearRemindersEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.gearRemindersEnabled)
    }

    // MARK: - Gear reminders

    /// One reminder, captured as values so scheduling never reads a model after an await.
    struct GearReminder: Equatable {
        static let sensorCleaningPrefix = "sensor_cleaning_"
        static let loanDuePrefix = "loan_due_"
        static let prefixes = [sensorCleaningPrefix, loanDuePrefix]

        let identifier: String
        let title: String
        let body: String
        /// The day it fires; nil means it shouldn't be scheduled (and any pending one is removed).
        let due: Date?
        let hour: Int
        let minute: Int

        /// Changes whenever anything shown or the fire time changes, so an edit reschedules.
        var revision: String {
            "\(due?.timeIntervalSince1970 ?? 0)|\(hour)|\(minute)|\(title)|\(body)"
        }

        /// The sensor-cleaning reminder and one reminder per loan for `item`.
        static func all(for item: GearItem) -> [GearReminder] {
            let name = item.displayName
            var reminders = [GearReminder(
                identifier: sensorCleaningPrefix + item.id.uuidString,
                title: "Sensor cleaning due",
                body: "\(name) is due for a sensor cleaning.",
                due: item.gearCategory.hasSensorCleaning ? item.nextSensorCleaningDate : nil,
                hour: item.reminderHour, minute: item.reminderMinute)]
            for loan in item.loans ?? [] {
                let who = loan.person.trimmingCharacters(in: .whitespacesAndNewlines)
                let body: String
                switch loan.direction {
                case .lentOut:
                    body = who.isEmpty ? "\(name) is due back today." : "\(name) is due back from \(who) today."
                case .rentedIn:
                    body = who.isEmpty ? "\(name) is due to be returned today." : "\(name) is due back to \(who) today."
                }
                reminders.append(GearReminder(
                    identifier: loanDuePrefix + loan.id.uuidString,
                    title: loan.direction == .lentOut ? "Gear due back" : "Rental due back",
                    body: body,
                    due: loan.isOpen ? loan.dueDate : nil,
                    hour: item.reminderHour, minute: item.reminderMinute))
            }
            return reminders
        }
    }

    /// Reschedules one item's reminders after it, or one of its loans, changed.
    func updateReminders(for item: GearItem) async {
        let reminders = GearReminder.all(for: item)
        await enqueue { [self] in
            reloadPreferences()
            await refreshAuthorizationStatus()
            let pending = await pendingRequests()
            for reminder in reminders {
                await update(reminder, pending: pending.first { $0.identifier == reminder.identifier })
            }
        }.value
    }

    /// Removes a deleted item's reminders.
    func cancelReminders(for item: GearItem) {
        let identifiers = GearReminder.all(for: item).map(\.identifier)
        enqueue { [self] in
            removeRequests(identifiers)
            var revisions = storedRevisions
            identifiers.forEach { revisions.removeValue(forKey: $0) }
            storedRevisions = revisions
        }
    }

    /// Reconciles every gear reminder with the library: schedules what's due, and removes
    /// reminders for deleted items, returned loans and changed preferences.
    func refreshGearReminders(for items: [GearItem]) async {
        let reminders = items.flatMap(GearReminder.all(for:))
        await enqueue { [self] in
            reloadPreferences()
            await refreshAuthorizationStatus()
            let pending = await pendingRequests()
            let wanted = Set(reminders.map(\.identifier))
            removeRequests(pending.map(\.identifier).filter { Self.isGearReminder($0) && !wanted.contains($0) })
            storedRevisions = storedRevisions.filter { wanted.contains($0.key) }
            for reminder in reminders {
                await update(reminder, pending: pending.first { $0.identifier == reminder.identifier })
            }
        }.value
    }

    private func update(_ reminder: GearReminder, pending: UNNotificationRequest?) async {
        var revisions = storedRevisions
        guard canDeliver, gearRemindersEnabled, let due = reminder.due else {
            removeRequests([reminder.identifier])
            revisions.removeValue(forKey: reminder.identifier)
            storedRevisions = revisions
            return
        }
        if pending?.content.userInfo["revision"] as? String == reminder.revision { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
        components.hour = reminder.hour
        components.minute = reminder.minute
        let fireDate = Calendar.current.date(from: components) ?? due
        // A delivered overdue reminder is not reissued on every foreground or sync.
        if pending == nil, fireDate <= Date(), revisions[reminder.identifier] == reminder.revision { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.badge = 1
        content.userInfo = ["revision": reminder.revision]
        let trigger: UNNotificationTrigger = fireDate.timeIntervalSinceNow > 60
            ? UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            : UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        do {
            try await deliverRequest(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
            revisions[reminder.identifier] = reminder.revision
            storedRevisions = revisions
        } catch {
            logger.error("Gear reminder could not be scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearAllGearReminders() async {
        let pending = await pendingRequests()
        removeRequests(pending.map(\.identifier).filter(Self.isGearReminder))
        defaults.removeObject(forKey: Constants.Notifications.gearReminderRevisionsKey)
    }

    private static func isGearReminder(_ identifier: String) -> Bool {
        GearReminder.prefixes.contains { identifier.hasPrefix($0) }
    }

    private var storedRevisions: [String: String] {
        get { defaults.dictionary(forKey: Constants.Notifications.gearReminderRevisionsKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Constants.Notifications.gearReminderRevisionsKey) }
    }

    /// Runs reminder operations one at a time, in order: a cancel queued during an add runs
    /// after the add completes.
    @discardableResult
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = queueTail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        queueTail = task
        return task
    }

    // MARK: - Timer alerts

    /// A one-off alert for a running timer: a long exposure ending, or a development step's
    /// agitation and end. Timer alerts are never gear reminders, so refreshing reminders leaves
    /// them alone, and they don't depend on the Gear Reminders setting.
    struct TimerAlert: Equatable {
        let date: Date
        let title: String
        let body: String
    }

    static let timerPrefix = "timer_"
    /// iOS keeps at most 64 pending notifications per app; leave room for gear reminders.
    static let maximumTimerAlerts = 40

    /// Replaces `group`'s pending alerts with `alerts` (past ones are skipped). Asks for
    /// permission the first time a timer runs.
    func scheduleTimerAlerts(_ alerts: [TimerAlert], group: String) {
        enqueue { [self] in
            await removeTimerAlerts(group: group)
            if authorizationStatus == .notDetermined {
                await requestAuthorization()
            } else {
                await refreshAuthorizationStatus()
            }
            guard canDeliver else { return }
            let upcoming = alerts.filter { $0.date.timeIntervalSinceNow > 0.5 }.sorted { $0.date < $1.date }
            for (index, alert) in upcoming.prefix(Self.maximumTimerAlerts).enumerated() {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(alert.date.timeIntervalSinceNow, 1),
                                                                repeats: false)
                do {
                    try await deliverRequest(UNNotificationRequest(identifier: Self.timerIdentifier(group, index),
                                                                   content: content, trigger: trigger))
                } catch {
                    logger.error("Timer alert could not be scheduled: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func cancelTimerAlerts(group: String) {
        enqueue { [self] in await removeTimerAlerts(group: group) }
    }

    /// Waits until every queued schedule or cancel has run (for tests).
    func waitForPendingWork() async {
        await queueTail?.value
    }

    private static func timerIdentifier(_ group: String, _ index: Int) -> String {
        "\(timerPrefix)\(group)_\(index)"
    }

    private func removeTimerAlerts(group: String) async {
        let prefix = "\(Self.timerPrefix)\(group)_"
        let pending = await pendingRequests()
        removeRequests(pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }

    // MARK: - Badge

    /// Clears the app icon badge; called whenever the app becomes active.
    func clearBadge() {
        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(0)
            } catch {
                logger.error("Failed to clear badge count: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Foreground presentation

/// Presents notifications while the app is in the foreground; without a delegate, iOS discards
/// them. Installed once at launch; the static `shared` keeps it alive since the center's
/// `delegate` is weak.
final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresentationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}
