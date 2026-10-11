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
                    Text(Constants.App.name)
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Your camera gear, in order")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Features")
                        .font(.headline)
                        .fontWeight(.semibold)
                    FeatureRow(icon: "camera", title: "Inventory",
                               description: "Bodies, lenses, lighting, drones and everything else, with photos, serial numbers and values")
                    FeatureRow(icon: "photo.badge.magnifyingglass", title: "Fill from a Photo",
                               description: "Read a camera's or lens's details from a photo it took")
                    FeatureRow(icon: "chart.xyaxis.line", title: "Shutter Count",
                               description: "Track actuations against the shutter's rated life")
                    FeatureRow(icon: "arrow.left.arrow.right", title: "Loans and Rentals",
                               description: "Know who has your gear and when it's due back")
                    FeatureRow(icon: "wrench.and.screwdriver", title: "Maintenance",
                               description: "Sensor cleanings, firmware updates and repairs, with reminders")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Developer")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Made by Furey Labs, for photographers.")
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
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// The privacy policy. Keep it in step with what the app actually does: every new permission,
/// network connection or data type needs a line here.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                Text("Last updated: October 11, 2026")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    PrivacySection(title: "What the App Stores", content: """
                        \(Constants.App.name) has no account system, no ads, no analytics and no tracking. Your library is stored on your device and, when iCloud is on, in your own private iCloud database:

                        • Gear you enter: makes, models, serial numbers, specifications, values and notes
                        • Photos you add to your gear
                        • Maintenance history, shutter counts and loans
                        • Development recipes and places you save
                        • App settings
                        """)

                    PrivacySection(title: "Where It Goes", content: """
                        • Your library is stored with Apple's SwiftData and, when iCloud is on, synced to your private iCloud database (CloudKit). The developer runs no servers and can't see it.
                        • Exports and backups go only where you send them. Local backups include photos by default and can keep records you later delete.
                        • Recovery tools can export the stored database and photos; nothing is sent automatically.
                        """)

                    PrivacySection(title: "Camera and Photos", content: """
                        • The camera is used to scan barcodes and as a light meter. Frames are processed on your device and never stored or sent; the light meter reads only the camera's exposure settings.
                        • Photos are chosen with the system photo picker; the app can't see the rest of your library and never saves to it.
                        • "Fill from a Photo" reads the camera and lens details in a photo's metadata on your device. The photo itself isn't kept.
                        • Gear photos are resized before they're stored, and their location data is removed.
                        """)

                    PrivacySection(title: "Location and Maps", content: """
                        • Your location is read only when you tap "Use My Location" in the sun, moon and Milky Way planners, and only while the app is open. It's used on your device to work out sun and moon times, and isn't stored unless you save it as a place.
                        • Places you save sync to your private iCloud database with the rest of your library.
                        • Maps, place search and place names come from Apple Maps (MapKit). Searches you type, and the points you pick on the map, are sent to Apple to find places and their names.
                        """)

                    PrivacySection(title: "Notifications", content: """
                        Reminders for sensor cleanings and loans due back, and alerts for running exposure and development timers, are scheduled on your device. Nothing is sent to a server.
                        """)

                    PrivacySection(title: "Other Services", content: """
                        • Barcode lookup: when you scan a barcode, its number is sent to UPCitemdb (upcitemdb.com) to look up the product. Product images it returns are downloaded from their hosts. You can always enter gear by hand instead.
                        • Marketplace searches and your reference links open in your browser, and searches include the make and model shown.
                        • Tip Jar purchases go through Apple; the app never sees payment details.
                        """)

                    PrivacySection(title: "Deleting Your Data", content: """
                        • Delete any item, along with its photos and history.
                        • Clear all data from Settings.
                        • Delete local backups and exported copies separately if you no longer want them.
                        • Uninstalling removes the app's data from that device. With iCloud on, your data stays in your private iCloud until you remove it in iCloud settings.
                        """)

                    PrivacySection(title: "Contact", content: """
                        \(Constants.App.name) is made by Furey Labs. Questions about this policy: jcfurey@furey-labs.com
                        """)
                }

                Text("This policy may change as the app does; significant changes will be noted in the app.")
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
