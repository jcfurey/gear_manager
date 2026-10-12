//
//  LaunchUITests.swift
//  ShutterManagerUITests
//
//  The app launches and shows all five tabs.
//

import XCTest

final class LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsAllTabs() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBarItem("Inventory").waitForExistence(timeout: 10), "Missing tab: Inventory")
        for title in ["Tools", "Light Meter", "Shoots", "Settings"] {
            XCTAssertTrue(app.tabBarItem(title).exists, "Missing tab: \(title)")
        }
    }

    @MainActor
    func testEveryTabOpens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
        for title in ["Tools", "Light Meter", "Shoots", "Settings", "Inventory"] {
            selectTab(title, in: app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) didn't open")
        }
    }
}
