//
//  AppColors.swift
//  ShutterManager
//

import SwiftUI

/// Centralized color system with full dark mode support
/// Ensures consistent colors across the app with proper dark mode adaptation
struct AppColors {

    // MARK: - Brand Colors

    /// Primary accent color (adapts to dark mode)
    static let accent = Color.accentColor

    /// Primary brand color
    static let primary = Color.blue

    /// Secondary brand color
    static let secondary = Color.purple

    // MARK: - Background Colors

    /// Primary background (system grouped background)
    static let background = Color(.systemGroupedBackground)

    /// Secondary background for cards and sections
    static let secondaryBackground = Color(.secondarySystemGroupedBackground)

    /// Tertiary background for nested elements
    static let tertiaryBackground = Color(.tertiarySystemGroupedBackground)

    // MARK: - Text Colors

    /// Primary text color
    static let text = Color.primary

    /// Secondary text color (descriptions, labels)
    static let textSecondary = Color.secondary

    /// Tertiary text color (captions, placeholders)
    static let textTertiary = Color(.tertiaryLabel)

    // MARK: - Semantic Colors

    /// Success color (checkmarks, confirmations)
    static let success = Color.green

    /// Error color (alerts, failures)
    static let error = Color.red

    /// Warning color (cautions)
    static let warning = Color.orange

    /// Info color (information, tips)
    static let info = Color.blue

    // MARK: - Gear Categories

    /// A distinct accent color per gear category, so categories read at a glance in the
    /// inventory list and grid. The single source of truth for category color.
    static func category(_ category: GearCategory) -> Color {
        switch category {
        case .cameraBody: return .blue
        case .lens: return .indigo
        case .lighting: return .yellow
        case .support: return .brown
        case .filter: return .purple
        case .drone: return .cyan
        case .audio: return .pink
        case .power: return .green
        case .memoryCard: return .orange
        case .bag: return .mint
        case .accessory: return .teal
        case .other: return .gray
        }
    }

    // MARK: - UI Element Colors

    /// Separator/divider color
    static let separator = Color(.separator)

    /// Border color for inputs and cards
    static let border = Color(.separator)

    /// Shadow color (adapts opacity for dark mode)
    static let shadow = Color.black.opacity(0.1)

    /// Overlay background for modals
    static let overlay = Color.black.opacity(0.3)

    /// Card background with slight elevation
    static let card = Color(.secondarySystemGroupedBackground)

    // MARK: - Chart Colors

    /// Chart color palette (diverse, accessible colors)
    static let chartColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint
    ]

    /// Get chart color by index with wrapping
    static func chartColor(at index: Int) -> Color {
        // Swift's % keeps the dividend's sign, so a negative index would go out of bounds.
        // Normalize into [0, count) before subscripting.
        let count = chartColors.count
        return chartColors[((index % count) + count) % count]
    }

    // MARK: - Gradient Colors

    /// Primary gradient for headers and highlights
    static let primaryGradient = LinearGradient(
        colors: [Color.blue, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Success gradient
    static let successGradient = LinearGradient(
        colors: [Color.green, Color.mint],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Error gradient
    static let errorGradient = LinearGradient(
        colors: [Color.red, Color.orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Adaptive Colors

    /// Returns appropriate color based on dark mode
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Color Extensions

extension Color {
    /// Reduces opacity by `percentage` (0.0–1.0). Named "lighter" because over a light
    /// background lowering opacity reads as lighter — it does not adjust hue/brightness.
    func lighter(by percentage: Double = 0.3) -> Color {
        self.opacity(1.0 - percentage)
    }

    /// Sets opacity to `percentage` (0.0–1.0). A fade, not a true brightness change.
    func darker(by percentage: Double = 0.3) -> Color {
        self.opacity(percentage)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // Background colors
            Group {
                Text("Background Colors")
                    .font(.headline)

                HStack(spacing: 10) {
                    ColorSwatch(color: AppColors.background, name: "Background")
                    ColorSwatch(color: AppColors.secondaryBackground, name: "Secondary")
                    ColorSwatch(color: AppColors.tertiaryBackground, name: "Tertiary")
                }
            }

            // Text colors
            Group {
                Text("Text Colors")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Primary Text").foregroundStyle(AppColors.text)
                    Text("Secondary Text").foregroundStyle(AppColors.textSecondary)
                    Text("Tertiary Text").foregroundStyle(AppColors.textTertiary)
                }
            }

            // Semantic colors
            Group {
                Text("Semantic Colors")
                    .font(.headline)

                HStack(spacing: 10) {
                    ColorSwatch(color: AppColors.success, name: "Success")
                    ColorSwatch(color: AppColors.error, name: "Error")
                    ColorSwatch(color: AppColors.warning, name: "Warning")
                    ColorSwatch(color: AppColors.info, name: "Info")
                }
            }

            // Category colors
            Group {
                Text("Category Colors")
                    .font(.headline)

                HStack(spacing: 10) {
                    ForEach([GearCategory.cameraBody, .lens, .lighting, .support]) { category in
                        ColorSwatch(color: AppColors.category(category), name: category.displayName)
                    }
                }
            }

            // Chart colors
            Group {
                Text("Chart Colors")
                    .font(.headline)

                HStack(spacing: 5) {
                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .fill(AppColors.chartColor(at: index))
                            .frame(width: 30, height: 30)
                    }
                }
            }
        }
        .padding()
    }
    .background(AppColors.background)
}

struct ColorSwatch: View {
    let color: Color
    let name: String

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 80, height: 80)

            Text(name)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
