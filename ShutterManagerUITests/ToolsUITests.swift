//
//  ToolsUITests.swift
//  ShutterManagerUITests
//
//  Every tool opens; depth of field shows its results; the sun and moon planner works from typed
//  coordinates; a development recipe can be made and run.
//  Runs against a fresh in-memory library (`-uiTestInMemory`).
//

import XCTest

final class ToolsUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Tool row identifiers and the titles their screens show, in list order.
    private let tools: [(id: String, title: String)] = [
        ("equivalentExposure", "Equivalent Exposure"), ("ndFilter", "ND Filter"), ("sunnySixteen", "Sunny 16"),
        ("depthOfField", "Depth of Field"), ("fieldOfView", "Field of View"),
        ("sunAndMoon", "Sun & Moon"), ("nightSky", "Milky Way"), ("astro", "Astro Exposure"),
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
            tap(row, toShow: app.navigationBars[tool.title])
            goBack(to: "Tools", in: app)
        }
    }

    @MainActor
    func testDepthOfFieldShowsTheSharpZone() throws {
        let row = app.buttons["tool.depthOfField"].firstMatch
        reveal(row, in: app)
        tap(row, toShow: app.textFields["dof.focalLength"].firstMatch)
        replaceText(in: app.textFields["dof.focalLength"].firstMatch, with: "50")
        for label in ["Near limit", "Far limit", "Depth of field", "Hyperfocal distance"] {
            let result = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            reveal(result, in: app)
        }
    }

    @MainActor
    func testSunAndMoonFromTypedCoordinates() throws {
        let row = app.buttons["tool.sunAndMoon"].firstMatch
        reveal(row, in: app)
        tap(row, toShow: app.navigationBars["Sun & Moon"])

        // London, typed: no location permission or network needed.
        chooseTypedPlace(latitude: "51.5", longitude: "-0.12", in: app)
        XCTAssertTrue(app.navigationBars["Sun & Moon"].waitForExistence(timeout: 5), "Using the place returns to the planner")
        for label in ["Sunrise", "Sunset", "Moonrise"] {
            let event = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            reveal(event, in: app)
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
        let newRecipe = app.buttons["newRecipeButton"]
        tap(row, toShow: newRecipe)
        let save = app.buttons["saveRecipeButton"]
        tap(newRecipe, toShow: save)
        XCTAssertFalse(save.isEnabled, "A recipe needs a name")
        replaceText(in: app.textFields["recipeNameField"], with: "Test Recipe")

        let addStep = app.buttons["addStepButton"]
        reveal(addStep, in: app)
        addStep.tap()
        let step = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Step 1")).firstMatch
        reveal(step, in: app)
        tap(step, toShow: app.textFields["stepMinutesField"].firstMatch)
        replaceText(in: app.textFields["stepMinutesField"].firstMatch, with: "2")
        goBack(toShow: save, in: app)
        // Saving closes the editor, and the new recipe is listed.
        let recipe = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Test Recipe")).firstMatch
        tap(save, toShow: recipe)
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "The editor should close")

        // Tapped just after the editor's sheet has closed.
        tap(recipe, toShow: app.navigationBars["Test Recipe"])
        let start = app.buttons["startDevelopmentButton"]
        reveal(start, in: app)
        XCTAssertTrue(start.isEnabled, "Every step has a time")
        // The timer opens, ready to start.
        let startStep = app.buttons["startStepButton"]
        tap(start, toShow: startStep)
        XCTAssertTrue(app.staticTexts["developmentCountdown"].exists)
        startStep.tap()
        app.tap() // Lets the interruption monitor answer the permission prompt, if it appeared.
        XCTAssertTrue(app.buttons["pauseStepButton"].waitForExistence(timeout: 5), "The step should be running")
        app.buttons["endDevelopmentButton"].tap()
        XCTAssertTrue(app.staticTexts["No Development Running"].waitForExistence(timeout: 5))
    }
}
