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

        for title in ["Inventory", "Tools", "Light Meter", "Shoots", "Settings"] {
            XCTAssertTrue(tabButton(title, in: app).waitForExistence(timeout: 10), "Missing tab: \(title)")
        }
    }

    /// iPhone shows a bottom tab bar; iPad (iOS 18+) shows a floating tab bar whose items are
    /// plain buttons, so fall back to any button with the tab's title.
    private func tabButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let tabBarButton = app.tabBars.buttons[title]
        return tabBarButton.exists ? tabBarButton : app.buttons[title].firstMatch
    }
}
