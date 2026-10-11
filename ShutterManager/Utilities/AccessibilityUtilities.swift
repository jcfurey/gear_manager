//
//  AccessibilityUtilities.swift
//  ShutterManager
//

import SwiftUI

/// Accessibility utilities for VoiceOver, Dynamic Type, and improved user experience
struct AccessibilityUtilities {
    
    // MARK: - Touch Target Sizes
    
    /// Minimum recommended touch target size (44x44 points)
    static let minimumTouchTarget: CGFloat = 44
    
    /// Comfortable touch target size (48x48 points)
    static let comfortableTouchTarget: CGFloat = 48
    
    /// Large touch target for primary actions (56x56 points)
    static let largeTouchTarget: CGFloat = 56
    
    // MARK: - Dynamic Type Categories
    
    /// Check if user is using accessibility text sizes
    static var isAccessibilitySize: Bool {
        UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
    }
    
    /// Current content size category
    static var contentSizeCategory: UIContentSizeCategory {
        UIApplication.shared.preferredContentSizeCategory
    }
}

// MARK: - View Extensions

extension View {
    
    // MARK: - Accessibility Labels
    
    /// Add comprehensive accessibility support to buttons
    func accessibleButton(
        label: String,
        hint: String? = nil,
        value: String? = nil
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(.isButton)
    }
    
    /// Add accessibility support to toggles
    func accessibleToggle(
        label: String,
        isOn: Bool,
        hint: String? = nil
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }
    
    /// Add accessibility support to images
    func accessibleImage(
        label: String,
        isDecorative: Bool = false
    ) -> some View {
        if isDecorative {
            return self.accessibilityHidden(true)
        } else {
            return self
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)
        }
    }
    
    /// Mark a view as an accessibility heading at the given level (for VoiceOver
    /// rotor navigation). Maps the app's `AccessibilityHeadingLevel` onto SwiftUI's.
    func accessibleHeading(level: AccessibilityHeadingLevel = .h2) -> some View {
        let swiftUILevel: SwiftUI.AccessibilityHeadingLevel
        switch level {
        case .h1: swiftUILevel = .h1
        case .h2: swiftUILevel = .h2
        case .h3: swiftUILevel = .h3
        case .h4: swiftUILevel = .h4
        }
        return self
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(swiftUILevel)
    }
    
    // MARK: - Touch Targets
    
    /// Ensure minimum touch target size
    func minimumTouchTarget() -> some View {
        self.frame(
            minWidth: AccessibilityUtilities.minimumTouchTarget,
            minHeight: AccessibilityUtilities.minimumTouchTarget
        )
    }
    
    /// Apply comfortable touch target size
    func comfortableTouchTarget() -> some View {
        self.frame(
            minWidth: AccessibilityUtilities.comfortableTouchTarget,
            minHeight: AccessibilityUtilities.comfortableTouchTarget
        )
    }
    
    /// Apply large touch target for primary actions
    func largeTouchTarget() -> some View {
        self.frame(
            minWidth: AccessibilityUtilities.largeTouchTarget,
            minHeight: AccessibilityUtilities.largeTouchTarget
        )
    }
    
    // MARK: - Dynamic Type
    
    /// Applies `font` and caps Dynamic Type growth at `.accessibility3` so very large
    /// accessibility sizes can't break fixed layouts.
    func scaledFont(_ font: Font) -> some View {
        self.font(font)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
    
    /// Apply accessibility-friendly line limit
    func accessibleLineLimit() -> some View {
        self.lineLimit(AccessibilityUtilities.isAccessibilitySize ? nil : 2)
    }
    
    // MARK: - VoiceOver Groups
    
    /// Group elements for VoiceOver navigation. Without a label the children's combined label is
    /// kept (an empty `accessibilityLabel` would replace it with nothing).
    @ViewBuilder
    func voiceOverGroup(label: String? = nil) -> some View {
        if let label {
            self
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
        } else {
            self.accessibilityElement(children: .combine)
        }
    }
    
    /// Create separate VoiceOver elements
    func voiceOverSeparate() -> some View {
        self.accessibilityElement(children: .contain)
    }
    
    // MARK: - Status Indicators
    
    /// Add accessibility status update (for success/error messages)
    func accessibilityStatusUpdate(_ message: String, type: AccessibilityNotification = .announcement) -> some View {
        self.onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIAccessibility.post(notification: type.notification, argument: message)
            }
        }
    }
}

// MARK: - Accessibility Notification Type

enum AccessibilityNotification {
    case announcement
    case screenChanged
    case layoutChanged
    
    var notification: UIAccessibility.Notification {
        switch self {
        case .announcement: return .announcement
        case .screenChanged: return .screenChanged
        case .layoutChanged: return .layoutChanged
        }
    }
}

// MARK: - Accessibility Heading Level

enum AccessibilityHeadingLevel {
    case h1, h2, h3, h4
}

// MARK: - Common Accessibility Patterns

extension View {
    
    /// Standard pattern for list items with actions
    func accessibleListItem(
        title: String,
        description: String? = nil,
        actions: [String] = []
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityHint(description ?? "")
            .accessibilityActions {
                ForEach(actions, id: \.self) { action in
                    Button(action) { }
                }
            }
    }
    
    /// Pattern for progress indicators
    func accessibleProgress(
        label: String,
        value: Double,
        range: ClosedRange<Double> = 0...1
    ) -> some View {
        // Guard divide-by-zero (upperBound == 0) and non-finite input — Int(NaN/Inf) traps.
        let upper = range.upperBound
        let ratio = (upper != 0 && value.isFinite) ? value / upper : 0
        let percent = Int((max(0, min(1, ratio)) * 100).rounded())
        return self
            .accessibilityLabel(label)
            .accessibilityValue("\(percent)%")
    }
    
    /// Pattern for star ratings
    func accessibleRating(
        label: String,
        rating: Int,
        outOf maximum: Int = 5
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityValue("\(rating) out of \(maximum) stars")
    }
}

// MARK: - VoiceOver Utilities

struct VoiceOverUtilities {
    /// Check if VoiceOver is currently running
    static var isVoiceOverRunning: Bool {
        UIAccessibility.isVoiceOverRunning
    }
    
    /// Post announcement to VoiceOver
    static func announce(_ message: String) {
        guard isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
    
    /// Announce screen change
    static func announceScreenChange(_ element: Any? = nil) {
        UIAccessibility.post(notification: .screenChanged, argument: element)
    }
    
    /// Announce layout change
    static func announceLayoutChange(_ element: Any? = nil) {
        UIAccessibility.post(notification: .layoutChanged, argument: element)
    }
}

// MARK: - Accessibility Test Helpers

#if DEBUG
extension View {
    /// Show accessibility information overlay (debug only)
    func showAccessibilityInfo() -> some View {
        self.overlay(alignment: .topTrailing) {
            if AccessibilityUtilities.isAccessibilitySize {
                Text("A11Y")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // Touch targets
            Group {
                Text("Touch Targets")
                    .font(.headline)
                    .accessibleHeading()
                
                HStack(spacing: 20) {
                    Button("Min") {}
                        .minimumTouchTarget()
                        .background(Color.blue)
                        .clipShape(Circle())
                        .accessibleButton(label: "Minimum touch target")
                    
                    Button("Comfortable") {}
                        .comfortableTouchTarget()
                        .background(Color.green)
                        .clipShape(Circle())
                        .accessibleButton(label: "Comfortable touch target")
                    
                    Button("Large") {}
                        .largeTouchTarget()
                        .background(Color.orange)
                        .clipShape(Circle())
                        .accessibleButton(label: "Large touch target")
                }
            }
            
            // Toggle example
            Toggle("Settings Toggle", isOn: .constant(true))
                .accessibleToggle(
                    label: "Enable notifications",
                    isOn: true,
                    hint: "Double tap to toggle"
                )
            
            // Progress example
            ProgressView(value: 0.7)
                .accessibleProgress(label: "Upload progress", value: 0.7)
            
            // List item example
            HStack {
                Image(systemName: "camera")
                    .accessibleImage(label: "Camera icon")
                VStack(alignment: .leading) {
                    Text("Camera Body")
                    Text("42,180 actuations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibleListItem(
                title: "Camera Body",
                description: "42,180 actuations",
                actions: ["Edit", "Delete"]
            )
        }
        .padding()
    }
}
