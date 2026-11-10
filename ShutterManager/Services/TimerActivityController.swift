//
//  TimerActivityController.swift
//  ShutterManager
//
//  Starts, updates and ends the running timers' Live Activities.
//

import ActivityKit
import Foundation
import os

/// Where the running timers show themselves outside the app. `ToolTimers` talks to this, so its
/// tests can stand a recorder in for the real thing.
@MainActor
protocol TimerActivityPresenting: AnyObject {
    /// Shows `state` for the timer of `kind`, starting its activity if it has none. `staleDate`
    /// is when the countdown runs out: the system then marks what's shown as stale, and the
    /// activity says the time is up without the app having to run.
    func show(_ state: TimerActivityAttributes.ContentState, kind: TimerActivityAttributes.Kind, staleDate: Date?)
    /// Takes the timer of `kind` off the Lock Screen and out of the Dynamic Island.
    func end(_ kind: TimerActivityAttributes.Kind)
}

/// The Live Activities themselves (ActivityKit). The drawing is in the widget extension
/// (`ShutterManagerWidgets`); both sides share `TimerActivityAttributes`.
///
/// Nothing is pushed to an activity: there's no server. The app updates it when a timer changes,
/// and the system keeps the countdown moving in between.
@MainActor
final class TimerActivityController: TimerActivityPresenting {
    static let shared = TimerActivityController()

    private let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "TimerActivity")
    private var activities: [TimerActivityAttributes.Kind: Activity<TimerActivityAttributes>] = [:]
    /// Requests are made one after another, in the order they were asked for: an update must
    /// never overtake the request that starts its activity, nor an end the update before it.
    private var queueTail: Task<Void, Never>?

    func show(_ state: TimerActivityAttributes.ContentState, kind: TimerActivityAttributes.Kind, staleDate: Date?) {
        enqueue { controller in
            let content = ActivityContent(state: state, staleDate: staleDate)
            if let activity = controller.activities[kind], activity.activityState != .ended,
               activity.activityState != .dismissed {
                await activity.update(content)
                return
            }
            // Off in Settings, or not offered on this device: the timer runs without one.
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                controller.activities[kind] = try Activity<TimerActivityAttributes>.request(
                    attributes: TimerActivityAttributes(kind: kind), content: content, pushType: nil)
            } catch {
                controller.logger.error("Live Activity could not start: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func end(_ kind: TimerActivityAttributes.Kind) {
        enqueue { controller in
            guard let activity = controller.activities.removeValue(forKey: kind) else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends activities left over from an earlier run of the app. The timers they showed went
    /// with that run (`ToolTimers` holds them for the session), so nothing could ever update or
    /// end them.
    func endLeftovers() {
        enqueue { controller in
            for activity in Activity<TimerActivityAttributes>.activities
            where !controller.activities.values.contains(where: { $0.id == activity.id }) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Waits for everything asked for so far. For tests and previews.
    func waitForPendingWork() async {
        await queueTail?.value
    }

    private func enqueue(_ operation: @escaping @MainActor (TimerActivityController) async -> Void) {
        let previous = queueTail
        queueTail = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }
}
