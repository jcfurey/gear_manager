//
//  SettingsRow.swift
//  ShutterManager
//
//  Reusable settings list row with SF Symbol icon, title, and generic trailing content.
//  Replaces the repeated HStack boilerplate throughout SettingsView.
//

import SwiftUI

/// A single settings list row: SF Symbol icon on the left, a title, and
/// an optional trailing view on the right (Picker, Toggle, Text, etc.).
struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let titleColor: Color
    let constants: ResponsiveConstants
    @ViewBuilder let trailing: () -> Trailing

    init(
        icon: String,
        iconColor: Color,
        title: String,
        titleColor: Color = .primary,
        constants: ResponsiveConstants,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.titleColor = titleColor
        self.constants = constants
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: constants.itemSpacing) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: constants.iconSize))
                .frame(width: constants.iconSize)
            Text(title)
                .font(constants.bodyFont)
                .foregroundColor(titleColor)
            Spacer()
            trailing()
        }
        .padding(.vertical, constants.itemSpacing / 4)
    }
}

/// Convenience initializer for rows with no trailing content (e.g. NavigationLink labels).
extension SettingsRow where Trailing == EmptyView {
    init(
        icon: String,
        iconColor: Color,
        title: String,
        titleColor: Color = .primary,
        constants: ResponsiveConstants
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            title: title,
            titleColor: titleColor,
            constants: constants
        ) {
            EmptyView()
        }
    }
}
