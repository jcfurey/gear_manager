//
//  AppNavigation.swift
//  ShutterManager
//
//  The selected tab and the Tools tab's stack, so one screen can open another in a different tab:
//  the light meter sends its reading to the ND calculator this way.
//

import SwiftUI

enum AppTab: Hashable {
    case inventory, tools, lightMeter, shoots, settings
}

@MainActor @Observable
final class AppNavigation {
    var tab: AppTab = .inventory
    /// The Tools tab's navigation stack.
    var toolsPath = NavigationPath()

    /// Switches to the Tools tab with `tool` open.
    func open(_ tool: Tool) {
        toolsPath = NavigationPath([tool])
        tab = .tools
    }
}
