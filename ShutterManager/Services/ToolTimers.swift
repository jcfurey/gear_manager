//
//  ToolTimers.swift
//  ShutterManager
//
//  The tools' running timers: a long-exposure countdown and a film development run. Held for the
//  whole session, so leaving a tool's screen doesn't stop its timer, and backed by notifications,
//  so the alerts still come with the app in the background or the screen off. With notifications
//  off, the alerts come from the app itself while it's open. Each running timer also shows as a
//  Live Activity on the Lock Screen and in the Dynamic Island.
//

import Foundation
import Observation

@MainActor
@Observable
final class ToolTimers {
    /// The app's timers, which show as Live Activities. Timers made elsewhere (tests) show none
    /// unless they're given somewhere to show them.
    static let shared = ToolTimers(activities: TimerActivityController.shared)

    /// A countdown for a long (bulb) exposure.
    struct Countdown: Equatable {
        let title: String
        let duration: Double
        let endsAt: Date

        func remaining(at date: Date) -> Double { max(endsAt.timeIntervalSince(date), 0) }
        func isDone(at date: Date) -> Bool { date >= endsAt }
    }

    /// A development recipe being run, one step at a time.
    struct DevelopmentRun: Equatable {
        let recipeID: UUID?
        let recipeName: String
        var session: DevelopmentSession
    }

    private(set) var exposure: Countdown?
    private(set) var development: DevelopmentRun?

    @ObservationIgnored private let notifications: NotificationManager
    /// The running timers' alerts by group, kept so the app can give them itself.
    @ObservationIgnored private var cues: [String: [NotificationManager.TimerAlert]] = [:]
    /// Alerts up to this moment have been looked at.
    @ObservationIgnored private var cuesSeenThrough = Date.distantPast
    @ObservationIgnored private var cueLoop: Task<Void, Never>?
    @ObservationIgnored private let giveCue: @MainActor (NotificationManager.TimerAlert) -> Void
    @ObservationIgnored private let activities: TimerActivityPresenting?
    /// A development run shows its activity from the first step's start, not from when the
    /// recipe is loaded: until then there's no clock to show.
    @ObservationIgnored private var showsDevelopmentActivity = false

    static let exposureGroup = "exposure"
    static let developmentGroup = "development"
    /// The "start pouring" alert comes this long before a step ends, for steps long enough to need it.
    static let pourWarningSeconds = 10.0
    /// How often the app looks for an alert that has come due.
    static let cueInterval: Duration = .milliseconds(250)
    /// An alert older than this is old news: the app was in the background when it came due.
    static let cueFreshness = 2.0

    /// `notifications` defaults to the shared manager and `cue` to the app's own alert (default
    /// arguments can't read them, being evaluated off the main actor).
    init(notifications: NotificationManager? = nil, cue: (@MainActor (NotificationManager.TimerAlert) -> Void)? = nil,
         activities: TimerActivityPresenting? = nil) {
        self.notifications = notifications ?? .shared
        giveCue = cue ?? { TimerCue.give($0) }
        self.activities = activities
    }

    var hasActiveTimer: Bool { exposure != nil || development != nil }

    // MARK: - Exposure

    func startExposure(seconds: Double, title: String, now: Date = Date()) {
        guard seconds.isFinite, seconds > 0 else { return }
        let countdown = Countdown(title: title, duration: seconds, endsAt: now.addingTimeInterval(seconds))
        exposure = countdown
        schedule([.init(date: countdown.endsAt, title: "Exposure done", body: "Close the shutter: \(title).", isRequired: true)],
                 group: Self.exposureGroup, now: now)
        activities?.show(Self.activityState(for: countdown, now: now), kind: .exposure, staleDate: countdown.endsAt)
    }

    func cancelExposure() {
        exposure = nil
        cancelAlerts(group: Self.exposureGroup)
        activities?.end(.exposure)
    }

    // MARK: - Development

    /// Loads a recipe's steps, ready to start the first one. Replaces any run in progress.
    func beginDevelopment(recipeName: String, recipeID: UUID?, steps: [DevelopmentStepPlan]) {
        development = DevelopmentRun(recipeID: recipeID, recipeName: recipeName,
                                     session: DevelopmentSession(steps: steps))
        cancelAlerts(group: Self.developmentGroup)
        // The run this replaces, if any, takes its activity with it.
        showsDevelopmentActivity = false
        activities?.end(.development)
    }

    func startStep(now: Date = Date()) {
        updateDevelopment(now: now) { $0.start(at: now) }
    }

    func pauseStep(now: Date = Date()) {
        updateDevelopment(now: now) { $0.pause(at: now) }
    }

    func nextStep(now: Date = Date()) {
        updateDevelopment(now: now) { $0.advance() }
    }

    func restartStep(now: Date = Date()) {
        updateDevelopment(now: now) { $0.restartStep() }
    }

    func endDevelopment() {
        development = nil
        cancelAlerts(group: Self.developmentGroup)
        showsDevelopmentActivity = false
        activities?.end(.development)
    }

    /// Schedules the running step's alerts again from `now`. A long step has more agitations
    /// than iOS keeps pending at once, so coming back to the app tops them up.
    func refreshDevelopmentAlerts(now: Date = Date()) {
        guard let run = development, run.session.isRunning else { return }
        schedule(Self.alerts(for: run.session, now: now), group: Self.developmentGroup, now: now)
    }

    private func updateDevelopment(now: Date, _ change: (inout DevelopmentSession) -> Void) {
        guard var run = development else { return }
        change(&run.session)
        development = run
        schedule(Self.alerts(for: run.session, now: now), group: Self.developmentGroup, now: now)
        showDevelopmentActivity(now: now)
    }

    // MARK: - Live Activities

    /// Brings the timers' Live Activities up to date with the clock: a step or an exposure whose
    /// time ran out while the app was away says so, and a finished exposure's activity goes, now
    /// that the app itself is showing it. Called when the app comes to the front.
    func refreshActivities(now: Date = Date()) {
        if let exposure, exposure.isDone(at: now) {
            activities?.end(.exposure)
        }
        showDevelopmentActivity(now: now)
    }

    private func showDevelopmentActivity(now: Date) {
        guard let run = development else { return }
        let phase = run.session.phase(at: now)
        if case .running = phase { showsDevelopmentActivity = true }
        guard showsDevelopmentActivity else { return }
        guard let state = Self.activityState(for: run, now: now) else {
            // Every step is done.
            showsDevelopmentActivity = false
            activities?.end(.development)
            return
        }
        activities?.show(state, kind: .development, staleDate: state.phase == .running ? state.endsAt : nil)
    }

    /// A bulb exposure as its Live Activity shows it.
    static func activityState(for exposure: Countdown, now: Date) -> TimerActivityAttributes.ContentState {
        TimerActivityAttributes.ContentState(
            title: exposure.title, detail: "", next: "Close the shutter",
            phase: exposure.isDone(at: now) ? .done : .running,
            startedAt: exposure.endsAt.addingTimeInterval(-exposure.duration), endsAt: exposure.endsAt,
            remaining: exposure.remaining(at: now))
    }

    /// A development run's current step as its Live Activity shows it; nil once every step is done.
    static func activityState(for run: DevelopmentRun, now: Date) -> TimerActivityAttributes.ContentState? {
        let session = run.session
        guard let step = session.currentStep else { return nil }
        let following = session.steps.indices.contains(session.currentIndex + 1) ? session.steps[session.currentIndex + 1] : nil
        let place = "step \(session.currentIndex + 1) of \(session.steps.count)"
        // The step's whole span: it began `elapsed` seconds ago, however often it was paused.
        let startedAt = now.addingTimeInterval(-session.elapsed(at: now))
        let clock: TimerActivityAttributes.Phase
        let remaining: Double
        switch session.phase(at: now) {
        case .running(let left, _):
            clock = .running
            remaining = left
        case .paused(let left):
            clock = .paused
            remaining = left
        case .ready:
            clock = .ready
            remaining = step.duration
        case .stepComplete, .finished:
            clock = .done
            remaining = 0
        }
        return TimerActivityAttributes.ContentState(
            title: step.name.isEmpty ? "Step \(session.currentIndex + 1)" : step.name,
            detail: run.recipeName.isEmpty ? "Step \(session.currentIndex + 1) of \(session.steps.count)" : "\(run.recipeName) · \(place)",
            next: following.map { "Next: \($0.name)" } ?? "Last step",
            phase: clock, startedAt: startedAt, endsAt: startedAt.addingTimeInterval(step.duration), remaining: remaining)
    }

    // MARK: - Alerts

    /// Schedules `alerts` as notifications and keeps them, so the app can give them itself.
    private func schedule(_ alerts: [NotificationManager.TimerAlert], group: String, now: Date) {
        cues[group] = alerts
        // Nothing from before this moment is owed: a step started late doesn't replay its past.
        cuesSeenThrough = max(cuesSeenThrough, now)
        notifications.scheduleTimerAlerts(alerts, group: group)
        startCueLoop()
    }

    private func cancelAlerts(group: String) {
        cues[group] = nil
        notifications.cancelTimerAlerts(group: group)
    }

    /// The alerts still to come at `now`, soonest first.
    func upcomingCues(at now: Date = Date()) -> [NotificationManager.TimerAlert] {
        cues.values.flatMap { $0 }.filter { $0.date > now }.sorted { $0.date < $1.date }
    }

    /// Gives the app's own alert for what has just come due, when a notification can't be shown
    /// (they're off, or not yet allowed). With notifications on this does nothing: the
    /// notification is the alert, in the app and out of it.
    ///
    /// One alert at a time: of several due together, a step's end or pour wins over an agitation.
    /// Anything older than `cueFreshness` is skipped, so coming back from the background doesn't
    /// replay what was missed.
    func giveDueCues(now: Date = Date()) {
        let due = cues.values.flatMap { $0 }
            .filter { $0.date > cuesSeenThrough && $0.date <= now && now.timeIntervalSince($0.date) <= ToolTimers.cueFreshness }
        cuesSeenThrough = max(cuesSeenThrough, now)
        guard !notifications.canDeliver else { return }
        let latest = due.max { ($0.isRequired ? 1 : 0, $0.date) < ($1.isRequired ? 1 : 0, $1.date) }
        if let latest { giveCue(latest) }
    }

    /// Looks for due alerts while any are still to come. The loop sleeps with the app, so it
    /// only ever gives an alert while the app is open.
    private func startCueLoop() {
        guard cueLoop == nil else { return }
        cueLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: ToolTimers.cueInterval)
                guard let self else { return }
                self.giveDueCues()
                if self.upcomingCues().isEmpty {
                    self.cueLoop = nil
                    return
                }
            }
        }
    }

    /// The alerts for the running step: each agitation, a pour warning, and the end.
    static func alerts(for session: DevelopmentSession, now: Date) -> [NotificationManager.TimerAlert] {
        guard let step = session.currentStep else { return [] }
        let cues = session.upcomingCues(after: now)
        guard let end = cues.stepEnd else { return [] }
        var alerts = cues.agitations.map {
            NotificationManager.TimerAlert(date: $0, title: "Agitate", body: "\(step.name): agitate now.")
        }
        if step.duration >= 60 {
            alerts.append(.init(date: end.addingTimeInterval(-pourWarningSeconds), title: "\(step.name): pour out",
                                body: "\(Int(pourWarningSeconds)) seconds left. Start pouring.", isRequired: true))
        }
        let next = session.steps.indices.contains(session.currentIndex + 1) ? session.steps[session.currentIndex + 1] : nil
        alerts.append(.init(date: end, title: "\(step.name) done",
                            body: next.map { "Next: \($0.name)." } ?? "That was the last step.", isRequired: true))
        return alerts
    }
}
