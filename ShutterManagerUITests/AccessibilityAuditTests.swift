//
//  AccessibilityAuditTests.swift
//  ShutterManagerUITests
//
//  Runs Xcode's accessibility audit on the main screens of each tab, in a fresh in-memory library.
//  An audit sees only what is on screen, so each test opens the screens it checks. Each issue
//  fails the test, naming the screen and the element.
//
//  It runs the checks that give the same answer every run: labels, touch-target size, and text
//  an assistive technology can't reach. A full audit of every type was run once and its real
//  findings fixed (see AppColors for contrast). The other checks are left out because:
//  - Dynamic Type flagged system text styles and standard Form rows, which do scale, and with
//    clipped text it made an audit on iPad run past the 10-minute test limit;
//  - contrast flagged text passing under the iOS 26 tab bar's and toolbar's edge fade, and
//    disabled buttons, which WCAG exempts;
//  - the trait check flagged SwiftUI's own disabled toolbar buttons.
//  Issues with no element are system drawing, such as the iPad tab bar or a menu picker's
//  value, and are skipped: there is nothing in the app to fix.
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    /// Missing labels, small touch targets, and text an assistive technology can't reach.
    private let auditTypes: XCUIAccessibilityAuditType = [.sufficientElementDescription, .hitRegion, .elementDetection]

    override func setUpWithError() throws {
        // Every screen in a test reports its issues, not only the first.
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
    }

    @MainActor
    func testInventoryScreens() throws {
        selectTab("Inventory", in: app)
        try wait(for: app.navigationBars["Inventory"], "The Inventory tab should open")
        try audit("Inventory (empty)")

        try wait(for: app.buttons["addGearButton"].firstMatch, "Missing Add Gear button").tap()
        let save = try wait(for: app.buttons["saveGearButton"].firstMatch, "Add Gear should open")
        try audit("Add Gear")
        replaceText(in: app.textFields["gearMakeField"].firstMatch, with: "Canon")
        replaceText(in: app.textFields["gearModelField"].firstMatch, with: "R6")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "The sheet should close")
        try audit("Inventory")

        try wait(for: app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Canon R6,")).firstMatch,
                 "The new item should be listed").tap()
        try wait(for: app.buttons["editGearButton"].firstMatch, "The item should open")
        try audit("Gear detail")
    }

    @MainActor
    func testToolScreens() throws {
        selectTab("Tools", in: app)
        try wait(for: app.navigationBars["Tools"], "The Tools tab should open")
        try audit("Tools")

        for (id, title) in [("equivalentExposure", "Equivalent Exposure"), ("depthOfField", "Depth of Field"),
                            ("sunAndMoon", "Sun & Moon"), ("development", "Development Timer")] {
            let row = app.buttons["tool.\(id)"].firstMatch
            reveal(row, in: app)
            row.tap()
            try wait(for: app.navigationBars[title], "\(title) should open")
            try audit(title)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            try wait(for: app.navigationBars["Tools"], "Back to Tools from \(title)")
        }
    }

    @MainActor
    func testLightMeter() throws {
        selectTab("Light Meter", in: app)
        try wait(for: app.navigationBars["Light Meter"], "The Light Meter tab should open")
        // Simulators have no camera, so the meter takes a typed reading.
        let byHand = app.buttons["By Hand"].firstMatch
        reveal(byHand, in: app)
        byHand.tap()
        try wait(for: app.staticTexts["meter.ev"].firstMatch, "A typed reading should show its EV")
        try audit("Light Meter")
    }

    @MainActor
    func testShootScreens() throws {
        selectTab("Shoots", in: app)
        try wait(for: app.navigationBars["Shoots"], "The Shoots tab should open")
        try audit("Shoots (empty)")

        try wait(for: app.buttons["addShootButton"].firstMatch, "Missing New Shoot button").tap()
        let save = try wait(for: app.buttons["saveShootButton"].firstMatch, "The shoot editor should open")
        try audit("New Shoot")
        replaceText(in: app.textFields["shootTitleField"].firstMatch, with: "Harbour")
        save.tap()
        try wait(for: app.navigationBars["Harbour"], "The new shoot should open")
        try audit("Shoot")
    }

    @MainActor
    func testSettingsScreens() throws {
        selectTab("Settings", in: app)
        try wait(for: app.navigationBars["Settings"], "The Settings tab should open")
        try audit("Settings")

        for (link, title) in [("About the App", "About"), ("Tip Jar", "Tip Jar"), ("Privacy Policy", "Privacy Policy")] {
            let row = app.buttons[link].firstMatch
            reveal(row, in: app)
            row.tap()
            try wait(for: app.navigationBars[title], "\(title) should open")
            try audit(title)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            try wait(for: app.navigationBars["Settings"], "Back to Settings from \(title)")
        }
    }

    // MARK: - Helpers

    /// Waits for a control a later step needs; a missing one ends the test, since nothing after it
    /// can run.
    @discardableResult
    private func wait(for element: XCUIElement, _ message: String,
                      file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        try XCTUnwrap(element.waitForExistence(timeout: 10) ? element : nil, message, file: file, line: line)
    }

    /// Audits what is on screen. The keyboard is dismissed first, since its keys are the system's.
    @MainActor
    private func audit(_ screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        if app.keyboards.firstMatch.exists {
            app.navigationBars.firstMatch.tap()
        }
        var failures: [String] = []
        try app.performAccessibilityAudit(for: auditTypes) { issue in
            if let element = issue.element, element.exists {
                failures.append("\(self.name(of: issue.auditType)): \(issue.compactDescription). "
                    + "\(issue.detailedDescription) [label \"\(element.label)\", id \"\(element.identifier)\", "
                    + "frame \(element.frame)]")
            }
            return true
        }
        for failure in failures {
            XCTFail("\(screen): \(failure)", file: file, line: line)
        }
    }

    private func name(of type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .elementDetection: "element detection"
        case .hitRegion: "hit region"
        case .sufficientElementDescription: "element description"
        default: "audit type \(type.rawValue)"
        }
    }
}
