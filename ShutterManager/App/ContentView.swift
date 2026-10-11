//
//  ContentView.swift
//  ShutterManager
//
//  The five-tab root: Inventory · Tools · Light Meter · Shoots · Settings.
//

import SwiftUI
import SwiftData

/// The app's root tab view.
struct ContentView: View {
    @AppStorage(Constants.UserDefaultsKeys.darkModePreference) private var darkModePreference = "system"

    /// App-lifetime tip-jar store, held here rather than in TipJarView so its
    /// `Transaction.updates` listener covers the whole session: an Ask-to-Buy approval that lands
    /// while the Tip Jar screen is closed is still finished.
    @State private var tipJarStore = TipJarStore()
    @State private var navigation = AppNavigation()

    private var colorScheme: ColorScheme? {
        switch darkModePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Inventory", systemImage: "camera", value: AppTab.inventory) {
                InventoryView()
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver", value: AppTab.tools) {
                ToolsView()
            }
            Tab("Light Meter", systemImage: "camera.aperture", value: AppTab.lightMeter) {
                LightMeterView()
            }
            Tab("Shoots", systemImage: "calendar", value: AppTab.shoots) {
                ComingSoonTab(title: "Shoots", systemImage: "calendar",
                              message: "Shoot logs, kits, shot lists and film rolls are on the way.")
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .environment(tipJarStore)
        .environment(navigation)
        .toast()
        .preferredColorScheme(colorScheme)
    }
}

/// Stands in for a tab until its feature lands.
private struct ComingSoonTab: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewModelContainer.make())
        .environment(iCloudSyncManager())
}
