//
//  AccessibilityAuditTests.swift
//  ShutterManagerUITests
//
//  Runs Xcode's accessibility audit on the main screens of each tab, in a fresh in-memory library.
//  An audit sees only what is on screen, so each test opens the screens it checks. Issues of the
//  types in `blocking` fail the test, one failure per issue naming the screen and the element;
//  the rest are attached to the result for review in Xcode.
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    /// Issue types that fail a test.
    private let blocking: XCUIAccessibilityAuditType = .all

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
        var issues: [(type: XCUIAccessibilityAuditType, text: String)] = []
        try app.performAccessibilityAudit { issue in
            issues.append((issue.auditType, self.describe(issue)))
            return true
        }
        var recorded: [String] = []
        for issue in issues {
            if blocking.contains(issue.type) {
                XCTFail("\(screen): \(issue.text)", file: file, line: line)
            } else {
                recorded.append(issue.text)
            }
        }
        if !recorded.isEmpty {
            let attachment = XCTAttachment(string: recorded.joined(separator: "\n"))
            attachment.name = "Accessibility audit: \(screen)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        var element = "no element"
        if let target = issue.element, target.exists {
            element = "label \"\(target.label)\", id \"\(target.identifier)\", frame \(target.frame)"
        }
        return "\(name(of: issue.auditType)): \(issue.compactDescription). \(issue.detailedDescription) [\(element)]"
    }

    private func name(of type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .elementDetection: "element detection"
        case .hitRegion: "hit region"
        case .sufficientElementDescription: "element description"
        case .dynamicType: "Dynamic Type"
        case .textClipped: "clipped text"
        case .trait: "trait"
        default: "audit type \(type.rawValue)"
        }
    }
}
