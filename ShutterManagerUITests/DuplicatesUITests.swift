//
//  DuplicatesUITests.swift
//  ShutterManagerUITests
//
//  Settings → Find Duplicates on a library with nothing doubled. Folding real doubles is covered
//  by the unit tests: a doubled library can't be made through the app's own screens.
//  Runs against a fresh in-memory library (`-uiTestInMemory`).
//

import XCTest

final class DuplicatesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
    }

    @MainActor
    func testALibraryHeldOnceHasNoDuplicates() throws {
        addGear(make: "Canon", model: "R6", in: app)

        selectTab("Settings", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let row = app.buttons["settings.duplicates"].firstMatch
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.navigationBars["Find Duplicates"].waitForExistence(timeout: 5), "The screen opens")
        XCTAssertTrue(app.staticTexts["No Duplicates"].firstMatch.waitForExistence(timeout: 10),
                      "A library held once has nothing to remove")
        XCTAssertFalse(app.buttons["removeDuplicatesButton"].firstMatch.exists, "So there's nothing to tap")
    }
}
