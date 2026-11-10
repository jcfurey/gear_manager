//
//  ReportsUITests.swift
//  ShutterManagerUITests
//
//  The report for the user's insurer: from Settings, with an item in the library, to the PDF on
//  screen with its share button. Runs against a fresh in-memory library (`-uiTestInMemory`).
//

import XCTest

final class ReportsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
    }

    @MainActor
    func testCreateAReportForYourInsurer() throws {
        addGear(make: "Canon", model: "R6", in: app)

        selectTab("Settings", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let row = app.buttons["settings.insurerReport"].firstMatch
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.navigationBars["Report for Your Insurer"].waitForExistence(timeout: 5), "The report sheet opens")

        XCTAssertTrue(app.textFields["reportOwnerField"].firstMatch.exists, "The report can carry the owner's name")
        let create = app.buttons["createReportButton"].firstMatch
        reveal(create, in: app)
        XCTAssertTrue(create.isEnabled, "One item is enough for a report")
        create.tap()

        XCTAssertTrue(app.navigationBars["Report"].waitForExistence(timeout: 20), "The finished report is shown")
        XCTAssertTrue(app.buttons["sharePDFButton"].firstMatch.waitForExistence(timeout: 5), "It can be shared or printed")
    }

    @MainActor
    func testAReportNeedsGear() throws {
        selectTab("Settings", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let row = app.buttons["settings.insurerReport"].firstMatch
        reveal(row, in: app)
        row.tap()
        let create = app.buttons["createReportButton"].firstMatch
        reveal(create, in: app)
        XCTAssertFalse(create.isEnabled, "There's nothing to report yet")
    }
}
