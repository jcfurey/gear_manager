//
//  PrivacyPolicy.swift
//  ShutterManager
//
//  The privacy policy text, in one place: the in-app screen shows it, and docs/PRIVACY.md is the
//  same text as Markdown for the public page App Store Connect links to. Foundation-only, so a
//  test (on Linux too) checks that the file still matches.
//

import Foundation

enum PrivacyPolicy {
    static let appName = "Shutter Manager"
    static let contactEmail = "jcfurey@furey-labs.com"
    static let lastUpdated = "October 11, 2026"

    struct Section: Hashable {
        let title: String
        /// Paragraphs and "• " bullet lines, separated by newlines.
        let body: String
    }

    /// Keep these in step with what the app does: every new permission, network connection or
    /// type of data needs a line here. Then regenerate docs/PRIVACY.md (see `markdown`).
    static let sections: [Section] = [
        Section(title: "What the App Stores", body: """
            \(appName) has no account system, no ads, no analytics and no tracking. Your library is stored on your device and, when iCloud is on, in your own private iCloud database:

            • Gear you enter: makes, models, serial numbers, specifications, values and notes
            • Photos you add to your gear
            • Maintenance history, shutter counts and loans
            • Development recipes and places you save
            • Shoots you plan or log, with their places, clients, shot lists and packing ticks
            • Kits, shot-list templates and film rolls
            • App settings
            """),
        Section(title: "Where It Goes", body: """
            • Your library is stored with Apple's SwiftData and, when iCloud is on, synced to your private iCloud database (CloudKit). The developer runs no servers and can't see it.
            • Exports and backups go only where you send them. Local backups include photos by default and can keep records you later delete.
            • Recovery tools can export the stored database and photos; nothing is sent automatically.
            """),
        Section(title: "Camera and Photos", body: """
            • The camera is used to scan barcodes and as a light meter. Frames are processed on your device and never stored or sent; the light meter reads only the camera's exposure settings.
            • Photos are chosen with the system photo picker; the app can't see the rest of your library and never saves to it.
            • "Fill from a Photo" reads the camera and lens details in a photo's metadata on your device. The photo itself isn't kept.
            • Gear photos are resized before they're stored, and their location data is removed.
            """),
        Section(title: "Location and Maps", body: """
            • Your location is read only when you tap "Use My Location" in the sun, moon and Milky Way planners, and only while the app is open. It's used on your device to work out sun and moon times, and isn't stored unless you save it as a place.
            • Places you save, and the places of your shoots, sync to your private iCloud database with the rest of your library.
            • Maps, place search and place names come from Apple Maps (MapKit). Searches you type, and the points you pick on the map, are sent to Apple to find places and their names.
            """),
        Section(title: "Notifications", body: """
            Reminders for sensor cleanings and loans due back, alerts for running exposure and development timers, and golden-hour heads-ups for shoots you plan are scheduled on your device. Nothing is sent to a server.
            """),
        Section(title: "Other Services", body: """
            • Barcode lookup: when you scan a barcode, its number is sent to UPCitemdb (upcitemdb.com) to look up the product. Product images it returns are downloaded from their hosts. You can always enter gear by hand instead.
            • Marketplace searches and your reference links open in your browser, and searches include the make and model shown.
            • Tip Jar purchases go through Apple; the app never sees payment details.
            """),
        Section(title: "Deleting Your Data", body: """
            • Delete any item, along with its photos and history.
            • Clear all data from Settings.
            • Delete local backups and exported copies separately if you no longer want them.
            • Uninstalling removes the app's data from that device. With iCloud on, your data stays in your private iCloud until you remove it in iCloud settings.
            """),
        Section(title: "Contact", body: """
            \(appName) is made by Furey Labs. Questions about this policy: \(contactEmail)
            """)
    ]

    static let closingNote = "This policy may change as the app does; significant changes will be noted in the app."

    /// The policy as Markdown: the contents of docs/PRIVACY.md. After changing the text, write
    /// this out to that file (the Linux test script prints it with `--print-privacy-policy`).
    static var markdown: String {
        var lines = ["# \(appName) Privacy Policy", "", "Last updated: \(lastUpdated)", ""]
        for section in sections {
            lines += ["## \(section.title)", ""]
            lines += section.body.components(separatedBy: "\n").map { line in
                line.hasPrefix("• ") ? "- " + line.dropFirst(2) : line
            }
            lines.append("")
        }
        lines += ["_\(closingNote)_", ""]
        return lines.joined(separator: "\n")
    }
}
