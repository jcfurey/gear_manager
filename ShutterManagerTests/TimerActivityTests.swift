//
//  TimerActivityTests.swift
//  ShutterManagerTests
//
//  The running timers' Live Activities: what the timers ask to be shown and when, and the words
//  and numbers the widget extension draws from it. A recorder stands in for ActivityKit.
//

import Foundation
import Testing
import UserNotifications
@testable import ShutterManager

@MainActor
struct TimerActivityTests {
    private typealias FakeCenter = NotificationManagerTests.FakeCenter
    private typealias ActivityState = TimerActivityAttributes.ContentState

    /// Keeps what the timers asked for, in order.
    @MainActor
    private final class Recorder: TimerActivityPresenting {
        enum Event: Equatable {
            case show(TimerActivityAttributes.Kind, ActivityState, staleDate: Date?)
            case end(TimerActivityAttributes.Kind)
        }

        var events: [Event] = []

        func show(_ state: ActivityState, kind: TimerActivityAttributes.Kind, staleDate: Date?) {
            events.append(.show(kind, state, staleDate: staleDate))
        }

        func end(_ kind: TimerActivityAttributes.Kind) {
            events.append(.end(kind))
        }

        /// The states shown, without the ends.
        var shown: [ActivityState] {
            events.compactMap { event in
                if case .show(_, let state, _) = event { return state }
                return nil
            }
        }
    }

    private func makeTimers() async -> (timers: ToolTimers, recorder: Recorder, manager: NotificationManager, center: FakeCenter) {
        let center = FakeCenter()
        let manager = center.make(defaults: TestSupport.makeDefaults())
        await manager.refreshAuthorizationStatus()
        let recorder = Recorder()
        return (ToolTimers(notifications: manager, activities: recorder), recorder, manager, center)
    }

    private static let steps = [
        DevelopmentStepPlan(name: "Developer", duration: 600, agitation: .everyMinute),
        DevelopmentStepPlan(name: "Stop", duration: 30, agitation: .none)
    ]

    // MARK: - Exposure

    @Test func anExposureShowsUntilItIsCleared() async {
        let (timers, recorder, manager, center) = await makeTimers()
        let start = Date()
        timers.startExposure(seconds: 120, title: "2 min exposure", now: start)
        let end = start.addingTimeInterval(120)
        #expect(recorder.events == [.show(.exposure, ActivityState(
            title: "2 min exposure", detail: "", next: "Close the shutter", phase: .running,
            startedAt: start, endsAt: end, remaining: 120), staleDate: end)])

        timers.cancelExposure()
        #expect(recorder.events.last == .end(.exposure))
        #expect(recorder.events.count == 2)
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }

    /// Back in the app after the time ran out, the app itself shows "Done": the activity goes.
    @Test func aFinishedExposuresActivityGoesWhenTheAppComesBack() async {
        let (timers, recorder, manager, center) = await makeTimers()
        let start = Date()
        timers.startExposure(seconds: 30, title: "30 s exposure", now: start)
        timers.refreshActivities(now: start.addingTimeInterval(10))
        #expect(recorder.events.count == 1, "Still running: nothing changes")
        timers.refreshActivities(now: start.addingTimeInterval(31))
        #expect(recorder.events.last == .end(.exposure))
        #expect(timers.exposure != nil, "The timer itself stays until it's cleared")
        await manager.waitForPendingWork()
        #expect(center.pending.count == 1)
    }

    // MARK: - Development

    @Test func aDevelopmentRunShowsFromItsFirstStepToItsLast() async {
        let (timers, recorder, manager, center) = await makeTimers()
        let start = Date()
        timers.beginDevelopment(recipeName: "HP5", recipeID: nil, steps: Self.steps)
        #expect(recorder.events == [.end(.development)], "A loaded recipe has no clock to show yet")

        timers.startStep(now: start)
        #expect(recorder.events.last == .show(.development, ActivityState(
            title: "Developer", detail: "HP5 · step 1 of 2", next: "Next: Stop", phase: .running,
            startedAt: start, endsAt: start.addingTimeInterval(600), remaining: 600),
            staleDate: start.addingTimeInterval(600)))

        // Paused 100 s in: 500 s left, and nothing counting down to go stale.
        timers.pauseStep(now: start.addingTimeInterval(100))
        guard case .show(_, let paused, let pausedStale)? = recorder.events.last else {
            Issue.record("A pause is shown")
            return
        }
        #expect(paused.phase == .paused)
        #expect(paused.remaining == 500)
        #expect(pausedStale == nil)
        #expect(abs(paused.fractionDone - 1.0 / 6) < 1e-9)

        // Resumed 100 s later: the end moves out by the pause.
        timers.startStep(now: start.addingTimeInterval(200))
        guard case .show(_, let resumed, let resumedStale)? = recorder.events.last else {
            Issue.record("A resumed step is shown")
            return
        }
        #expect(resumed.phase == .running)
        #expect(resumed.endsAt == start.addingTimeInterval(700))
        #expect(resumed.startedAt == start.addingTimeInterval(100))
        #expect(resumedStale == start.addingTimeInterval(700))

        timers.nextStep(now: start.addingTimeInterval(700))
        #expect(recorder.shown.last?.title == "Stop")
        #expect(recorder.shown.last?.phase == .ready)
        #expect(recorder.shown.last?.remaining == 30)
        #expect(recorder.shown.last?.detail == "HP5 · step 2 of 2")
        #expect(recorder.shown.last?.next == "Last step")

        timers.startStep(now: start.addingTimeInterval(710))
        #expect(recorder.shown.last?.phase == .running)
        timers.nextStep(now: start.addingTimeInterval(740))
        #expect(recorder.events.last == .end(.development), "After the last step there's nothing left to show")
        timers.endDevelopment()
        #expect(recorder.events.last == .end(.development))
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }

    /// Stepping through a recipe without starting a clock shows nothing.
    @Test func aRunThatNeverStartsShowsNothing() async {
        let (timers, recorder, manager, center) = await makeTimers()
        timers.beginDevelopment(recipeName: "HP5", recipeID: nil, steps: Self.steps)
        timers.pauseStep()
        timers.nextStep()
        timers.restartStep()
        timers.refreshActivities()
        #expect(recorder.shown.isEmpty)
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }

    /// A step whose time ran out while the app was away says so when the app comes back.
    @Test func aStepThatRanOutSaysSoOnReturn() async {
        let (timers, recorder, manager, center) = await makeTimers()
        let start = Date()
        timers.beginDevelopment(recipeName: "HP5", recipeID: nil, steps: Self.steps)
        timers.startStep(now: start)
        timers.refreshActivities(now: start.addingTimeInterval(650))
        #expect(recorder.shown.last?.phase == .done)
        #expect(recorder.shown.last?.remaining == 0)
        #expect(recorder.shown.last?.caption(stale: false) == "Time's up · Next: Stop")
        guard case .show(_, _, let staleDate)? = recorder.events.last else {
            Issue.record("The finished step is shown")
            return
        }
        #expect(staleDate == nil)
        await manager.waitForPendingWork()
        #expect(center.pending.count >= 1, "The step's alerts were scheduled when it started")
    }

    /// Timers made without somewhere to show activities, as tests and previews make them, run as before.
    @Test func timersRunWithoutActivities() async {
        let center = FakeCenter()
        let manager = center.make(defaults: TestSupport.makeDefaults())
        await manager.refreshAuthorizationStatus()
        let timers = ToolTimers(notifications: manager)
        timers.startExposure(seconds: 30, title: "30 s exposure")
        timers.refreshActivities()
        timers.cancelExposure()
        #expect(timers.exposure == nil)
        await manager.waitForPendingWork()
        #expect(center.pending.isEmpty)
    }

    // MARK: - What's shown

    @Test func aStepWithNoNamesStillReads() {
        let run = ToolTimers.DevelopmentRun(recipeID: nil, recipeName: "",
                                            session: DevelopmentSession(steps: [DevelopmentStepPlan(name: "", duration: 60, agitation: .none)]))
        let state = ToolTimers.activityState(for: run, now: Date())
        #expect(state?.title == "Step 1")
        #expect(state?.detail == "Step 1 of 1")
        #expect(state?.next == "Last step")
        #expect(state?.phase == .ready)

        var finished = run
        finished.session.advance()
        #expect(ToolTimers.activityState(for: finished, now: Date()) == nil)
    }

    @Test func theCaptionSaysWhereThingsStand() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        var state = ActivityState(title: "Developer", detail: "HP5 · step 1 of 2", next: "Next: Stop", phase: .running,
                          startedAt: start, endsAt: start.addingTimeInterval(600), remaining: 600)
        #expect(state.caption(stale: false) == "HP5 · step 1 of 2 · Next: Stop")
        // The system marks a countdown stale when it runs out, with the app asleep.
        #expect(state.caption(stale: true) == "Time's up · Next: Stop")
        #expect(state.isOver(stale: true))
        #expect(!state.isOver(stale: false))

        state.phase = .paused
        state.remaining = 245
        #expect(state.caption(stale: false) == "Paused · Next: Stop")
        #expect(!state.isOver(stale: true), "A paused clock doesn't run out")
        #expect(state.remainingText == "4:05")
        state.phase = .ready
        #expect(state.caption(stale: false) == "Ready to start · Next: Stop")
        state.phase = .done
        #expect(state.caption(stale: false) == "Time's up · Next: Stop")

        let exposure = ActivityState(title: "4 min exposure", detail: "", next: "Close the shutter", phase: .running,
                             startedAt: start, endsAt: start.addingTimeInterval(240), remaining: 240)
        #expect(exposure.caption(stale: false) == "Close the shutter")
    }

    @Test func numbersStayInRange() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        var state = ActivityState(title: "", detail: "", next: "", phase: .paused,
                          startedAt: start, endsAt: start.addingTimeInterval(100), remaining: 25)
        #expect(state.fractionDone == 0.75)
        state.remaining = 500
        #expect(state.fractionDone == 0, "More left than the whole reads as nothing done")
        state.remaining = -5
        #expect(state.fractionDone == 1)
        #expect(state.remainingText == "0:00")
        state.remaining = 3_729
        #expect(state.remainingText == "1:02:09")
        state.remaining = 59.2
        #expect(state.remainingText == "1:00", "Rounded up, as the in-app countdown is")

        // Dates the wrong way round never make a backwards range, which would trap.
        state.endsAt = start.addingTimeInterval(-10)
        #expect(state.interval == start...start)
        #expect(state.fractionDone == 0)
    }

    @Test func oneActivityForEachKindOfTimer() {
        #expect(TimerActivityAttributes.Kind.allCases == [.exposure, .development])
        #expect(TimerActivityAttributes(kind: .exposure).kind == .exposure)
    }
}
