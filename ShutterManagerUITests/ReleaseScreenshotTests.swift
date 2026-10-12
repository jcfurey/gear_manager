#if DEBUG && RELEASE_SCREENSHOTS
//
//  ReleaseScreenshotTests.swift
//  ShutterManagerUITests
//
//  Captures the App Store screenshots from the fictional library in ReleaseScreenshotData. Compiled
//  only with DEBUG and RELEASE_SCREENSHOTS, so ordinary test runs don't include it. See
//  marketing/README.md.
//

import XCTest

final class ReleaseScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureReleaseScreenshots() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestInMemory", "-releaseScreenshots",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-darkModePreference", "dark", "-hapticFeedback", "NO"
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 15))
        let body = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Northwind NW-45 Mirrorless")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 10), "The demo library is loaded")
        capture("01-inventory")

        body.tap()
        XCTAssertTrue(app.navigationBars["Northwind NW-45 Mirrorless"].waitForExistence(timeout: 5))
        capture("02-gear-detail")

        selectTab("Shoots", in: app)
        XCTAssertTrue(app.navigationBars["Shoots"].waitForExistence(timeout: 5))
        let sunrise = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sunrise at Mesa Arch")).firstMatch
        XCTAssertTrue(sunrise.waitForExistence(timeout: 5))
        capture("03-shoots")

        sunrise.tap()
        XCTAssertTrue(app.navigationBars["Sunrise at Mesa Arch"].waitForExistence(timeout: 5))
        let packing = app.buttons.matching(identifier: "packRow").firstMatch
        reveal(packing, in: app)
        capture("04-shoot-detail")

        selectTab("Tools", in: app)
        XCTAssertTrue(app.navigationBars["Tools"].waitForExistence(timeout: 5))
        let sunAndMoon = app.buttons["tool.sunAndMoon"].firstMatch
        reveal(sunAndMoon, in: app)
        sunAndMoon.tap()
        XCTAssertTrue(app.navigationBars["Sun & Moon"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sunrise")).firstMatch
            .waitForExistence(timeout: 10), "The planner has worked out the day")
        capture("05-sun-and-moon")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let depthOfField = app.buttons["tool.depthOfField"].firstMatch
        reveal(depthOfField, in: app)
        capture("06-tools")

        selectTab("Light Meter", in: app)
        XCTAssertTrue(app.navigationBars["Light Meter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["meter.ev"].waitForExistence(timeout: 5))
        capture("07-light-meter")

        selectTab("Shoots", in: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let rolls = app.buttons["filmRollsLink"].firstMatch
        reveal(rolls, in: app)
        rolls.tap()
        XCTAssertTrue(app.navigationBars["Film Rolls"].waitForExistence(timeout: 5))
        capture("08-film-rolls")
    }

    @MainActor
    private func capture(_ name: String) {
        // Let navigation, charts and maps settle.
        Thread.sleep(forTimeInterval: 2)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
