//
//  LabelsUITests.swift
//  ShutterManagerUITests
//
//  QR labels: printing one for a kit, and opening a label's link the way the Camera app does.
//  Runs against a fresh in-memory library (`-uiTestInMemory`).
//

import XCTest

final class LabelsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
    }

    @MainActor
    func testPrintALabelForAKit() throws {
        selectTab("Shoots", in: app)
        XCTAssertTrue(app.navigationBars["Shoots"].waitForExistence(timeout: 10))
        let kits = app.buttons["kitsLink"].firstMatch
        reveal(kits, in: app)
        tap(kits, toShow: app.navigationBars["Kits"])

        tap(app.buttons["addKitButton"].firstMatch, toShow: app.textFields["kitNameField"].firstMatch)
        replaceText(in: app.textFields["kitNameField"].firstMatch, with: "Wedding")
        let save = app.buttons["saveKitButton"].firstMatch
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "The kit sheet should close")

        let labels = app.buttons["kitLabelsButton"].firstMatch
        reveal(labels, in: app)
        tap(labels, toShow: app.navigationBars["QR Labels"])
        let row = app.buttons.matching(identifier: "labelKitRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isSelected, "Opened from Kits, every kit is already chosen")

        let create = app.buttons["createLabelsButton"].firstMatch
        reveal(create, in: app)
        XCTAssertTrue(create.isEnabled)
        create.tap()
        XCTAssertTrue(app.navigationBars["Labels"].waitForExistence(timeout: 20), "The sheet of labels is shown")
        XCTAssertTrue(app.buttons["sharePDFButton"].firstMatch.waitForExistence(timeout: 5), "It can be shared or printed")
    }

    @MainActor
    func testALabelFromAnotherLibrarySaysSo() throws {
        XCTAssertTrue(app.tabBarItem("Inventory").waitForExistence(timeout: 10))
        // The Camera app follows a label's code to the app like this.
        app.open(try XCTUnwrap(URL(string: "shuttermanager://kit/6F9619FF-8B86-D011-B42D-00C04FC964FF")))
        XCTAssertTrue(app.staticTexts["Not Found"].waitForExistence(timeout: 10), "An unknown label is explained, not ignored")
        app.buttons["closeLabelButton"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Not Found"].waitForNonExistence(timeout: 5))
    }
}
