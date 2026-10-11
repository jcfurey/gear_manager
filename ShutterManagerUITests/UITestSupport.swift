//
//  UITestSupport.swift
//  ShutterManagerUITests
//
//  Shared XCUITest helpers. The important one: locating and tapping tab-bar items in a way that
//  survives the iPadOS 26 floating ("Liquid Glass") tab bar, where each item is a
//  `_UIFloatingTabBarItemCell` exposed to XCUITest as a `.cell` (automation type 75) rather than a
//  `.button` inside a `.tabBar`. Tests that hard-coded `app.tabBars.buttons["…"]` matched nothing
//  on that layout and failed to navigate; everything funnels through `selectTab` instead.
//

import XCTest

extension XCUIApplication {
    /// The tab item with the given title, resilient to how the OS represents the tab bar.
    ///
    /// - Classic `UITabBar` (iPhone, iPadOS ≤ 18): items are `.button`s inside a `.tabBar`, so
    ///   `tabBars.buttons[title]` matches.
    /// - iPadOS 26 floating tab bar: there is no queryable `.tabBar`, and each item is a
    ///   `_UIFloatingTabBarItemCell` surfaced as a `.cell` — `tabBars.buttons[title]` matches
    ///   nothing, so we fall back to `cells[title]` (and then a plain `buttons[title]`).
    ///
    /// Matching is by accessibility label/identifier (the tab's title), which is stable across both
    /// layouts. Returns the first representation that currently resolves; if none do yet, returns the
    /// classic-tab-bar query so callers still get a usable (non-existent) element to wait/assert on.
    func tabBarItem(_ title: String) -> XCUIElement {
        // `.firstMatch` on each: the floating tab bar item matches as both a cell and a (nested)
        // button, so a bare query resolves to multiple elements and can't be tapped — see selectTab.
        let inTabBar = tabBars.buttons[title].firstMatch
        if inTabBar.exists { return inTabBar }
        let asCell = cells[title].firstMatch
        if asCell.exists { return asCell }
        let asButton = buttons[title].firstMatch
        if asButton.exists { return asButton }
        return inTabBar
    }

    /// Whether the app is showing a tab switcher we can drive (a classic tab bar or floating cells).
    var showsTabSwitcher: Bool {
        tabBars.firstMatch.exists || cells["Inventory"].exists
    }
}

extension XCTestCase {
    /// Tap a tab by its title, waiting for whichever representation the current OS uses (classic
    /// tab-bar button or floating-tab-bar cell). Fails the test (with file/line context) if no tab
    /// item resolves within `timeout`.
    ///
    /// - Returns: `true` once a tab item was tapped. Discardable — most call sites just navigate.
    @discardableResult
    func selectTab(_ title: String,
                   in app: XCUIApplication,
                   timeout: TimeInterval = 10,
                   file: StaticString = #file,
                   line: UInt = #line) -> Bool {
        // Each representation is resolved with `.firstMatch`: on the iPadOS 26 floating tab bar an
        // item is exposed as a cell that *also* computes (via legacy attributes) to a nested
        // button-in-button, so a bare `cells[title]` / `buttons[title]` query matches multiple
        // elements — `.tap()` then throws "Multiple matching elements found", and `.isHittable`
        // can't resolve. `.firstMatch` collapses each to a single element. Re-reading `.exists` on
        // these handles each loop is an instant snapshot query, so polling stays cheap.
        let candidates = [app.tabBars.buttons[title].firstMatch,
                          app.cells[title].firstMatch,
                          app.buttons[title].firstMatch]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let item = candidates.first(where: { $0.exists && $0.isHittable }) {
                item.tap()
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline

        // Last resort: a representation that exists but never reported hittable — try tapping it.
        if let existing = candidates.first(where: { $0.exists }) {
            existing.tap()
            return true
        }
        XCTFail("Could not find a tab labeled \"\(title)\" (checked tab-bar button, cell, and button).",
                file: file, line: line)
        return false
    }
}

extension XCTestCase {
    enum ScrollDirection { case up, down }

    /// Brings a control on screen; an absent control always fails.
    ///
    /// It waits briefly before scrolling: a control queried while a tab switch or push is still
    /// settling isn't hittable yet, and swiping then can carry one that was already on screen out
    /// of view. A control that exists is dragged toward the middle of the window by its measured
    /// distance, so a swipe can't overshoot it under a bar; one a lazy SwiftUI form hasn't built
    /// yet is looked for by swiping in `direction`.
    func reveal(_ element: XCUIElement, in app: XCUIApplication,
                direction: ScrollDirection = .up, maxSwipes: Int = 8,
                file: StaticString = #file, line: UInt = #line) {
        if waitUntilHittable(element, timeout: 2) { return }
        let window = app.windows.firstMatch
        for _ in 0..<maxSwipes {
            let frame = element.exists ? element.frame : .zero
            if frame.isEmpty {
                if direction == .up { app.swipeUp() } else { app.swipeDown() }
            } else {
                let bounds = window.frame
                // Clamped so the drag stays inside the window; the next pass measures again.
                let distance = max(-0.4 * bounds.height, min(0.4 * bounds.height, bounds.midY - frame.midY))
                if abs(distance) < bounds.height / 8 {
                    // Already mid-screen, so position isn't what's blocking it; give it a moment.
                    if waitUntilHittable(element, timeout: 1) { return }
                } else {
                    drag(window, by: distance)
                }
            }
            if element.exists && element.isHittable { return }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Required control is not visible: \(element)", file: file, line: line)
    }

    /// Scrolls whatever is under the middle of `window` by exactly `distance` points: a slow drag
    /// that holds at the end, so it has no momentum to carry past the target.
    private func drag(_ window: XCUIElement, by distance: CGFloat) {
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: distance))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    func replaceText(in field: XCUIElement, with text: String,
                     file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        // A tap that lands while a transition or scroll is still settling doesn't focus the field,
        // and typing then fails with "no keyboard focus". Tap again if the keyboard doesn't come up.
        // (With a hardware keyboard connected it never does; typing still works after the retry.)
        let keyboard = XCUIApplication().keyboards.firstMatch
        field.tap()
        if !keyboard.waitForExistence(timeout: 2) {
            field.tap()
            _ = keyboard.waitForExistence(timeout: 2)
        }
        let existing = field.value as? String ?? ""
        // Empty TextFields report their placeholder as their value.
        let count = existing == field.placeholderValue ? 0 : existing.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + text)
    }
}
