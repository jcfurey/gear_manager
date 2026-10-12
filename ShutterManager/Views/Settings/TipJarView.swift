//
//  TipJarView.swift
//  ShutterManager
//
//  Optional "tip jar": a few consumable In-App Purchases that let users support development.
//  Entirely optional — the app is fully functional without it. Names and prices are localized by
//  StoreKit. App Store compliant: digital tips go through In-App Purchase only (no external links).
//

import SwiftUI
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

struct TipJarView: View {
    // App-scoped (injected by ContentView) so the transaction listener runs for the whole session.
    @Environment(TipJarStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                if store.didTip {
                    thankYouBanner
                }

                content

                // Status/errors render here regardless of whether products loaded — a purchase
                // failure sets this while products is non-empty, and it was previously never shown.
                if let message = store.statusMessage {
                    statusBanner(message)
                }

                Text("Tips are one-time and don't unlock anything — they're simply a thank-you. 💛")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Tip Jar")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Fresh visit: don't show a stale thank-you from an earlier tip (the store is now
            // app-lifetime, so didTip would otherwise persist). Load products only if we don't
            // already have them.
            store.didTip = false
            if store.products.isEmpty { await store.load() }
        }
        .onChange(of: store.didTip) { _, tipped in
            // VoiceOver doesn't auto-announce the inserted banner — announce the confirmation.
            if tipped { UIAccessibility.post(notification: .announcement, argument: "Thank you for your tip!") }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundColor(.pink)
                .accessibilityHidden(true)
            Text("Enjoying \(Constants.App.name)?")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("It's free, ad-free, and built by one person at Furey Labs. If it's earned a spot on your home screen, a tip helps keep it going. Either way, thanks for being here!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top)
    }

    @ViewBuilder
    private var content: some View {
        if store.products.isEmpty {
            // Only the loading spinner lives here now; any message (load failure or "unavailable")
            // is rendered by statusBanner below, together with a retry.
            if store.statusMessage == nil {
                ProgressView()
                    .padding()
                    .accessibilityLabel("Loading tips")
            }
        } else {
            VStack(spacing: 12) {
                ForEach(store.products) { product in
                    tipRow(product)
                }
            }
        }
    }

    /// Status / error message. Offers a retry only when products failed to load (a purchase
    /// failure, with products already present, just needs the user to tap a tip again).
    private func statusBanner(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if store.products.isEmpty {
                Button("Try Again") { Task { await store.load() } }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func tipRow(_ product: Product) -> some View {
        Button {
            Task { await store.tip(product) }
        } label: {
            HStack(spacing: 14) {
                Text(TipProduct(rawValue: product.id)?.emoji ?? "🎁")
                    .font(.title2)
                Text(product.displayName)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                Spacer()
                if store.purchasingID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(store.purchasingID != nil)
        // One clean spoken label (the emoji would otherwise read as "hamburger"/"camera with flash", and the
        // spinner is unlabeled) + a state so VoiceOver conveys the in-progress purchase.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
        .accessibilityValue(store.purchasingID == product.id ? "Purchasing" : "")
        .accessibilityHint("Sends a tip")
    }

    private var thankYouBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
                .accessibilityHidden(true)
            Text("Thank you so much — it means a lot! 🎉")
                .font(.subheadline.weight(.medium))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.12))
        )
    }
}

#Preview {
    NavigationStack {
        TipJarView()
    }
    .environment(TipJarStore())
}
