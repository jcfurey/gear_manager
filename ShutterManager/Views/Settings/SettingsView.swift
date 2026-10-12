//
//  SettingsView.swift
//  ShutterManager
//
//  Root settings screen: appearance and haptics, reminders, iCloud sync, data (backups,
//  export, import, clear), and about. Preferences persist via @AppStorage
//  (Constants.UserDefaultsKeys).
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "SettingsView")

struct SettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(iCloudSyncManager.self) private var syncManager

    /// All gear, to reschedule reminders when the preference changes.
    @Query private var gearItems: [GearItem]

    @AppStorage(Constants.UserDefaultsKeys.hapticFeedback) private var hapticFeedback = true
    @AppStorage(Constants.UserDefaultsKeys.darkModePreference) private var darkModePreference = "system"
    /// Master switch for gear reminders. The schedule and time are per item.
    @AppStorage(Constants.UserDefaultsKeys.gearRemindersEnabled) private var gearRemindersEnabled = false
    @AppStorage(Constants.UserDefaultsKeys.measurementUnits) private var measurementUnits = UnitPreference.automatic
    @AppStorage(Constants.UserDefaultsKeys.depthOfFieldStandard) private var depthOfFieldStandard = CircleOfConfusionStandard.standard
    @AppStorage(Constants.UserDefaultsKeys.lightMeterCalibration) private var lightMeterCalibration = 0.0

    @State private var showingDataExport = false
    @State private var showingDataImport = false
    @State private var showingDeleteConfirmation = false
    @State private var clearFailed = false

    var body: some View {
        GeometryReader { geometry in
            let constants = ResponsiveConstants(geometry, dynamicTypeSize: dynamicTypeSize)

            NavigationStack {
                List {
                    Section("App Preferences") {
                        SettingsRow(icon: "paintbrush", iconColor: .purple, title: "Appearance", constants: constants) {
                            Picker("Appearance", selection: $darkModePreference) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                            .pickerStyle(.menu)
                            .font(constants.bodyFont)
                        }

                        SettingsRow(icon: "iphone.radiowaves.left.and.right", iconColor: .orange, title: "Haptic Feedback", constants: constants) {
                            Toggle("", isOn: $hapticFeedback)
                                .labelsHidden()
                                .accessibilityLabel("Haptic Feedback")
                                .accessibilityIdentifier("settings.haptics")
                                .onChange(of: hapticFeedback) { _, _ in
                                    HapticFeedbackManager.shared.toggle()
                                }
                        }
                    }

                    Section {
                        SettingsRow(icon: "bell.badge", iconColor: .red, title: "Gear Reminders", constants: constants) {
                            Toggle("", isOn: $gearRemindersEnabled)
                                .labelsHidden()
                                .accessibilityLabel("Gear Reminders")
                                .accessibilityIdentifier("settings.gearReminders")
                                .onChange(of: gearRemindersEnabled) { _, enabled in
                                    HapticFeedbackManager.shared.toggle()
                                    if enabled {
                                        Task { @MainActor in
                                            await NotificationManager.shared.requestAuthorization()
                                            NotificationManager.shared.updateGearRemindersEnabled(true)
                                            await NotificationManager.shared.refreshGearReminders(for: gearItems)
                                        }
                                    } else {
                                        NotificationManager.shared.updateGearRemindersEnabled(false)
                                    }
                                }
                        }
                    } header: {
                        Text("Reminders")
                    } footer: {
                        Text("Sensor cleanings due and loans due back. Set each item's schedule and reminder time in Inventory.")
                    }

                    Section {
                        SettingsRow(icon: "ruler", iconColor: .teal, title: "Units", constants: constants) {
                            Picker("Units", selection: $measurementUnits) {
                                ForEach(UnitPreference.allCases) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .font(constants.bodyFont)
                            .accessibilityIdentifier("settings.units")
                        }
                        SettingsRow(icon: "scope", iconColor: .indigo, title: "Depth of Field", constants: constants) {
                            Picker("Depth of Field", selection: $depthOfFieldStandard) {
                                ForEach(CircleOfConfusionStandard.allCases) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .font(constants.bodyFont)
                        }
                        SettingsRow(icon: "camera.aperture", iconColor: .orange, title: "Light Meter", constants: constants) {
                            Stepper(value: Binding(get: { lightMeterCalibration },
                                                   set: { lightMeterCalibration = ($0 * 10).rounded() / 10 }),
                                    in: LightMeter.calibrationRange, step: 0.1) {
                                Text("\(LightMeter.signedEVLabel(lightMeterCalibration)) EV")
                                    .font(constants.bodyFont)
                                    .monospacedDigit()
                            }
                            .fixedSize()
                            .accessibilityLabel("Light meter calibration")
                            .accessibilityValue("\(LightMeter.signedEVLabel(lightMeterCalibration)) EV")
                            .accessibilityIdentifier("settings.meterCalibration")
                        }
                    } header: {
                        Text("Tools")
                    } footer: {
                        Text("Automatic units follow your region. The depth-of-field standard sets how strict \"sharp\" is: \(depthOfFieldStandard.detail.lowercased()). The light meter's calibration is added to every reading: raise it if photos come out too bright, lower it if they come out too dark, or calibrate against a meter you trust in the Light Meter tab.")
                    }

                    Section("iCloud Sync") {
                        NavigationLink {
                            iCloudSyncDetailView()
                        } label: {
                            SettingsRow(icon: syncManager.status.icon,
                                        iconColor: syncManager.isAvailable ? .green : .secondary,
                                        title: "iCloud Sync",
                                        constants: constants) {
                                Text(syncManager.status.displayText)
                                    .font(constants.captionFont)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .accessibilityIdentifier("settings.icloud")
                    }

                    Section("Data") {
                        NavigationLink {
                            BackupManagementView()
                        } label: {
                            SettingsRow(icon: "arrow.clockwise.icloud", iconColor: .cyan, title: "Backups", constants: constants)
                        }
                        .accessibilityIdentifier("settings.backups")

                        Button {
                            HapticFeedbackManager.shared.buttonTap()
                            showingDataExport = true
                        } label: {
                            SettingsRow(icon: "square.and.arrow.up", iconColor: .blue, title: "Export Data", constants: constants) {
                                Image(systemName: "chevron.right")
                                    .font(constants.captionFont)
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityIdentifier("settings.export")

                        Button {
                            HapticFeedbackManager.shared.buttonTap()
                            showingDataImport = true
                        } label: {
                            SettingsRow(icon: "square.and.arrow.down", iconColor: .green, title: "Import Data", constants: constants) {
                                Image(systemName: "chevron.right")
                                    .font(constants.captionFont)
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityIdentifier("settings.import")

                        Button {
                            HapticFeedbackManager.shared.buttonTap()
                            showingDeleteConfirmation = true
                        } label: {
                            SettingsRow(icon: "trash", iconColor: .red, title: "Clear All Data", titleColor: .red, constants: constants)
                        }
                    }

                    Section("About") {
                        SettingsRow(icon: "info.circle", iconColor: .blue, title: "Version", constants: constants) {
                            Text("\(Constants.App.version) (\(Constants.App.build))")
                                .foregroundColor(.secondary)
                                .font(constants.bodyFont)
                        }

                        NavigationLink {
                            AboutView()
                        } label: {
                            SettingsRow(icon: "person.circle", iconColor: .purple, title: "About the App", constants: constants)
                        }

                        NavigationLink {
                            TipJarView()
                        } label: {
                            SettingsRow(icon: "heart", iconColor: .pink, title: "Tip Jar", constants: constants)
                        }
                        .accessibilityIdentifier("settings.tipJar")

                        NavigationLink {
                            PrivacyPolicyView()
                        } label: {
                            SettingsRow(icon: "hand.raised", iconColor: .orange, title: "Privacy Policy", constants: constants)
                        }

                        if let support = URL(string: "mailto:\(Constants.App.supportEmail)") {
                            Link(destination: support) {
                                SettingsRow(icon: "envelope", iconColor: .green, title: "Contact Support", constants: constants) {
                                    Image(systemName: "arrow.up.right")
                                        .font(constants.captionFont)
                                        .foregroundColor(.secondary)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Settings")
            }
        }
        .confirmationDialog("Clear All Data", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Clear All Data", role: .destructive) {
                HapticFeedbackManager.shared.delete()
                clearAllData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes all your gear, photos, maintenance history, shutter counts, loans, development recipes, saved places, shoots, kits, shot-list templates and film rolls, on every device signed in to your iCloud account. Settings and local backups are kept.")
        }
        .alert("Couldn't Clear Data", isPresented: $clearFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Nothing was deleted. Please try again.")
        }
        .sheet(isPresented: $showingDataExport) {
            EnhancedDataExportView()
        }
        .sheet(isPresented: $showingDataImport) {
            DataImportView()
        }
    }

    private func clearAllData() {
        do {
            // Every model in the schema, so nothing is left orphaned or forgotten.
            try modelContext.deleteEveryRecord()
            try modelContext.save()
            // No gear or shoots means no reminders: this removes every pending one.
            Task {
                await NotificationManager.shared.refreshGearReminders(for: [])
                await ShootAlertScheduler.refresh(shoots: [])
            }
        } catch {
            logger.error("Failed to clear data: \(error.localizedDescription, privacy: .public)")
            modelContext.rollback()
            clearFailed = true
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewModelContainer.make())
        .environment(iCloudSyncManager())
        .preferredColorScheme(.dark)
}
