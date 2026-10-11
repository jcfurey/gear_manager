//
//  AboutView.swift
//  ShutterManager
//
//  About screen and the in-app privacy policy.
//

import SwiftUI

/// App information: what it does and who makes it. The version is shown in Settings.
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                    Text(Constants.App.name)
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Your camera gear, in order, and the tools to use it")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Features")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                    FeatureRow(icon: "camera", title: "Inventory",
                               description: "Bodies, lenses, lighting, drones and everything else, with photos, serial numbers and values. Fill in a camera's or lens's details from a photo it took.")
                    FeatureRow(icon: "wrench.and.screwdriver", title: "Care and Use",
                               description: "Shutter counts against rated life, sensor cleanings, maintenance, and loans, with reminders")
                    FeatureRow(icon: "plusminus.circle", title: "Photography Tools",
                               description: "Exposure, ND filters, depth of field, field of view, astro, time-lapse, flash and print size")
                    FeatureRow(icon: "film", title: "Film",
                               description: "Reciprocity from the makers' datasheets, a development timer for your recipes, and a roll log")
                    FeatureRow(icon: "camera.aperture", title: "Light Meter",
                               description: "A reflected-light reading from the camera, solved for aperture, shutter or ISO")
                    FeatureRow(icon: "sun.horizon", title: "Sun, Moon and Milky Way",
                               description: "Golden and blue hours, twilight, moon phases and dark, moonless nights for any place")
                    FeatureRow(icon: "calendar", title: "Shoots",
                               description: "Plan shoots with that day's light, pack with kits, and tick off shot lists")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Developer")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text("Made by Furey Labs, for photographers. Free, with no ads, no subscriptions and no tracking; an optional tip jar supports development.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Icon + title + description row used in the About feature list.
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The privacy policy, from `PrivacyPolicy` (which docs/PRIVACY.md mirrors for the public page).
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                Text("Last updated: \(PrivacyPolicy.lastUpdated)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(PrivacyPolicy.sections, id: \.title) { section in
                        PrivacySection(title: section.title, content: section.body)
                    }
                }

                Text(PrivacyPolicy.closingNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top)
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Titled block of body text within the privacy policy.
struct PrivacySection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            Text(content)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
    .preferredColorScheme(.dark)
}
