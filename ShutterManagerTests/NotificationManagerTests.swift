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

        func make(defaults: UserDefaults) -> NotificationManager {
            NotificationManager(
                defaults: defaults,
                authorizationProvider: { [unowned self] in self.status },
                requestAuthorization: { true },
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
