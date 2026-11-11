//
//  TimerLiveActivity.swift
//  ShutterManagerWidgets
//
//  A running bulb exposure or development step on the Lock Screen and in the Dynamic Island.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            TimerLockScreenView(kind: context.attributes.kind, state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            let kind = context.attributes.kind
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.title, systemImage: kind.symbol)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerCountdown(state: state, isStale: context.isStale)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        TimerProgress(state: state, isStale: context.isStale)
                        TimerCaption(state: state, isStale: context.isStale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: kind.symbol)
                    .accessibilityLabel(kind.spokenName)
            } compactTrailing: {
                // A running timer's text takes all the width it's offered; hold it to its digits.
                TimerCountdown(state: state, isStale: context.isStale)
                    .frame(maxWidth: 56)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                Image(systemName: kind.symbol)
                    .accessibilityLabel(kind.spokenName)
            }
        }
    }
}

/// The Lock Screen's view: what's being timed, the countdown, a bar, and what follows.
struct TimerLockScreenView: View {
    let kind: TimerActivityAttributes.Kind
    let state: TimerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(state.title, systemImage: kind.symbol)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 12)
                TimerCountdown(state: state, isStale: isStale)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }
            TimerProgress(state: state, isStale: isStale)
            TimerCaption(state: state, isStale: isStale)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

/// The time left. A running clock is drawn by the system, which keeps it moving with the app
/// suspended; the others are fixed text.
struct TimerCountdown: View {
    let state: TimerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if state.isOver(stale: isStale) {
            Text("Done")
        } else if state.phase == .running {
            Text(timerInterval: state.interval, countsDown: true)
                .monospacedDigit()
        } else {
            Text(state.remainingText)
                .monospacedDigit()
        }
    }
}

/// How far through the time it is.
struct TimerProgress: View {
    let state: TimerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if state.isOver(stale: isStale) {
            ProgressView(value: 1)
                .accessibilityHidden(true)
        } else if state.phase == .running {
            ProgressView(timerInterval: state.interval, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .accessibilityHidden(true)
        } else {
            ProgressView(value: state.fractionDone)
                .accessibilityHidden(true)
        }
    }
}

/// The line under the bar: where things stand, in words, and what follows.
struct TimerCaption: View {
    let state: TimerActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Text(state.caption(stale: isStale))
            .lineLimit(2)
    }
}

extension TimerActivityAttributes.Kind {
    var symbol: String {
        switch self {
        case .exposure: return "timer"
        case .development: return "flask"
        }
    }

    var spokenName: String {
        switch self {
        case .exposure: return "Exposure timer"
        case .development: return "Development timer"
        }
    }
}
