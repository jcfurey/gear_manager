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
                // A tap that lands while a sheet is still leaving doesn't switch tabs: on iPad the
                // Settings tab was tapped a second after Add Gear closed, and Settings never came.
                // Tap again until the tab is the one showing.
                for _ in 0..<2 where !isShowingTab(title, item: item, in: app, within: 2) {
                    if item.exists && item.isHittable { item.tap() }
                }
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

    /// Whether `title`'s tab comes up within `timeout`: its item reports being selected, or the
    /// bar of its first screen (titled as the tab is) is on screen.
    private func isShowingTab(_ title: String, item: XCUIElement, in app: XCUIApplication,
                              within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if (item.exists && item.isSelected) || app.navigationBars[title].exists { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
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

    /// Goes back one screen, to the one whose bar is titled `title`; an absent screen always fails.
    ///
    /// A back tap that lands while the push that brought this screen is still finishing is
    /// ignored. That's rare on a light screen, but the sun and moon planner with a place chosen
    /// takes long enough to settle that CI's iPhone lost one. So this taps again while this
    /// screen's back button is still there and the earlier screen hasn't come.
    func goBack(to title: String, in app: XCUIApplication,
                file: StaticString = #file, line: UInt = #line) {
        let destination = app.navigationBars[title]
        // Named, so a later try can't tap some other button once the earlier screen is back.
        let named = app.navigationBars.buttons["BackButton"].firstMatch
        (named.exists ? named : app.navigationBars.buttons.element(boundBy: 0)).tap()
        for _ in 0..<2 where !destination.waitForExistence(timeout: 3) {
            if named.exists && named.isHittable { named.tap() }
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "Back to \(title) didn't happen", file: file, line: line)
    }

    /// Chooses a place for a planner from typed coordinates, starting on a screen with the place
    /// row and ending back on it. Typed, so it needs no location permission and no network.
    func chooseTypedPlace(latitude: String, longitude: String, in app: XCUIApplication,
                          file: StaticString = #file, line: UInt = #line) {
        let place = app.buttons["placeRow"].firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 5), file: file, line: line)
        place.tap()
        let findOnMap = app.buttons["findOnMapButton"].firstMatch
        XCTAssertTrue(findOnMap.waitForExistence(timeout: 5), file: file, line: line)
        findOnMap.tap()

        replaceText(in: app.textFields["latitudeField"].firstMatch, with: latitude)
        replaceText(in: app.textFields["longitudeField"].firstMatch, with: longitude)
        let useCoordinates = app.buttons["useCoordinatesButton"].firstMatch
        reveal(useCoordinates, in: app, file: file, line: line)
        XCTAssertTrue(useCoordinates.isEnabled, "Typed coordinates should be accepted", file: file, line: line)
        useCoordinates.tap()
        let use = app.buttons["usePlaceButton"].firstMatch
        XCTAssertTrue(use.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(use.isEnabled, "A picked place can be used", file: file, line: line)
        use.tap()

        // The place sheet closes, back to the screen it was opened from.
        XCTAssertTrue(use.waitForNonExistence(timeout: 5), "Using the place closes the place sheet", file: file, line: line)
    }

    /// Adds an item from the Inventory tab with a make and model, leaving the tab showing the
    /// list. New items are camera bodies unless the category is changed.
    func addGear(make: String, model: String, in app: XCUIApplication,
                 file: StaticString = #file, line: UInt = #line) {
        selectTab("Inventory", in: app, file: file, line: line)
        let add = app.buttons["addGearButton"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Missing Add Gear button", file: file, line: line)
        add.tap()
        replaceText(in: app.textFields["gearMakeField"], with: make, file: file, line: line)
        replaceText(in: app.textFields["gearModelField"], with: model, file: file, line: line)
        let save = app.buttons["saveGearButton"]
        XCTAssertTrue(save.isEnabled, file: file, line: line)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "The sheet should close", file: file, line: line)
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
        /// What the field holds. An empty TextField reports its placeholder as its value.
        func contents() -> String {
            let value = field.value as? String ?? ""
            return value == field.placeholderValue ? "" : value
        }
        /// Deletes `held` characters, then types `text`. Deleting more than the field holds does
        /// no harm; deleting fewer leaves the rest in front of what's typed.
        func enter(deleting held: Int) {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: held) + text)
        }
        /// Waits for what was typed to show. True once the field holds `text`, or holds something
        /// that isn't a shortened copy of it: a field that rewrites what's typed (grouping
        /// separators, capitals) is left alone. False if it still holds a shortened copy when the
        /// wait runs out.
        func settles() -> Bool {
            let deadline = Date().addingTimeInterval(5)
            repeat {
                let arrived = contents()
                if arrived == text || !Self.isSubsequence(arrived, of: text) { return true }
                Thread.sleep(forTimeInterval: 0.25)
            } while Date() < deadline
            return false
        }
        enter(deleting: contents().count)
        // A busy simulator does two things here, and they look alike for a moment:
        // - it loses keystrokes: "Harbour" once arrived as "Ha" in CI, and the test then looked for
        //   a title that was never typed;
        // - it shows them late: the field read "R" some seconds after "R6" had gone in. Taking that
        //   for a loss and deleting one character before typing again left "RR6".
        // So the text is given time to show before it's counted as lost, and a retry clears as
        // much as could be there, not only what the field admits to.
        var attempts = 1
        while !settles(), attempts < 3 {
            enter(deleting: max(contents().count, text.count))
            attempts += 1
        }
        let arrived = contents()
        XCTAssertFalse(arrived != text && Self.isSubsequence(arrived, of: text),
                       "Typed \"\(text)\" \(attempts) times, but the field holds \"\(arrived)\"", file: file, line: line)
    }

    /// Whether `part`'s characters all appear in `whole`, in order: what a field that lost some
    /// keystrokes holds.
    static func isSubsequence(_ part: String, of whole: String) -> Bool {
        var remaining = Substring(whole)
        for character in part {
            guard let index = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }
}
