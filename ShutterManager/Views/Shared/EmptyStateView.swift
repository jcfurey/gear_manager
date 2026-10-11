//
//  EmptyStateView.swift
//  ShutterManager
//
//  Shared empty-state placeholder and the app's predefined empty states.
//

import SwiftUI

/// Empty-state placeholder: icon, title, description, and an optional action button.
/// Use the static factories below for the app's predefined empty states.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        icon: String,
        title: String,
        description: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
                .accessibilityHidden(true)   // decorative; VoiceOver otherwise reads the symbol name
            
            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            // Description
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Action Button
            if let actionTitle = actionTitle, let action = action {
                Button(action: {
                    HapticFeedbackManager.shared.buttonTap()
                    action()
                }) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Predefined Empty States

extension EmptyStateView {
    
    // MARK: - Inventory Empty States

    static func noGearItems(action: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "camera",
            title: "No Gear Yet",
            description: "Add your first camera, lens or accessory to start your inventory.",
            actionTitle: "Add Gear",
            action: action
        )
    }

    static func noMaintenanceRecords() -> EmptyStateView {
        EmptyStateView(
            icon: "wrench.and.screwdriver",
            title: "No Maintenance History",
            description: "Log sensor cleanings, firmware updates and repairs to keep a service history.",
            actionTitle: nil,
            action: nil
        )
    }

    static func noPhotos() -> EmptyStateView {
        EmptyStateView(
            icon: "photo.on.rectangle.angled",
            title: "No Photos",
            description: "Add photos of your gear, its serial number and its condition.",
            actionTitle: nil,
            action: nil
        )
    }

    // MARK: - Settings Empty States
    
    static func noBackups() -> EmptyStateView {
        EmptyStateView(
            icon: "externaldrive",
            title: "No Backups",
            description: "Create backups to protect your data and enable easy restoration if needed.",
            actionTitle: nil,
            action: nil
        )
    }
    
    // MARK: - Search Empty States
    
    static func noSearchResults(searchTerm: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            description: "No items match '\(searchTerm)'. Try adjusting your search or filters.",
            actionTitle: nil,
            action: nil
        )
    }
    
    // MARK: - Generic Empty State
    
    static func generic(
        icon: String = "tray",
        title: String = "Nothing Here Yet",
        description: String = "Add items to get started."
    ) -> EmptyStateView {
        EmptyStateView(
            icon: icon,
            title: title,
            description: description,
            actionTitle: nil,
            action: nil
        )
    }
}

// MARK: - Preview

#Preview("No Gear Items") {
    EmptyStateView.noGearItems { }
}

#Preview("No Search Results") {
    EmptyStateView.noSearchResults(searchTerm: "Leica")
}

#Preview("Generic") {
    EmptyStateView.generic()
}
