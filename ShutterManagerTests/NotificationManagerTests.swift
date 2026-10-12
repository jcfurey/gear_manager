//
//  NotificationManagerTests.swift
//  ShutterManagerTests
//
//  Gear reminders: which ones exist, when they fire, and that they reconcile with the library.
//

import Foundation
import SwiftData
import UserNotifications
import Testing
@testable import ShutterManager

@MainActor
struct NotificationManagerTests {
    /// Records what the manager asks the notification center to do.
    @MainActor
    final class FakeCenter {
        var pending: [UNNotificationRequest] = []
        var status: UNAuthorizationStatus = .authorized
        /// What the permission prompt answers.
        var grantsPermission = true
        var permissionRequests = 0

        func make(defaults: UserDefaults) -> NotificationManager {
            NotificationManager(
                defaults: defaults,
                authorizationProvider: { [unowned self] in self.status },
                requestAuthorization: { [unowned self] in
                    self.permissionRequests += 1
                    self.status = self.grantsPermission ? .authorized : .denied
                    return self.grantsPermission
                },
                deliverRequest: { [unowned self] request in
                    self.pending.removeAll { $0.identifier == request.identifier }
                    self.pending.append(request)
                },
                pendingRequests: { [unowned self] in self.pending },
                removeRequests: { [unowned self] ids in self.pending.removeAll { ids.contains($0.identifier) } })
        }
    }

    private func enabledDefaults() -> UserDefaults {
        let defaults = TestSupport.makeDefaults()
        defaults.set(true, forKey: Constants.UserDefaultsKeys.gearRemindersEnabled)
        return defaults
    }

    @Test func remindersCoverSensorCleaningAndEachLoan() throws {
        let container = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: container.mainContext)
        try container.mainContext.save()
        let reminders = NotificationManager.GearReminder.all(for: body)
        #expect(reminders.count == 2)
        let cleaning = try #require(reminders.first { $0.identifier.hasPrefix("sensor_cleaning_") })
        #expect(cleaning.due == body.nextSensorCleaningDate)
        #expect(cleaning.hour == 9)
        #expect(cleaning.minute == 30)
        let loan = try #require(reminders.first { $0.identifier.hasPrefix("loan_due_") })
        #expect(loan.due == body.loans?.first?.dueDate)
        #expect(loan.body.contains("Sam"))
    }

    @Test func aLensHasNoSensorCleaningReminder() throws {
        let container = try TestSupport.makeContainer()
        let lens = TestSupport.insertSampleLens(into: container.mainContext)
        lens.sensorCleaningIntervalDays = 30
        lens.lastSensorCleaningDate = Date()
        #expect(NotificationManager.GearReminder.all(for: lens).first?.due == nil)
    }

    @Test func refreshSchedulesDueRemindersAndDropsReturnedLoans() async throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody, make: "Sony", model: "A7 IV")
        context.insert(body)
        let loan = GearLoan(gearItem: body, person: "Kim", dueDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()))
        context.insert(loan)
        try context.save()

        let center = FakeCenter()
        let manager = center.make(defaults: enabledDefaults())
        await manager.refreshGearReminders(for: [body])
        #expect(center.pending.map(\.identifier) == ["loan_due_\(loan.id.uuidString)"])
        #expect(center.pending.first?.content.body.contains("Kim") == true)

        loan.returnedDate = Date()
        try context.save()
        await manager.refreshGearReminders(for: [body])
        #expect(center.pending.isEmpty)
    }

    @Test func nothingIsScheduledWhenTurnedOffOrUnauthorized() async throws {
        let container = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: container.mainContext)
        body.loans?.first?.dueDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())
        try container.mainContext.save()

        let off = FakeCenter()
        await off.make(defaults: TestSupport.makeDefaults()).refreshGearReminders(for: [body])
        #expect(off.pending.isEmpty)

        let denied = FakeCenter()
        denied.status = .denied
        await denied.make(defaults: enabledDefaults()).refreshGearReminders(for: [body])
        #expect(denied.pending.isEmpty)
    }

    @Test func deletedItemsLoseTheirReminders() async throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody)
        body.sensorCleaningIntervalDays = 30
        body.lastSensorCleaningDate = Date()
        context.insert(body)
        try context.save()

        let center = FakeCenter()
        let manager = center.make(defaults: enabledDefaults())
        await manager.refreshGearReminders(for: [body])
        #expect(center.pending.count == 1)
        await manager.refreshGearReminders(for: [])
        #expect(center.pending.isEmpty)
    }
}

@MainActor
struct TimerAlertTests {
    private typealias FakeCenter = NotificationManagerTests.FakeCenter

    @Test func alertsAreScheduledReplacedAndCancelledByGroup() async {
        let center = FakeCenter()
        // Timer alerts don't depend on the Gear Reminders setting, which is off here.
        let manager = center.make(defaults: TestSupport.makeDefaults())
        let now = Date()
        manager.scheduleTimerAlerts([.init(date: now.addingTimeInterval(60), title: "A", body: "a"),
                                     .init(date: now.addingTimeInterval(120), title: "B", body: "b"),
                                     .init(date: now.addingTimeInterval(-5), title: "Past", body: "")],
                                    group: "dev")
        await manager.waitForPendingWork()
        #expect(center.pending.map(\.identifier) == ["timer_dev_0", "timer_dev_1"])
        #expect(center.pending.first?.content.title == "A")

        manager.scheduleTimerAlerts([.init(date: now.addingTimeInterval(30), title: "C", body: "")], group: "dev")
        manager.scheduleTimerAlerts([.init(date: now.addingTimeInterval(30), title: "D", body: "")], group: "exposure")
        await manager.waitForPendingWork()
        #expect(Set(center.pending.map(\.identifier)) == ["timer_dev_0", "timer_exposure_0"])

        // Reconciling gear reminders leaves timer alerts alone.
        await manager.refreshGearReminders(for: [])
        #expect(center.pending.count == 2)

        manager.cancelTimerAlerts(group: "dev")
        await manager.waitForPendingWork()
        #expect(center.pending.map(\.identifier) == ["timer_exposure_0"])
    }

    @Test func theFirstTimerAsksForPermission() async {
        let center = FakeCenter()
        center.status = .notDetermined
        let manager = center.make(defaults: TestSupport.makeDefaults())
        await manager.refreshAuthorizationStatus()
        manager.scheduleTimerAlerts([.init(date: Date().addingTimeInterval(60), title: "A", body: "")], group: "x")
        await manager.waitForPendingWork()
        #expect(center.permissionRequests == 1)
        #expect(center.pending.count == 1)
    }

    @Test func nothingIsScheduledWithoutPermission() async {
        let center = FakeCenter()
        center.status = .notDetermined
        center.grantsPermission = false
        let manager = center.make(defaults: TestSupport.makeDefaults())
        await manager.refreshAuthorizationStatus()
        manager.scheduleTimerAlerts([.init(date: Date().addingTimeInterval(60), title: "A", body: "")], group: "x")
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }
}

@MainActor
struct ToolTimersTests {
    private typealias FakeCenter = NotificationManagerTests.FakeCenter

    private func makeTimers() async -> (ToolTimers, NotificationManager, FakeCenter) {
        let center = FakeCenter()
        let manager = center.make(defaults: TestSupport.makeDefaults())
        await manager.refreshAuthorizationStatus()
        return (ToolTimers(notifications: manager), manager, center)
    }

    @Test func exposureCountdownAlertsWhenDone() async {
        let (timers, manager, center) = await makeTimers()
        let now = Date()
        timers.startExposure(seconds: 120, title: "2 min exposure", now: now)
        await manager.waitForPendingWork()
        #expect(timers.exposure?.endsAt == now.addingTimeInterval(120))
        #expect(timers.exposure?.remaining(at: now.addingTimeInterval(20)) == 100)
        #expect(center.pending.map(\.identifier) == ["timer_exposure_0"])
        #expect(center.pending.first?.content.title == "Exposure done")
        #expect(timers.hasActiveTimer)

        timers.cancelExposure()
        await manager.waitForPendingWork()
        #expect(timers.exposure == nil)
        #expect(center.pending.isEmpty)
    }

    @Test func developmentAlertsFollowTheRunningStep() async {
        let (timers, manager, center) = await makeTimers()
        timers.beginDevelopment(recipeName: "HP5", recipeID: nil, steps: [
            DevelopmentStepPlan(name: "Developer", duration: 600, agitation: .everyMinute),
            DevelopmentStepPlan(name: "Stop", duration: 30, agitation: .none)
        ])
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty, "Nothing runs until the step is started")

        timers.startStep()
        await manager.waitForPendingWork()
        // Agitations at 1:00 … 9:00, the pour warning, and the end.
        #expect(center.pending.count == 11)

        timers.pauseStep()
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty, "A paused step has nothing to alert")

        timers.nextStep()
        timers.startStep()
        await manager.waitForPendingWork()
        #expect(center.pending.count == 1, "A short step with no agitation only alerts at its end")
        #expect(center.pending.first?.content.title == "Stop done")
        #expect(center.pending.first?.content.body == "That was the last step.")

        timers.endDevelopment()
        await manager.waitForPendingWork()
        #expect(timers.development == nil)
        #expect(center.pending.isEmpty)
    }

    @Test func stepAlertsNameWhatComesNext() {
        var session = DevelopmentSession(steps: [
            DevelopmentStepPlan(name: "Developer", duration: 120, agitation: .none),
            DevelopmentStepPlan(name: "Fixer", duration: 300, agitation: .none)
        ])
        let now = Date(timeIntervalSince1970: 1_000)
        session.start(at: now)
        let alerts = ToolTimers.alerts(for: session, now: now)
        #expect(alerts.map(\.title) == ["Developer: pour out", "Developer done"])
        #expect(alerts.last?.body == "Next: Fixer.")
        #expect(alerts.first?.date == now.addingTimeInterval(110))
    }
}

/// Golden-hour heads-ups for planned shoots.
@MainActor
struct ShootAlertTests {
    private typealias FakeCenter = NotificationManagerTests.FakeCenter

    /// Gear reminders on, to show a gear refresh still leaves shoot alerts alone.
    private func enabledDefaults() -> UserDefaults {
        let defaults = TestSupport.makeDefaults()
        defaults.set(true, forKey: Constants.UserDefaultsKeys.gearRemindersEnabled)
        return defaults
    }

    @Test func shootAlertsSurviveGearRefreshesAndAreReplaced() async {
        let center = FakeCenter()
        let manager = center.make(defaults: enabledDefaults())
        let soon = ShootAlert(identifier: "shoot_a_0", date: Date().addingTimeInterval(3600), title: "Golden hour", body: "Soon")
        let past = ShootAlert(identifier: "shoot_b_0", date: Date().addingTimeInterval(-60), title: "Golden hour", body: "Gone")
        await manager.replaceShootAlerts([soon, past])
        #expect(center.pending.map(\.identifier) == ["shoot_a_0"], "Past alerts are skipped")
        await manager.refreshGearReminders(for: [])
        #expect(center.pending.map(\.identifier) == ["shoot_a_0"], "A gear refresh leaves shoot alerts alone")
        await manager.replaceShootAlerts([])
        #expect(center.pending.isEmpty)
    }

    @Test func shootAlertsAskForPermissionOnlyWhenAsked() async {
        let center = FakeCenter()
        center.status = .notDetermined
        let manager = center.make(defaults: enabledDefaults())
        let alert = ShootAlert(identifier: "shoot_a_0", date: Date().addingTimeInterval(3600), title: "Golden hour", body: "Soon")
        await manager.replaceShootAlerts([alert])
        #expect(center.permissionRequests == 0, "A background refresh never prompts")
        #expect(center.pending.isEmpty)
        await manager.replaceShootAlerts([alert], askingPermission: true)
        #expect(center.permissionRequests == 1)
        #expect(center.pending.count == 1)
    }

    @Test func plansCoverUpcomingShootsWithAPlaceAndAHeadsUp() async throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let bst = TimeZone(secondsFromGMT: 3600)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = bst
        let at = { (hour: Int) in calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: hour))! }
        let now = at(12)
        let greenwich = PlaceValue(name: "Greenwich Park", coordinate: GeoCoordinate(latitude: 51.4769, longitude: -0.0005),
                                   timeZoneIdentifier: "Europe/London")

        let evening = Shoot(title: "Evening", startDate: at(19), endDate: at(22))
        evening.place = greenwich
        evening.goldenHourAlertMinutes = 30
        let noPlace = Shoot(title: "Studio", startDate: at(19), endDate: at(22))
        noPlace.goldenHourAlertMinutes = 30
        let noAlert = Shoot(title: "Quiet", startDate: at(19), endDate: at(22))
        noAlert.place = greenwich
        let finished = Shoot(title: "Morning", startDate: at(4), endDate: at(6))
        finished.place = greenwich
        finished.goldenHourAlertMinutes = 30
        for shoot in [evening, noPlace, noAlert, finished] { context.insert(shoot) }

        let alerts = await ShootAlertScheduler.alerts(for: [evening, noPlace, noAlert, finished], now: now)
        #expect(alerts.count == 1)
        let alert = try #require(alerts.first)
        #expect(alert.identifier == "shoot_\(evening.id.uuidString)_0")
        let window = try #require(ShootLight.goldenHours(for: evening.interval, observer: greenwich.coordinate,
                                                         timeZone: greenwich.timeZone).first)
        #expect(alert.date == window.start.addingTimeInterval(-30 * 60))
        #expect(alert.body.hasPrefix("Evening: golden hour at Greenwich Park starts at"))
    }
}

