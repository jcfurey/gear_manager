//
//  ShootsUITests.swift
//  ShutterManagerUITests
//
//  The Shoots tab: planning a shoot and ticking off its shot list, and loading a film roll that
//  the light meter then meters for. Runs against a fresh in-memory library (`-uiTestInMemory`).
//

import XCTest

final class ShootsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
        selectTab("Shoots", in: app)
        XCTAssertTrue(app.navigationBars["Shoots"].waitForExistence(timeout: 10), "The Shoots tab should open")
    }

    @MainActor
    func testPlanAShootAndTickItsShotList() throws {
        let add = app.buttons["addShootButton"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        replaceText(in: app.textFields["shootTitleField"].firstMatch, with: "Harbour Test")
        let save = app.buttons["saveShootButton"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // A new shoot opens once its sheet has closed.
        XCTAssertTrue(app.navigationBars["Harbour Test"].waitForExistence(timeout: 5), "The new shoot opens")
        let field = app.textFields["newShotField"].firstMatch
        reveal(field, in: app)
        replaceText(in: field, with: "Bridge at blue hour")
        let addShot = app.buttons["addShotButton"].firstMatch
        reveal(addShot, in: app)
        addShot.tap()

        let shot = app.buttons.matching(identifier: "shotRow").firstMatch
        reveal(shot, in: app)
        XCTAssertFalse(shot.isSelected)
        shot.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "shotRow").firstMatch.isSelected, "The shot is ticked off")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Shoots"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Harbour Test")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The shoot is listed")
    }

    @MainActor
    func testLoadARollAndMeterForIt() throws {
        let rolls = app.buttons["filmRollsLink"].firstMatch
        reveal(rolls, in: app)
        rolls.tap()
        XCTAssertTrue(app.navigationBars["Film Rolls"].waitForExistence(timeout: 5))
        app.buttons["addRollButton"].firstMatch.tap()

        let save = app.buttons["saveRollButton"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "A roll needs a film")
        let stock = app.buttons["rollStockRow"].firstMatch
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.tap()
        let hp5 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HP5 Plus 400")).firstMatch
        reveal(hp5, in: app)
        hp5.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ilford HP5 Plus 400")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The roll is listed as loaded")

        selectTab("Light Meter", in: app)
        XCTAssertTrue(app.navigationBars["Light Meter"].waitForExistence(timeout: 5))
        let byHand = app.buttons["By Hand"].firstMatch
        reveal(byHand, in: app)
        byHand.tap()
        let loadedRolls = app.buttons["meter.loadedRoll"].firstMatch
        reveal(loadedRolls, in: app)
        loadedRolls.tap()
        XCTAssertTrue(app.navigationBars["Loaded Rolls"].waitForExistence(timeout: 5))
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ilford HP5 Plus 400")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "The loaded roll is offered")
        choice.tap()
        XCTAssertTrue(app.navigationBars["Light Meter"].waitForExistence(timeout: 5), "Picking a roll goes back")
        let film = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                    "Film", "HP5 Plus 400")).firstMatch
        reveal(film, in: app)
    }
}
