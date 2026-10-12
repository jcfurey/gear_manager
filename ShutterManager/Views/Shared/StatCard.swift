//
//  StatCard.swift
//  ShutterManager
//

import SwiftUI

/// Reusable statistic card: title (secondary), prominent colored value, and subtitle.
/// Used across practice analytics, the collection overview, and market dashboards.
/// Pass `constants` to scale fonts/padding responsively; omit for fixed defaults.
struct StatCard: View {
    let title: String

    /// Main metric value, displayed prominently in `color`.
    let value: String

    let subtitle: String

    /// Accent color applied to the value text.
    let color: Color

    /// Responsive sizing; `nil` uses fixed defaults.
    var constants: ResponsiveConstants? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: constants?.itemSpacing ?? 8) {
            Text(title)
                .font(constants.map { c in c.bodyFont.weight(.medium) } ?? .subheadline.weight(.medium))
                .foregroundColor(.secondary)

            Text(value)
                .font(constants.map { c in c.titleFont.weight(.bold) } ?? .title2.weight(.bold))
                .foregroundColor(color)

            Text(subtitle)
                .font(constants.map { c in c.bodyFont } ?? .caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(constants?.padding ?? 16)
        .background(
            RoundedRectangle(cornerRadius: constants?.cornerRadius ?? 12)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack {
        StatCard(
            title: "Today",
            value: "1:23:45",
            subtitle: "3 sessions",
            color: .blue
        )
        
        StatCard(
            title: "This Week",
            value: "8:15:32",
            subtitle: "12 sessions",
            color: .green
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}
