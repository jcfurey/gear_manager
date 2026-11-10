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
            // Rebuilt when the library is replaced; Settings, where that's done from, stays put.
            Tab("Inventory", systemImage: "camera", value: AppTab.inventory) {
                InventoryView().id(navigation.libraryGeneration)
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver", value: AppTab.tools) {
                ToolsView().id(navigation.libraryGeneration)
            }
            Tab("Light Meter", systemImage: "camera.aperture", value: AppTab.lightMeter) {
                LightMeterView().id(navigation.libraryGeneration)
            }
            Tab("Shoots", systemImage: "calendar", value: AppTab.shoots) {
                ShootsView().id(navigation.libraryGeneration)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .environment(tipJarStore)
        .environment(navigation)
        // A restore or an import commits here, whichever screen started it.
        .onReceive(NotificationCenter.default.publisher(for: DataImportService.didImportNotification)
            .receive(on: DispatchQueue.main)) { _ in
            navigation.libraryWasReplaced()
        }
        // A label's code is a link to the app; the Camera app opens it here.
        .onOpenURL { navigation.open($0) }
        .sheet(item: $navigation.openedLabel) { link in
            NavigationStack {
                LabelDestinationView(link: link)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { navigation.openedLabel = nil }
                                .accessibilityIdentifier("closeLabelButton")
                        }
                    }
            }
        }
        .toast()
        .preferredColorScheme(colorScheme)
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewModelContainer.make())
        .environment(iCloudSyncManager())
}
