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
    /// Goes up each time the whole library is replaced (a restore, an import, Clear All Data).
    /// The tabs that show records are rebuilt for each value, back at their first screens: a
    /// detail screen left open on another tab would otherwise go on showing a deleted record.
    private(set) var libraryGeneration = 0

    /// A QR label opened from outside the app (the Camera app follows a label's link here),
    /// shown over whichever tab is up.
    var openedLabel: LabelLink?

    /// Opens the label `url` points at. Returns false for a link that isn't one of the app's labels.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = LabelLink(url: url) else { return false }
        openedLabel = link
        return true
    }

    /// Call after the library has been replaced.
    func libraryWasReplaced() {
        libraryGeneration += 1
        toolsPath = NavigationPath()
        openedLabel = nil
    }

    /// Switches to the Tools tab with `tool` open.
    func open(_ tool: Tool) {
        toolsPath = NavigationPath([tool])
        tab = .tools
    }
}
