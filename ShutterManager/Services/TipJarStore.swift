//
//  TipJarStore.swift
//  ShutterManager
//
//  StoreKit 2 store for the optional "tip jar." Tips are consumables — they unlock nothing, so
//  there's no entitlement to persist: we load the products, process the purchase, finish the
//  (consumable) transaction, and thank the user. The app is fully functional without ever tipping,
//  and all payment is handled by Apple's In-App Purchase (no external payment links).
//

import Foundation
import StoreKit
import os

/// Identifiers for the tip-jar consumables. These must match the In-App Purchase products created
/// in App Store Connect exactly (and any local `.storekit` configuration used for testing).
enum TipProduct: String, CaseIterable {
    case small  = "jcameronfurey.shuttermanager.tip.small"
    case medium = "jcameronfurey.shuttermanager.tip.medium"
    case large  = "jcameronfurey.shuttermanager.tip.large"

    /// Emoji shown beside the tier. The real, localized name and price come from StoreKit.
    var emoji: String {
        switch self {
        case .small:  return "☕️"
        case .medium: return "🍔"
        case .large:  return "📸"
        }
    }
}

/// Loads and purchases the optional tip-jar products via StoreKit 2.
@MainActor
@Observable
final class TipJarStore {
    /// Loaded tip products, cheapest first. Empty until `load()` succeeds.
    private(set) var products: [Product] = []
    /// The product currently being purchased — drives the per-row spinner and disables the others.
    private(set) var purchasingID: Product.ID?
    /// Flips true after a successful tip so the view can show a thank-you.
    var didTip = false
    /// User-facing message shown when loading or purchasing fails (nil when all is well).
    private(set) var statusMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "TipJarStore")

    init() {
        // Finish any transaction that arrives outside the direct purchase call — an "Ask to Buy"
        // approval that lands later, or a purchase interrupted and completed afterward. Consumables
        // carry no entitlement, so we just finish them so StoreKit stops re-delivering, and set
        // didTip so an out-of-band tip is acknowledged when the Tip Jar screen is showing.
        //
        // For this to catch transactions that arrive while Tip Jar ISN'T open, the owning store must
        // live at app scope (ContentView holds it and injects it) — Apple's guidance is to observe
        // Transaction.updates for the app's lifetime, not a single screen's.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { break }
                if let transaction = try? self.checkVerified(update) {
                    await transaction.finish()
                    self.didTip = true
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    /// Fetch the tip products from the App Store, sorted by price ascending.
    func load() async {
        do {
            let loaded = try await Product.products(for: TipProduct.allCases.map(\.rawValue))
            products = loaded.sorted { $0.price < $1.price }
            statusMessage = products.isEmpty ? "Tips aren't available right now." : nil
        } catch {
            statusMessage = "Couldn't load tips. Please check your connection and try again."
            logger.error("Tip product load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Purchase a tip. On success, finishes the consumable transaction and sets `didTip`.
    func tip(_ product: Product) async {
        guard purchasingID == nil else { return }
        purchasingID = product.id
        statusMessage = nil   // clear any stale message from a previous attempt
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                didTip = true
                statusMessage = nil
            case .pending:
                // Ask to Buy / Strong Customer Authentication: the purchase needs approval and
                // arrives later via Transaction.updates. Tell the user instead of looking like a
                // silent no-op (previously .pending was lumped with .userCancelled).
                statusMessage = "Waiting for approval — your tip completes once it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            statusMessage = "The tip didn't go through. Please try again."
            logger.error("Tip purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns the verified payload, or throws if StoreKit couldn't verify the signature.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified:         throw TipJarError.failedVerification
        }
    }
}

enum TipJarError: Error {
    case failedVerification
}
