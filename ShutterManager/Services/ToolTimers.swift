//
//  ToolTimers.swift
//  ShutterManager
//
//  The tools' running timers: a long-exposure countdown and a film development run. Held for the
//  whole session, so leaving a tool's screen doesn't stop its timer, and backed by notifications,
//  so the alerts still come with the app in the background or the screen off. With notifications
//  off, the alerts come from the app itself while it's open.
//

import Foundation
import Observation

@MainActor
@Observable
final class ToolTimers {
    static let shared = ToolTimers()

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
    init(notifications: NotificationManager? = nil, cue: (@MainActor (NotificationManager.TimerAlert) -> Void)? = nil) {
        self.notifications = notifications ?? .shared
        giveCue = cue ?? { TimerCue.give($0) }
    }

    var hasActiveTimer: Bool { exposure != nil || development != nil }

    // MARK: - Exposure

    func startExposure(seconds: Double, title: String, now: Date = Date()) {
        guard seconds.isFinite, seconds > 0 else { return }
        let countdown = Countdown(title: title, duration: seconds, endsAt: now.addingTimeInterval(seconds))
        exposure = countdown
        schedule([.init(date: countdown.endsAt, title: "Exposure done", body: "Close the shutter: \(title).", isRequired: true)],
                 group: Self.exposureGroup, now: now)
    }

    func cancelExposure() {
        exposure = nil
        cancelAlerts(group: Self.exposureGroup)
    }

    // MARK: - Development

    /// Loads a recipe's steps, ready to start the first one. Replaces any run in progress.
    func beginDevelopment(recipeName: String, recipeID: UUID?, steps: [DevelopmentStepPlan]) {
        development = DevelopmentRun(recipeID: recipeID, recipeName: recipeName,
                                     session: DevelopmentSession(steps: steps))
        cancelAlerts(group: Self.developmentGroup)
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
