//
//  ToolTimers.swift
//  ShutterManager
//
//  The tools' running timers: a long-exposure countdown and a film development run. Held for the
//  whole session, so leaving a tool's screen doesn't stop its timer, and backed by notifications,
//  so the alerts still come with the app in the background or the screen off.
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

    static let exposureGroup = "exposure"
    static let developmentGroup = "development"
    /// The "start pouring" alert comes this long before a step ends, for steps long enough to need it.
    static let pourWarningSeconds = 10.0

    init(notifications: NotificationManager = .shared) {
        self.notifications = notifications
    }

    var hasActiveTimer: Bool { exposure != nil || development != nil }

    // MARK: - Exposure

    func startExposure(seconds: Double, title: String, now: Date = Date()) {
        guard seconds.isFinite, seconds > 0 else { return }
        let countdown = Countdown(title: title, duration: seconds, endsAt: now.addingTimeInterval(seconds))
        exposure = countdown
        notifications.scheduleTimerAlerts(
            [.init(date: countdown.endsAt, title: "Exposure done", body: "Close the shutter: \(title).")],
            group: Self.exposureGroup)
    }

    func cancelExposure() {
        exposure = nil
        notifications.cancelTimerAlerts(group: Self.exposureGroup)
    }

    // MARK: - Development

    /// Loads a recipe's steps, ready to start the first one. Replaces any run in progress.
    func beginDevelopment(recipeName: String, recipeID: UUID?, steps: [DevelopmentStepPlan]) {
        development = DevelopmentRun(recipeID: recipeID, recipeName: recipeName,
                                     session: DevelopmentSession(steps: steps))
        notifications.cancelTimerAlerts(group: Self.developmentGroup)
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
        notifications.cancelTimerAlerts(group: Self.developmentGroup)
    }

    private func updateDevelopment(now: Date, _ change: (inout DevelopmentSession) -> Void) {
        guard var run = development else { return }
        change(&run.session)
        development = run
        notifications.scheduleTimerAlerts(Self.alerts(for: run.session, now: now), group: Self.developmentGroup)
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
                                body: "\(Int(pourWarningSeconds)) seconds left. Start pouring."))
        }
        let next = session.steps.indices.contains(session.currentIndex + 1) ? session.steps[session.currentIndex + 1] : nil
        alerts.append(.init(date: end, title: "\(step.name) done",
                            body: next.map { "Next: \($0.name)." } ?? "That was the last step."))
        return alerts
    }
}
