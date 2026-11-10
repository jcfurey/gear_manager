//
//  TimerCueTests.swift
//  ShutterManagerTests
//
//  A running timer's alerts when notifications can't show them: the app gives them itself, once
//  each, only while they're fresh.
//

import Foundation
import Testing
import UserNotifications
@testable import ShutterManager

@MainActor
struct TimerCueTests {
    private typealias FakeCenter = NotificationManagerTests.FakeCenter

    /// The alerts the app gave itself.
    @MainActor
    private final class Given {
        var alerts: [NotificationManager.TimerAlert] = []
        var titles: [String] { alerts.map(\.title) }
    }

    /// Timers whose own alerts are collected, with notifications allowed or not. The center and
    /// manager are returned to be kept alive, and drained, by the test.
    private func makeTimers(notifications status: UNAuthorizationStatus) async
        -> (timers: ToolTimers, given: Given, manager: NotificationManager, center: FakeCenter) {
        let center = FakeCenter()
        center.status = status
        let manager = center.make(defaults: TestSupport.makeDefaults())
        await manager.refreshAuthorizationStatus()
        let given = Given()
        return (ToolTimers(notifications: manager, cue: { given.alerts.append($0) }), given, manager, center)
    }

    @Test func withNotificationsOffTheAppGivesTheAlertItself() async {
        let (timers, given, manager, center) = await makeTimers(notifications: .denied)
        let start = Date()
        timers.startExposure(seconds: 30, title: "30 s exposure", now: start)
        #expect(timers.upcomingCues(at: start).map(\.title) == ["Exposure done"])

        timers.giveDueCues(now: start.addingTimeInterval(10))
        #expect(given.alerts.isEmpty, "Nothing is due yet")
        timers.giveDueCues(now: start.addingTimeInterval(30.2))
        #expect(given.titles == ["Exposure done"])
        #expect(given.alerts.first?.body == "Close the shutter: 30 s exposure.")
        timers.giveDueCues(now: start.addingTimeInterval(30.4))
        timers.giveDueCues(now: start.addingTimeInterval(31))
        #expect(given.alerts.count == 1, "Each alert is given once")
        #expect(timers.upcomingCues(at: start.addingTimeInterval(31)).isEmpty)

        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty, "And nothing was scheduled as a notification")
    }

    @Test func withNotificationsOnTheNotificationIsTheAlert() async {
        let (timers, given, manager, center) = await makeTimers(notifications: .authorized)
        let start = Date()
        timers.startExposure(seconds: 30, title: "30 s exposure", now: start)
        timers.giveDueCues(now: start.addingTimeInterval(30.2))
        #expect(given.alerts.isEmpty)
        await manager.waitForPendingWork()
        #expect(center.pending.count == 1)
    }

    /// Back from the background a minute late, the alert is old news.
    @Test func anAlertMissedInTheBackgroundIsNotReplayed() async {
        let (timers, given, manager, center) = await makeTimers(notifications: .denied)
        let start = Date()
        timers.startExposure(seconds: 30, title: "30 s exposure", now: start)
        timers.giveDueCues(now: start.addingTimeInterval(90))
        timers.giveDueCues(now: start.addingTimeInterval(90.3))
        #expect(given.alerts.isEmpty)
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }

    /// An exposure ending on the same second as an agitation: the one that ends something wins,
    /// and the next agitation still comes.
    @Test func ofAlertsDueTogetherTheOneThatEndsSomethingWins() async {
        let (timers, given, manager, center) = await makeTimers(notifications: .denied)
        let start = Date()
        timers.beginDevelopment(recipeName: "HP5", recipeID: nil, steps: [
            DevelopmentStepPlan(name: "Developer", duration: 600, agitation: .everyMinute)
        ])
        timers.startStep(now: start)
        timers.startExposure(seconds: 60, title: "1 min exposure", now: start)
        let upcoming = timers.upcomingCues(at: start)
        #expect(upcoming.count == 12, "Nine agitations, the pour warning, the step's end and the exposure's")
        #expect(upcoming.map(\.date) == upcoming.map(\.date).sorted(), "Soonest first")

        timers.giveDueCues(now: start.addingTimeInterval(60.2))
        #expect(given.titles == ["Exposure done"])
        timers.giveDueCues(now: start.addingTimeInterval(120.1))
        #expect(given.titles == ["Exposure done", "Agitate"])
        // Ten seconds from the end, then the end.
        timers.giveDueCues(now: start.addingTimeInterval(590.1))
        timers.giveDueCues(now: start.addingTimeInterval(600.1))
        #expect(given.titles == ["Exposure done", "Agitate", "Developer: pour out", "Developer done"])
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }

    @Test func aStoppedTimerGivesNothing() async {
        let (timers, given, manager, center) = await makeTimers(notifications: .denied)
        let start = Date()
        timers.startExposure(seconds: 30, title: "30 s exposure", now: start)
        timers.cancelExposure()
        #expect(timers.upcomingCues(at: start).isEmpty)
        timers.giveDueCues(now: start.addingTimeInterval(30.2))
        #expect(given.alerts.isEmpty)

        // A paused development step has nothing due either.
        timers.beginDevelopment(recipeName: "HP5", recipeID: nil, steps: [
            DevelopmentStepPlan(name: "Stop", duration: 30, agitation: .none)
        ])
        timers.startStep(now: start)
        timers.pauseStep(now: start.addingTimeInterval(5))
        timers.giveDueCues(now: start.addingTimeInterval(30.2))
        #expect(given.alerts.isEmpty)
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }
}
