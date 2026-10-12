//
//  PrivacyPolicyTests.swift
//  ShutterManagerTests
//
//  The public privacy policy page (docs/PRIVACY.md) says what the app says. Foundation-only, so
//  it also runs on Linux.
//

import Foundation
import Testing
@testable import ShutterManager

struct PrivacyPolicyTests {
    @Test func thePublicPageMatchesTheApp() throws {
        // Resolved, because the Linux script runs the tests through symlinks.
        let page = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/PRIVACY.md")
        let text = try String(contentsOf: page, encoding: .utf8)
        #expect(text == PrivacyPolicy.markdown,
                "docs/PRIVACY.md is out of date: write PrivacyPolicy.markdown to it")
    }

    @Test func everySectionHasText() {
        #expect(!PrivacyPolicy.sections.isEmpty)
        for section in PrivacyPolicy.sections {
            #expect(!section.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(section.title)")
        }
        #expect(PrivacyPolicy.markdown.contains(PrivacyPolicy.contactEmail))
    }
}
