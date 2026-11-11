//
//  CloudForecastUITests.swift
//  ShutterManagerUITests
//
//  The cloud forecast is off until it's asked for, then shows with Apple Weather's credit, and
//  Settings turns it off again.
//  Runs against a fresh in-memory library (`-uiTestInMemory`), which also starts every launch
//  with the forecast off, and a fixed forecast in place of Apple Weather (`-uiTestCloudSample`):
//  the simulator isn't signed for WeatherKit, and a test mustn't depend on the weather.
//

import XCTest

final class CloudForecastUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory", "-uiTestCloudSample"]
        app.launch()
        selectTab("Tools", in: app)
        XCTAssertTrue(app.navigationBars["Tools"].waitForExistence(timeout: 10), "The Tools tab should open")
    }

    @MainActor
    func testTheForecastIsOffUntilAskedForAndSettingsTurnsItOff() throws {
        let row = app.buttons["tool.sunAndMoon"].firstMatch
        reveal(row, in: app)
        tap(row, toShow: app.navigationBars["Sun & Moon"])
        chooseTypedPlace(latitude: "51.5", longitude: "-0.12", in: app)
        XCTAssertTrue(app.navigationBars["Sun & Moon"].waitForExistence(timeout: 5), "Using the place returns to the planner")

        // Off: the offer, and nothing of Apple Weather's.
        let credit = app.descendants(matching: .any).matching(identifier: "weatherAttribution").firstMatch
        let show = app.buttons["showCloudForecastButton"].firstMatch
        reveal(show, in: app)
        XCTAssertFalse(credit.exists, "No forecast is shown before it's asked for")
        show.tap()

        // On: the clouds, with the credit and the link Apple's terms ask for.
        XCTAssertTrue(show.waitForNonExistence(timeout: 10), "The offer goes once the forecast is on")
        let clouds = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "% cloud")).firstMatch
        reveal(clouds, in: app)
        reveal(credit, in: app)
        XCTAssertEqual(credit.label, "Apple Weather")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "weatherLegalLink").firstMatch.exists,
                      "The link to Apple Weather's data sources goes with its credit")

        // Settings shows it on, and turns it off.
        selectTab("Settings", in: app)
        let toggle = app.switches["settings.cloudForecast"].firstMatch
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1", "Turning it on in the planner is the same switch")
        toggle.tap()
        let off = expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: toggle)
        wait(for: [off], timeout: 5)

        // Back in the planner the forecast has gone, and the offer is back. (A second tap on the
        // tab, which `selectTab` makes when the first didn't seem to take, returns to the list:
        // open the planner again then. It remembers its place.)
        selectTab("Tools", in: app)
        if !app.navigationBars["Sun & Moon"].waitForExistence(timeout: 3) {
            reveal(row, in: app)
            tap(row, toShow: app.navigationBars["Sun & Moon"])
        }
        reveal(show, in: app)
        XCTAssertFalse(credit.exists, "Off drops the forecast")
    }
}
