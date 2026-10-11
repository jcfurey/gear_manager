//
//  LightMeterUITests.swift
//  ShutterManagerUITests
//
//  The light meter with a typed reading (simulators have no camera): stepping the EV, and sending
//  the result to the ND filter calculator.
//

import XCTest

final class LightMeterUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory"]
        app.launch()
        selectTab("Light Meter", in: app)
        XCTAssertTrue(app.navigationBars["Light Meter"].waitForExistence(timeout: 10), "The Light Meter tab should open")
    }

    @MainActor
    func testTypedReadingSolvesAndOpensTheNDCalculator() throws {
        let byHand = app.buttons["By Hand"].firstMatch
        reveal(byHand, in: app)
        byHand.tap()

        let ev = app.staticTexts["meter.ev"].firstMatch
        XCTAssertTrue(ev.waitForExistence(timeout: 5))
        let before = ev.label
        XCTAssertTrue(before.hasPrefix("EV "), "A typed reading shows its EV, not \(before)")

        // The typed-EV stepper comes before the filter stepper, so its buttons match first.
        let stepper = app.descendants(matching: .any).matching(identifier: "meter.manualEV").firstMatch
        reveal(stepper, in: app)
        let direction = before == "EV 25" ? "Decrement" : "Increment"
        var step = stepper.buttons[direction].firstMatch
        if !step.exists { step = app.buttons[direction].firstMatch }
        step.tap()
        let changed = expectation(for: NSPredicate(format: "label != %@", before), evaluatedWith: ev)
        wait(for: [changed], timeout: 5)

        // The segment, not the aperture picker below it.
        let aperturePriority = app.segmentedControls["meter.priority"].buttons["Aperture"].firstMatch
        reveal(aperturePriority, in: app)
        aperturePriority.tap()
        let result = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Shutter")).firstMatch
        reveal(result, in: app)

        let send = app.buttons["meter.sendToND"].firstMatch
        reveal(send, in: app)
        send.tap()
        XCTAssertTrue(app.navigationBars["ND Filter"].waitForExistence(timeout: 5), "The reading opens in the ND calculator")
    }
}
