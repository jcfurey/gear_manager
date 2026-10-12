//
//  ChartEmptyState.swift
//  ShutterManager
//
//  Shared placeholder for an empty chart card — a centered icon, title, and hint sized to the
//  chart's area, so every chart's "no data yet" state looks the same.
//

import SwiftUI

/// Compact, centered empty state for a chart card. Sized to roughly fill a chart's height so the
/// card doesn't collapse when there's no data. Purely presentational.
struct ChartEmptyState: View {
    let icon: String
    let title: String
    let message: String
    /// Matches the host chart's height so the empty and populated states occupy the same space.
    var height: CGFloat = 200

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)   // decorative; VoiceOver otherwise reads the symbol name
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .padding()
    }
}

#Preview {
    ChartEmptyState(icon: "chart.xyaxis.line", title: "No Readings Yet",
                    message: "Add a shutter count to start the chart.")
        .padding()
}
