//
//  TipJarStoreTests.swift
//  ShutterManagerTests
//
//  The tip jar against StoreKit's local test environment, using the same configuration file the
//  scheme runs with (ShutterManager.storekit at the repository root).
//

import Foundation
import StoreKitTest
import Testing
@testable import ShutterManager

@MainActor
@Suite(.serialized)
struct TipJarStoreTests {
    /// The configuration file, found from this source file so the test needs no bundle resource.
    private static let configuration = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ShutterManager.storekit")

    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(contentsOf: Self.configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test func theConfigurationListsEveryTip() throws {
        let data = try Data(contentsOf: Self.configuration)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try #require(json["products"] as? [[String: Any]])
        #expect(Set(products.compactMap { $0["productID"] as? String }) == Set(TipProduct.allCases.map(\.rawValue)))
        #expect(products.allSatisfy { $0["type"] as? String == "Consumable" }, "Tips unlock nothing")
    }

    @Test func tipsLoadCheapestFirstAndATipSaysThanks() async throws {
        let session = try makeSession()
        let store = TipJarStore()
        await store.load()
        #expect(store.products.map(\.id) == TipProduct.allCases.map(\.rawValue))
        #expect(store.statusMessage == nil)

        let small = try #require(store.products.first)
        await store.tip(small)
        #expect(store.didTip)
        #expect(store.statusMessage == nil)
        #expect(store.purchasingID == nil)
        #expect(session.allTransactions().count == 1)
    }
}
