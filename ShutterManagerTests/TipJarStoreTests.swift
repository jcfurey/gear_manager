//
//  TipJarStoreTests.swift
//  ShutterManagerTests
//
//  The local StoreKit configuration (ShutterManager.storekit at the repository root, which the
//  scheme runs with) offers exactly the app's tips. Purchases themselves are checked by hand in
//  Xcode: StoreKitTest's headers use a type iOS 18 deprecates, so the framework can't be imported
//  with warnings treated as errors.
//

import Foundation
import Testing
@testable import ShutterManager

struct TipJarStoreTests {
    @Test func theConfigurationListsEveryTip() throws {
        let configuration = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ShutterManager.storekit")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: configuration)) as? [String: Any])
        let products = try #require(json["products"] as? [[String: Any]])
        #expect(Set(products.compactMap { $0["productID"] as? String }) == Set(TipProduct.allCases.map(\.rawValue)))
        #expect(products.allSatisfy { $0["type"] as? String == "Consumable" }, "Tips unlock nothing")
        #expect(products.allSatisfy { $0["familyShareable"] as? Bool == false })
    }
}
