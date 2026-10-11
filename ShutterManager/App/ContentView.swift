//
//  ContentView.swift
//  ShutterManager
//
//  The five-tab root: Inventory · Tools · Light Meter · Shoots · Settings.
//

import SwiftUI

/// The app's root tab view.
struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Inventory", systemImage: "camera") {
                PlaceholderTab(title: "Inventory", systemImage: "camera")
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver") {
                PlaceholderTab(title: "Tools", systemImage: "wrench.and.screwdriver")
            }
            Tab("Light Meter", systemImage: "camera.aperture") {
                PlaceholderTab(title: "Light Meter", systemImage: "camera.aperture")
            }
            Tab("Shoots", systemImage: "calendar") {
                PlaceholderTab(title: "Shoots", systemImage: "calendar")
            }
            Tab("Settings", systemImage: "gearshape") {
                PlaceholderTab(title: "Settings", systemImage: "gearshape")
            }
        }
    }
}

/// Stands in for a tab until its feature lands.
private struct PlaceholderTab: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming soon."))
                .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
}
