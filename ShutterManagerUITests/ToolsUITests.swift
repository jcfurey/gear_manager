//
//  ToolsUITests.swift
//  ShutterManagerUITests
//
//  Every tool opens; depth of field shows its results; a development recipe can be made and run.
//  Runs against a fresh in-memory library (`-uiTestInMemory`).
//

import XCTest

final class ToolsUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Tool row identifiers and the titles their screens show, in list order.
    private let tools: [(id: String, title: String)] = [
        ("equivalentExposure", "Equivalent Exposure"), ("ndFilter", "ND Filter"), ("sunnySixteen", "Sunny 16"),
        ("depthOfField", "Depth of Field"), ("fieldOfView", "Field of View"), ("astro", "Astro Exposure"),
        ("timeLapse", "Time-Lapse"), ("flash", "Flash"), ("printSize", "Print Size"),
        ("reciprocity", "Reciprocity"), ("development", "Development Timer")
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
        selectTab("Tools", in: app)
        XCTAssertTrue(app.navigationBars["Tools"].waitForExistence(timeout: 10), "The Tools tab should open")
    }

    @MainActor
    func testEveryToolOpens() throws {
        for tool in tools {
            let row = app.buttons["tool.\(tool.id)"].firstMatch
            reveal(row, in: app)
            row.tap()
            XCTAssertTrue(app.navigationBars[tool.title].waitForExistence(timeout: 5), "\(tool.title) didn't open")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Tools"].waitForExistence(timeout: 5), "Back to Tools from \(tool.title)")
        }
    }

    @MainActor
    func testDepthOfFieldShowsTheSharpZone() throws {
        let row = app.buttons["tool.depthOfField"].firstMatch
        reveal(row, in: app)
        row.tap()
        replaceText(in: app.textFields["dof.focalLength"].firstMatch, with: "50")
        for label in ["Near limit", "Far limit", "Depth of field", "Hyperfocal distance"] {
            let result = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            reveal(result, in: app)
        }
    }

    @MainActor
    func testCreateARecipeAndStartItsTimer() throws {
        // Starting a step asks for notification permission the first time.
        addUIInterruptionMonitor(withDescription: "Notifications") { alert in
            for title in ["Allow", "Don’t Allow", "Don't Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }

        let row = app.buttons["tool.development"].firstMatch
        reveal(row, in: app)
        row.tap()
        let newRecipe = app.buttons["newRecipeButton"]
        XCTAssertTrue(newRecipe.waitForExistence(timeout: 5))
        newRecipe.tap()

        let save = app.buttons["saveRecipeButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "A recipe needs a name")
        replaceText(in: app.textFields["recipeNameField"], with: "Test Recipe")

        let addStep = app.buttons["addStepButton"]
        reveal(addStep, in: app)
        addStep.tap()
        let step = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Step 1")).firstMatch
        reveal(step, in: app)
        step.tap()
        replaceText(in: app.textFields["stepMinutesField"].firstMatch, with: "2")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "The editor should close")

        let recipe = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Test Recipe")).firstMatch
        XCTAssertTrue(recipe.waitForExistence(timeout: 5), "The new recipe should be listed")
        recipe.tap()
        let start = app.buttons["startDevelopmentButton"]
        reveal(start, in: app)
        XCTAssertTrue(start.isEnabled, "Every step has a time")
        start.tap()

        let startStep = app.buttons["startStepButton"]
        XCTAssertTrue(startStep.waitForExistence(timeout: 5), "The timer should open, ready to start")
        XCTAssertTrue(app.staticTexts["developmentCountdown"].exists)
        startStep.tap()
        app.tap() // Lets the interruption monitor answer the permission prompt, if it appeared.
        XCTAssertTrue(app.buttons["pauseStepButton"].waitForExistence(timeout: 5), "The step should be running")
        app.buttons["endDevelopmentButton"].tap()
        XCTAssertTrue(app.staticTexts["No Development Running"].waitForExistence(timeout: 5))
    }
}
