//
//  InventoryUITests.swift
//  ShutterManagerUITests
//
//  Adding a camera body, opening it, logging a shutter count, and lending it out.
//  Runs against a fresh in-memory library (`-uiTestInMemory`).
//

import XCTest

final class InventoryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
        selectTab("Inventory", in: app)
    }

    @MainActor
    func testAddBodyLogShutterCountAndLend() throws {
        addCameraBody(make: "Nikon", model: "Z8")

        // The new body is listed; open it.
        openItem(named: "Nikon Z8")

        // Shutter count: add a reading by hand.
        let shutterLink = app.buttons["shutterCountLink"].firstMatch
        reveal(shutterLink, in: app)
        shutterLink.tap()
        let addReading = app.buttons["addShutterReadingButton"].firstMatch
        XCTAssertTrue(addReading.waitForExistence(timeout: 5))
        addReading.tap()
        replaceText(in: app.textFields["shutterCountField"].firstMatch, with: "12345")
        let saveReading = app.buttons["saveShutterReadingButton"]
        XCTAssertTrue(saveReading.isEnabled, "A positive count should be savable")
        saveReading.tap()
        // Grouping separators vary by locale.
        let reading = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "12\\D?345")).firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 5), "The reading should be listed")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Loans: lend it out, then mark it returned.
        let loansLink = app.buttons["loansLink"].firstMatch
        reveal(loansLink, in: app)
        loansLink.tap()
        let newLoan = app.buttons["newLoanButton"].firstMatch
        XCTAssertTrue(newLoan.waitForExistence(timeout: 5))
        newLoan.tap()
        replaceText(in: app.textFields["loanPersonField"], with: "Sam")
        app.buttons["saveLoanButton"].tap()
        let markReturned = app.buttons["markReturnedButton"].firstMatch
        XCTAssertTrue(markReturned.waitForExistence(timeout: 5), "The loan should be open")
        markReturned.tap()
        XCTAssertTrue(app.buttons["newLoanButton"].firstMatch.waitForExistence(timeout: 5),
                      "Returning should close the loan")
    }

    @MainActor
    func testEditingAndCancellingLeavesTheItemUnchanged() throws {
        addCameraBody(make: "Canon", model: "R6")
        openItem(named: "Canon R6")

        let edit = app.buttons["editGearButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        replaceText(in: app.textFields["gearModelField"], with: "R5")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Canon R6"].waitForExistence(timeout: 5), "Cancel should drop the edit")

        edit.tap()
        replaceText(in: app.textFields["gearModelField"], with: "R5")
        app.buttons["doneEditingButton"].tap()
        XCTAssertTrue(app.navigationBars["Canon R5"].waitForExistence(timeout: 5), "Done should keep the edit")
    }

    @MainActor
    func testSaveNeedsAMakeOrModel() throws {
        let add = app.buttons["addGearButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let save = app.buttons["saveGearButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "A blank item can't be saved")
        replaceText(in: app.textFields["gearModelField"], with: "Leica M6")
        XCTAssertTrue(save.isEnabled)
    }

    // MARK: - Helpers

    private func addCameraBody(make: String, model: String, file: StaticString = #file, line: UInt = #line) {
        let add = app.buttons["addGearButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Missing Add Gear button", file: file, line: line)
        add.tap()
        replaceText(in: app.textFields["gearMakeField"], with: make, file: file, line: line)
        replaceText(in: app.textFields["gearModelField"], with: model, file: file, line: line)
        let save = app.buttons["saveGearButton"]
        XCTAssertTrue(save.isEnabled, file: file, line: line)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "The sheet should close", file: file, line: line)
    }

    /// Opens an item from the inventory. A row (iPhone list) or card (iPad grid) is one element
    /// whose label starts with the item's name.
    private func openItem(named name: String, file: StaticString = #file, line: UInt = #line) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name) should be listed", file: file, line: line)
        row.tap()
        XCTAssertTrue(app.buttons["editGearButton"].waitForExistence(timeout: 5), "Detail should open",
                      file: file, line: line)
    }
}
