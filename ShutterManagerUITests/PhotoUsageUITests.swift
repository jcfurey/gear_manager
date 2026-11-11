//
//  PhotoUsageUITests.swift
//  ShutterManagerUITests
//
//  Usage from Photos: counting a batch, recording the shutter count it carries, and adding the
//  gear used to a shoot. The system photo and file pickers can't be driven from a test, so
//  `-uiTestPhotoUsageSample` adds a button that reads a fixed batch in their place: three shots
//  on a Nikon Z6 III, the last at 20,002 actuations, and one on a Fujifilm.
//  Runs against a fresh in-memory library (`-uiTestInMemory`).
//

import XCTest

final class PhotoUsageUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestInMemory", "-uiTestPhotoUsageSample"]
        app.launch()
    }

    /// An element with `identifier` whose label has every one of `parts`.
    private func element(_ identifier: String, saying parts: String...) -> XCUIElement {
        var format = "identifier == %@"
        var arguments: [Any] = [identifier]
        for part in parts {
            format += " AND label CONTAINS %@"
            arguments.append(part)
        }
        return app.descendants(matching: .any).matching(NSPredicate(format: format, argumentArray: arguments)).firstMatch
    }

    /// Reads the sample batch on the Usage from Photos sheet, which must be showing.
    private func readSamplePhotos(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars["Usage from Photos"].waitForExistence(timeout: 5), "The sheet opens",
                      file: file, line: line)
        for identifier in ["photoUsagePhotosButton", "photoUsageFilesButton", "photoUsageFolderButton"] {
            XCTAssertTrue(app.buttons[identifier].firstMatch.waitForExistence(timeout: 5),
                          "Photos, files and a folder are all offered: \(identifier)", file: file, line: line)
        }
        XCTAssertFalse(app.buttons["savePhotoUsageButton"].firstMatch.exists, "Nothing to save before photos are read",
                       file: file, line: line)
        app.buttons["photoUsageSampleButton"].firstMatch.tap()
        XCTAssertTrue(element("photoUsageTotal", saying: "4 photos").waitForExistence(timeout: 10),
                      "The batch is counted", file: file, line: line)
        XCTAssertTrue(element("photoUsageGroup", saying: "Nikon Z6_3", "3 photos").exists,
                      "Shots are counted per body", file: file, line: line)
        XCTAssertTrue(element("photoUsageGroup", saying: "X-T5", "1 photo").exists,
                      "A body that isn't in the inventory is still counted", file: file, line: line)
    }

    @MainActor
    func testCountPhotosAndRecordTheShutterCount() throws {
        addGear(make: "Nikon", model: "Z6 III", in: app)

        // Tapped just after Add Gear's sheet has closed: on CI that tap was once lost.
        tap(app.buttons["Collection stats"].firstMatch, toShow: app.navigationBars["Collection"])
        let usage = app.buttons["collectionPhotoUsageButton"].firstMatch
        reveal(usage, in: app)
        tap(usage, toShow: app.navigationBars["Usage from Photos"])
        readSamplePhotos()

        // The Z6 III was matched by name ("Z6_3" in the files), so its count can be saved.
        let save = app.buttons["savePhotoUsageButton"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "A matched body with a shutter count is something to save")
        save.tap()
        XCTAssertTrue(app.navigationBars["Usage from Photos"].waitForNonExistence(timeout: 5), "Saving closes the sheet")

        // The body now has the count from its last photo. (The confirmation banner sits near the
        // top bar on iPad: let it go before reaching for Back.)
        let banner = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Usage Saved")).firstMatch
        XCTAssertTrue(banner.waitForNonExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Nikon Z6 III,")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Back in the inventory")
        row.tap()
        let history = app.buttons["shutterCountLink"].firstMatch
        reveal(history, in: app)
        history.tap()
        // Grouping separators vary by locale.
        let reading = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", ".*20\\D?002.*")).firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 5), "The count from the photos is in the body's history")
    }

    @MainActor
    func testAddTheGearUsedToAShoot() throws {
        addGear(make: "Nikon", model: "Z6 III", in: app)

        selectTab("Shoots", in: app)
        XCTAssertTrue(app.navigationBars["Shoots"].waitForExistence(timeout: 10))
        tap(app.buttons["addShootButton"].firstMatch, toShow: app.textFields["shootTitleField"].firstMatch)
        replaceText(in: app.textFields["shootTitleField"].firstMatch, with: "Harbour Test")
        app.buttons["saveShootButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Harbour Test"].waitForExistence(timeout: 5), "The new shoot opens")
        XCTAssertFalse(app.buttons.matching(identifier: "packRow").firstMatch.exists, "No gear on it yet")

        let fromPhotos = app.buttons["shootPhotoUsageButton"].firstMatch
        reveal(fromPhotos, in: app)
        tap(fromPhotos, toShow: app.navigationBars["Usage from Photos"])
        readSamplePhotos()
        let toggle = app.switches["photoUsageShootToggle"].firstMatch
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1", "From a shoot, its gear is added unless turned off")

        let save = app.buttons["savePhotoUsageButton"].firstMatch
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.navigationBars["Usage from Photos"].waitForNonExistence(timeout: 5), "Saving closes the sheet")

        let packed = app.buttons.matching(identifier: "packRow").firstMatch
        reveal(packed, in: app, direction: .down)
        XCTAssertTrue(packed.label.contains("Z6 III"), "The body the photos named is on the shoot: \(packed.label)")
    }
}
