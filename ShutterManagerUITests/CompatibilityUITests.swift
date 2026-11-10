//
//  CompatibilityUITests.swift
//  ShutterManagerUITests
//
//  Lens and body compatibility: a body's screen of lenses, and a lens that needs the maker's
//  adapter listed as such. Runs against a fresh in-memory library (`-uiTestInMemory`).
//

import XCTest

final class CompatibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
    }

    /// Adds an item with a mount; `category` names one to choose in place of Camera Body.
    private func addGear(make: String, model: String, mount: String, category: String? = nil,
                         file: StaticString = #file, line: UInt = #line) {
        selectTab("Inventory", in: app, file: file, line: line)
        let add = app.buttons["addGearButton"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Missing Add Gear button", file: file, line: line)
        add.tap()
        if let category {
            let picker = app.descendants(matching: .any).matching(identifier: "gearCategoryPicker").firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 5), "Missing the category picker", file: file, line: line)
            picker.tap()
            let choice = app.buttons[category].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "The category menu should list \(category)",
                          file: file, line: line)
            choice.tap()
        }
        replaceText(in: app.textFields["gearMakeField"], with: make, file: file, line: line)
        replaceText(in: app.textFields["gearModelField"], with: model, file: file, line: line)
        let mountField = app.textFields["gearMountField"].firstMatch
        reveal(mountField, in: app, file: file, line: line)
        replaceText(in: mountField, with: mount, file: file, line: line)
        let save = app.buttons["saveGearButton"]
        XCTAssertTrue(save.isEnabled, file: file, line: line)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "The sheet should close", file: file, line: line)
    }

    private func openCompatibility(of name: String, file: StaticString = #file, line: UInt = #line) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name) should be listed", file: file, line: line)
        row.tap()
        let link = app.buttons["compatibilityLink"].firstMatch
        reveal(link, in: app, file: file, line: line)
        link.tap()
    }

    @MainActor
    func testABodyWithAMountHasAScreenOfLenses() throws {
        addGear(make: "Nikon", model: "Z6 III", mount: "Nikon Z")
        openCompatibility(of: "Nikon Z6 III")
        XCTAssertTrue(app.navigationBars["Lenses That Fit"].waitForExistence(timeout: 5), "The body's lenses open")
        XCTAssertTrue(app.staticTexts["16 mm"].firstMatch.waitForExistence(timeout: 5)
                      || app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "16 mm")).firstMatch.exists,
                      "The mount's flange distance is shown")
        XCTAssertTrue(app.staticTexts["No Lenses to Compare"].firstMatch.exists, "With no lenses yet, it says so")
    }

    @MainActor
    func testALensThatNeedsTheMakersAdapterSaysSo() throws {
        addGear(make: "Nikon", model: "Z6 III", mount: "Nikon Z")
        addGear(make: "Nikon", model: "AF-S 85mm", mount: "Nikon F", category: "Lens")
        openCompatibility(of: "Nikon Z6 III")
        XCTAssertTrue(app.navigationBars["Lenses That Fit"].waitForExistence(timeout: 5))
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "compatibilityRow", "AF-S 85mm", "FTZ II")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The F-mount lens is listed with Nikon's adapter named")
        XCTAssertTrue(app.staticTexts["With an Adapter"].firstMatch.exists
                      || app.staticTexts["WITH AN ADAPTER"].firstMatch.exists, "Under its own heading")
    }
}
