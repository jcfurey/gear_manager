//
//  ResponsiveDesign.swift
//  ShutterManager
//
//  Responsive design system. From a view's GeometryProxy it derives a 4-tier device size
//  and orientation, then exposes `ResponsiveConstants`: spacing, sizing, grid columns, and
//  Dynamic Type–aware fonts/heights (scaled by accessibilityScale). Image thumbnails stay fixed.
//  Inject once per top-level view via `.injectResponsive(_:)`; descendants read
//  `@Environment(\.responsive)`.
//

import SwiftUI

// MARK: - Device Size Detection (Hardware Classification)

/// Device size classification for responsive design decisions.
/// Categorizes devices into logical groups for appropriate UI scaling.
///
/// Note: classification is derived from the view container's GeometryProxy, not the physical
/// screen. On iPad with split-view or Stage Manager the container can be narrower than the
/// full display, so `.extraLarge` may not be reached in those configurations — sizing will
/// still adapt correctly because the geometry already reflects the constrained window.
enum DeviceSize {
    // Supported range spans iPhone 8 (the oldest target) through every iPad. Classification
    // is by the container's min (portrait-width) dimension, so it adapts to any current or
    // future model that falls in these width bands.
    case compact    // iPhone 8/SE (375pt), iPhone 12/13 mini (360pt)
    case regular    // iPhone 12–16 (390–393pt)
    case large      // iPhone 8 Plus (414pt), Plus / Pro Max (428–440pt)
    case extraLarge // iPad mini (744pt) through iPad Pro 12.9" (1024pt)

    /// Determine device size category from geometry proxy dimensions.
    /// Uses minimum dimension (portrait width) for consistent classification.
    ///
    /// - Parameter geometry: SwiftUI GeometryProxy providing current view dimensions
    /// - Returns: Appropriate DeviceSize category for responsive design decisions
    static func current(_ geometry: GeometryProxy) -> DeviceSize {
        let minDimension = min(geometry.size.width, geometry.size.height)

        if minDimension > 700 {
            return .extraLarge
        }
        if minDimension <= 375 {        // iPhone SE (375), 12 mini (360)
            return .compact
        } else if minDimension <= 393 { // iPhone 14 (390), iPhone 15 (393)
            return .regular
        } else {                        // iPhone 14 Plus (428), 15 Pro Max (430)
            return .large
        }
    }
}

/// Device orientation classification for layout optimization.
enum DeviceOrientation {
    case portrait
    case landscape

    static func current(_ geometry: GeometryProxy) -> DeviceOrientation {
        geometry.size.width > geometry.size.height ? .landscape : .portrait
    }
}

// MARK: - Responsive Design System

/// Device- and Dynamic Type–aware sizing, spacing, and font values. Derived once from a
/// GeometryProxy (and the current Dynamic Type size) and read throughout a view tree.
struct ResponsiveConstants {
    let deviceSize: DeviceSize
    let orientation: DeviceOrientation
    let dynamicTypeSize: DynamicTypeSize
    /// The container's point size (from the originating GeometryProxy). Lets size classes that
    /// span a wide hardware range — chiefly iPad — scale continuously with the actual screen
    /// instead of snapping to one fixed value per tier. `.zero` for the environment default.
    let containerSize: CGSize
    /// Semantic size classes, when supplied by the caller. These are the multitasking-safe signal
    /// for "how much room do I actually have" — under Split View / Stage Manager the window can be
    /// far smaller than the physical device, and the size class reflects that where a raw point
    /// threshold would not. `nil` when a caller builds constants without them (callers then fall
    /// back to the geometry-derived tier).
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?

    init(_ geometry: GeometryProxy,
         dynamicTypeSize: DynamicTypeSize = .large,
         horizontalSizeClass: UserInterfaceSizeClass? = nil,
         verticalSizeClass: UserInterfaceSizeClass? = nil) {
        self.deviceSize = DeviceSize.current(geometry)
        self.orientation = DeviceOrientation.current(geometry)
        self.dynamicTypeSize = dynamicTypeSize
        self.containerSize = geometry.size
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
    }

    /// Default instance — iPhone 14 (regular) portrait at the standard Dynamic Type size.
    /// Used as the SwiftUI environment default before a GeometryReader injects real values.
    init() {
        self.deviceSize = .regular
        self.orientation = .portrait
        self.dynamicTypeSize = .large
        self.containerSize = .zero
        self.horizontalSizeClass = nil
        self.verticalSizeClass = nil
    }

    // MARK: - Dynamic Type Scale

    /// Multiplier derived from the user's preferred text size setting.
    /// Applied to all font base sizes so typography scales with accessibility preferences.
    private var accessibilityScale: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:         return 0.82
        case .small:          return 0.88
        case .medium:         return 0.94
        case .large:          return 1.00
        case .xLarge:         return 1.12
        case .xxLarge:        return 1.24
        case .xxxLarge:       return 1.35
        case .accessibility1: return 1.59
        case .accessibility2: return 1.88
        case .accessibility3: return 2.06
        case .accessibility4: return 2.35
        case .accessibility5: return 2.82
        @unknown default:     return 1.00
        }
    }

    // MARK: - Spacing

    var sectionSpacing: CGFloat {
        switch deviceSize {
        case .compact: return 12
        case .regular: return 16
        case .large: return 20
        case .extraLarge: return 24
        }
    }

    var itemSpacing: CGFloat {
        switch deviceSize {
        case .compact: return 8
        case .regular: return 12
        case .large: return 16
        case .extraLarge: return 20
        }
    }

    var padding: CGFloat {
        switch deviceSize {
        case .compact: return 16
        case .regular: return 20
        case .large: return 24
        case .extraLarge: return 32
        }
    }

    var cornerRadius: CGFloat {
        switch deviceSize {
        case .compact: return 8
        case .regular: return 10
        case .large: return 12
        case .extraLarge: return 16
        }
    }

    var lineSpacing: CGFloat {
        switch deviceSize {
        case .compact: return 2
        case .regular: return 4
        case .large: return 5
        case .extraLarge: return 6
        }
    }

    // MARK: - Typography (Font — Dynamic Type aware)

    /// Large monospaced display font for big readouts (64–96pt base).
    var largeTitleFont: Font {
        let base: CGFloat = switch deviceSize {
        case .compact:    64
        case .regular:    72
        case .large:      80
        case .extraLarge: 96
        }
        return .system(size: base * accessibilityScale, weight: .bold, design: .monospaced)
    }

    /// Display-scale font (~36–48pt base). For prominent numeric or value displays.
    var displayFont: Font {
        let base: CGFloat = switch deviceSize {
        case .compact:    30
        case .regular:    36
        case .large:      42
        case .extraLarge: 48
        }
        return .system(size: base * accessibilityScale)
    }

    /// Section-heading font (20–32pt base).
    var titleFont: Font {
        let base: CGFloat = switch deviceSize {
        case .compact:    20
        case .regular:    24
        case .large:      28
        case .extraLarge: 32
        }
        return .system(size: base * accessibilityScale)
    }

    /// Sub-heading font, 4pt below titleFont (16–28pt base).
    var subtitleFont: Font {
        let base: CGFloat = switch deviceSize {
        case .compact:    16
        case .regular:    20
        case .large:      24
        case .extraLarge: 28
        }
        return .system(size: base * accessibilityScale)
    }

    /// Standard body font (14–20pt base).
    var bodyFont: Font {
        let base: CGFloat = switch deviceSize {
        case .compact:    14
        case .regular:    16
        case .large:      18
        case .extraLarge: 20
        }
        return .system(size: base * accessibilityScale)
    }

    /// Secondary / caption font, 2pt below bodyFont (12–18pt base).
    var captionFont: Font {
        let base: CGFloat = switch deviceSize {
        case .compact:    12
        case .regular:    14
        case .large:      16
        case .extraLarge: 18
        }
        return .system(size: base * accessibilityScale)
    }

    /// Tertiary / footnote font, 4pt below bodyFont (10–16pt base).
    var footnoteFont: Font {
        let base: CGFloat = switch deviceSize {
        case .compact:    10
        case .regular:    12
        case .large:      14
        case .extraLarge: 16
        }
        return .system(size: base * accessibilityScale)
    }

    // MARK: - Line Heights (CGFloat — for frame calculations only)
    //
    // These scale with Dynamic Type (× accessibilityScale) so that fixed-height containers
    // built from them grow in lock-step with the (also-scaled) fonts. Without this, large
    // accessibility text sizes overflow/clip their reserved frames.

    /// Approximate single-line height for body-sized text. Use for frame(height:) calculations,
    /// not for font assignment — use bodyFont for that.
    var bodyLineHeight: CGFloat {
        let base: CGFloat = switch deviceSize {
        case .compact:    14
        case .regular:    16
        case .large:      18
        case .extraLarge: 20
        }
        return base * accessibilityScale
    }

    /// Approximate single-line height for title-sized text. Use for frame(height:) calculations,
    /// not for font assignment — use titleFont for that.
    var titleLineHeight: CGFloat {
        let base: CGFloat = switch deviceSize {
        case .compact:    20
        case .regular:    24
        case .large:      28
        case .extraLarge: 32
        }
        return base * accessibilityScale
    }

    // MARK: - Component Sizing

    var buttonHeight: CGFloat {
        let base: CGFloat = switch deviceSize {
        case .compact:    44
        case .regular:    50
        case .large:      56
        case .extraLarge: 64
        }
        // Scale with Dynamic Type (the label inside scales too); never below the 44pt
        // minimum tap target.
        return max(minTapTarget, base * accessibilityScale)
    }

    var cardHeight: CGFloat {
        let base: CGFloat = switch deviceSize {
        case .compact:    100
        case .regular:    120
        case .large:      140
        case .extraLarge: 160
        }
        return base * accessibilityScale
    }

    /// Icon size for glyphs shown alongside text — scales with Dynamic Type so icons track
    /// the text they sit next to.
    var iconSize: CGFloat {
        let base: CGFloat = switch deviceSize {
        case .compact:    20
        case .regular:    24
        case .large:      28
        case .extraLarge: 32
        }
        return base * accessibilityScale
    }

    /// Image thumbnail edge length. Not text, so it does NOT scale with Dynamic Type.
    var thumbnailSize: CGFloat {
        switch deviceSize {
        case .compact:    return 60
        case .regular:    return 80
        case .large:      return 96
        case .extraLarge: return 120
        }
    }

    // MARK: - Adaptive layout signals (multitasking-safe)

    /// Whether the container is a roomy, regular-width canvas worth capping and centering content
    /// in (iPad, wide multitasking windows, large phones in landscape). Prefers the semantic size
    /// class — correct under Split View / Stage Manager where the window can be far smaller than
    /// the device — and falls back to the geometry-derived tier when no size class was supplied.
    var isRegularWidth: Bool {
        if let horizontalSizeClass { return horizontalSizeClass == .regular }
        return deviceSize == .extraLarge
    }

    /// Roomy in BOTH axes — an iPad or a large window, not a short landscape phone. Decides whether
    /// to center content vertically (room to spare) rather than top-anchor it with a gap.
    var hasAmpleCanvas: Bool {
        guard isRegularWidth else { return false }
        if let verticalSizeClass { return verticalSizeClass == .regular }
        return deviceSize == .extraLarge
    }

    // MARK: - Layout

    var maxContentWidth: CGFloat {
        // Cap (and let callers center) on a regular-width canvas; fill the width on compact
        // phones/windows. With no size class supplied this matches the old per-tier behavior
        // exactly (isRegularWidth falls back to `deviceSize == .extraLarge`).
        isRegularWidth ? 800 : .infinity
    }

    var gridColumns: Int {
        switch (deviceSize, orientation) {
        case (.extraLarge, .landscape): return 3
        case (.extraLarge, .portrait):  return 2
        case (.large, _):               return 2
        case (.regular, .landscape):    return 2
        default:                        return 1
        }
    }

    var shouldUseCompactLayout: Bool {
        deviceSize == .compact || (deviceSize == .regular && orientation == .landscape)
    }

    var headerHeight: CGFloat {
        let base: CGFloat = switch deviceSize {
        case .compact:    44
        case .regular:    52
        case .large:      60
        case .extraLarge: 72
        }
        return base * accessibilityScale
    }

    // MARK: - Accessibility

    /// Minimum recommended touch target size per Human Interface Guidelines.
    /// Constant across all device sizes.
    var minTapTarget: CGFloat { 44 }
}

// MARK: - Environment

private struct ResponsiveKey: EnvironmentKey {
    static var defaultValue = ResponsiveConstants()
}

extension EnvironmentValues {
    var responsive: ResponsiveConstants {
        get { self[ResponsiveKey.self] }
        set { self[ResponsiveKey.self] = newValue }
    }
}

// MARK: - Environment Injection

private struct InjectResponsiveModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let geometry: GeometryProxy

    func body(content: Content) -> some View {
        content
            .environment(\.responsive, ResponsiveConstants(geometry, dynamicTypeSize: dynamicTypeSize))
    }
}

extension View {
    /// Injects device size, orientation, and Dynamic Type size into the environment as
    /// `ResponsiveConstants`. Call once inside a `GeometryReader` at the root of each
    /// top-level view; descendant views read `@Environment(\.responsive)` without needing
    /// their own `GeometryReader` or a `constants` parameter.
    func injectResponsive(_ geometry: GeometryProxy) -> some View {
        modifier(InjectResponsiveModifier(geometry: geometry))
    }
}

// MARK: - Responsive Layout Container

struct ResponsiveVStack<Content: View>: View {
    let geometry: GeometryProxy
    let alignment: HorizontalAlignment
    let content: () -> Content

    init(
        geometry: GeometryProxy,
        alignment: HorizontalAlignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.geometry = geometry
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        VStack(alignment: alignment, spacing: ResponsiveConstants(geometry).sectionSpacing) {
            content()
        }
    }
}

// MARK: - Safe Area Handling

extension GeometryProxy {
    var responsiveSafeAreaInsets: EdgeInsets {
        safeAreaInsets
    }

    var isLandscape: Bool {
        size.width > size.height
    }

    var isCompact: Bool {
        size.width <= 375
    }
}
