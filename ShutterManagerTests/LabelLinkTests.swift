//
//  LabelLinkTests.swift
//  ShutterManagerTests
//
//  The link a QR label carries. Foundation-only, so it also runs on Linux.
//

import Foundation
import Testing
@testable import ShutterManager

struct LabelLinkTests {
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test func aLinkReadsBackAsItself() throws {
        for link in [LabelLink.kit(id), .gear(id)] {
            #expect(LabelLink(text: link.text) == link)
            #expect(LabelLink(url: try #require(link.url)) == link)
            #expect(link.recordID == id)
        }
        #expect(LabelLink.kit(id).text == "shuttermanager://kit/6F9619FF-8B86-D011-B42D-00C04FC964FF")
        #expect(LabelLink.kit(id) != LabelLink.gear(id))
    }

    @Test func readingForgivesCaseAndWhitespace() {
        #expect(LabelLink(text: "  SHUTTERMANAGER://Kit/6f9619ff-8b86-d011-b42d-00c04fc964ff\n") == .kit(id))
        #expect(LabelLink(text: "shuttermanager://gear/6F9619FF-8B86-D011-B42D-00C04FC964FF/") == .gear(id))
    }

    @Test(arguments: [
        "", "hello", "012345678905",
        "https://example.com/kit/6F9619FF-8B86-D011-B42D-00C04FC964FF",
        "shuttermanager://kit/not-an-id",
        "shuttermanager://kit/",
        "shuttermanager://shoot/6F9619FF-8B86-D011-B42D-00C04FC964FF",
        "shuttermanager:6F9619FF-8B86-D011-B42D-00C04FC964FF"
    ])
    func otherCodesAreNotLabels(text: String) {
        #expect(LabelLink(text: text) == nil)
    }

    @Test func theLinkIsShortEnoughForASmallCode() {
        // 62 bytes is what a version 4 code (33 modules a side) holds at medium error correction;
        // anything longer would need smaller modules on the same label.
        #expect(LabelLink.gear(id).text.utf8.count <= 62)
    }
}
