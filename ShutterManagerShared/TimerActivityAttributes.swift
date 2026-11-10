//
//  TimerActivityAttributes.swift
//  ShutterManagerShared
//
//  What a running timer's Live Activity shows. This folder belongs to two targets: the app,
//  which starts and updates the activity, and the widget extension, which draws it.
//

import ActivityKit
import Foundation

/// A running bulb exposure or development step, as its Live Activity shows it on the Lock Screen
/// and in the Dynamic Island.
///
/// The activity gets no pushes: the app updates it while it's open, and in between the system
/// counts the time down by itself and marks the content stale when the time is up.
struct TimerActivityAttributes: ActivityAttributes {
    /// Which timer this is. At most one activity runs for each.
    enum Kind: String, Codable, Hashable, CaseIterable, Sendable {
        case exposure, development
    }

    /// Where the clock is.
    enum Phase: String, Codable, Hashable, Sendable {
        /// Counting down to `endsAt`.
        case running
        /// Stopped part-way, with `remaining` seconds left.
        case paused
        /// A step that hasn't been started, `remaining` seconds long.
        case ready
        /// The time is up.
        case done
    }

    struct ContentState: Codable, Hashable, Sendable {
        /// What's being timed: the exposure ("4 min exposure") or the step ("Developer").
        var title: String
        /// A line under it: "HP5 in Ilfosol 3 · step 1 of 3". Empty for an exposure.
        var detail: String
        /// What follows: "Close the shutter", "Next: Stop", "Last step".
        var next: String
        var phase: Phase
        /// The whole time being counted, start to end. Meaningful while `phase` is `.running`.
        var startedAt: Date
        var endsAt: Date
        /// Seconds left on a clock that isn't running.
        var remaining: Double

        /// The span to count down over. Never backwards, whatever the dates say: a range the
        /// wrong way round would trap.
        var interval: ClosedRange<Date> { startedAt...max(endsAt, startedAt) }

        /// Whether to show the time as up: it is, or the system has marked the countdown stale,
        /// which it does at `endsAt` when the app isn't there to say so.
        func isOver(stale: Bool) -> Bool {
            phase == .done || (phase == .running && stale)
        }
    }

    let kind: Kind
}

// MARK: - What the activity says

// Here, not in the widget extension, so the app's tests can check the words and numbers the
// extension shows.
extension TimerActivityAttributes.ContentState {
    /// The time left on a clock that isn't running: "4:05", or "1:02:09" from an hour up.
    var remainingText: String {
        let whole = Duration.seconds(max(remaining.rounded(.up), 0))
        return whole.formatted(.time(pattern: remaining >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    /// The share of the whole time already run, for a clock that's stopped: 0 to 1.
    var fractionDone: Double {
        let whole = endsAt.timeIntervalSince(startedAt)
        guard whole > 0 else { return 0 }
        return min(max(1 - remaining / whole, 0), 1)
    }

    /// The line under the countdown: where things stand, then what follows.
    func caption(stale: Bool) -> String {
        let status: String
        if isOver(stale: stale) {
            status = "Time's up"
        } else {
            switch phase {
            case .paused: status = "Paused"
            case .ready: status = "Ready to start"
            case .running, .done: status = detail
            }
        }
        return [status, next].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
