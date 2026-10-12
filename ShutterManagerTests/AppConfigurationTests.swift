//
//  AppConfigurationTests.swift
//  ShutterManagerTests
//
//  Checks the identifiers the App Store, CloudKit and backups depend on.
//

import Foundation
import Testing
@testable import ShutterManager

struct AppConfigurationTests {
    /// Unit tests are hosted in the app, so `Bundle.main` is the app bundle.
    @Test func bundleIdentifierIsStable() {
        #expect(Bundle.main.bundleIdentifier == "jcameronfurey.shuttermanager")
    }

    @Test func displayNameIsShutterManager() {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        #expect(name == "Shutter Manager")
    }
}
