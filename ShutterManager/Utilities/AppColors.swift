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

    // MARK: - Status Text

    // Status colors for text, each a system color darkened for light mode, or lightened for dark
    // mode, until it reads at 4.8:1 or better on a card or grouped background. Plain system red,
    // orange and green are 2.2 to 3.6:1 on white: fine for icons and fills, not for words.

    /// Done, saved, gained.
    static let goodText = adaptive(light: 0x207936, dark: 0x30D158)
    /// Due soon, needs attention.
    static let warningText = adaptive(light: 0x9C5B00, dark: 0xFF9F0A)
    /// Overdue, failed, lost value.
    static let badText = adaptive(light: 0xC92F26, dark: 0xFF655B)
    /// Neutral status, such as a loan that isn't due yet.
    static let infoText = adaptive(light: 0x0066D6, dark: 0x399BFF)

    // MARK: - Gear Categories

    /// A distinct accent color per gear category, so categories read at a glance in the
    /// inventory list and grid. The single source of truth for category color.
    ///
    /// Each is a system color darkened for light mode, or lightened for dark mode, until text in
    /// it reaches 4.8:1 against a card and against the category chip's tint (WCAG AA asks for
    /// 4.5:1). Plain system yellow, for one, is barely readable on white.
    static func category(_ category: GearCategory) -> Color {
        let (light, dark): (UInt32, UInt32) = switch category {
        case .cameraBody: (0x005FC7, 0x3B9DFF)   // blue
        case .lens: (0x5453CD, 0x9392EE)         // indigo
        case .lighting: (0x786000, 0xFFD60A)     // yellow
        case .support: (0x766045, 0xB29673)      // brown
        case .filter: (0x8A41AF, 0xCB78F4)       // purple
        case .drone: (0x1E6A8C, 0x64D2FF)        // cyan
        case .audio: (0xBA213E, 0xFF6382)        // pink
        case .power: (0x1E7133, 0x30D158)        // green
        case .memoryCard: (0x915500, 0xFF9F0A)   // orange
        case .bag: (0x006F6A, 0x63E6E2)          // mint
        case .accessory: (0x1D6B79, 0x40C8E0)    // teal
        case .other: (0x636367, 0x9C9CA0)        // gray
        }
        return adaptive(light: light, dark: dark)
    }

    /// `light` in light mode and `dark` in dark mode, each written 0xRRGGBB.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in rgbColor(traits.userInterfaceStyle == .dark ? dark : light) })
    }

    private static func rgbColor(_ rgb: UInt32) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
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
