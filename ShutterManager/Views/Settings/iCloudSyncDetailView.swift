//
//  iCloudSyncDetailView.swift
//  ShutterManager
//
//  iCloud sync status, recent activity and what syncs.
//

import SwiftUI

struct iCloudSyncDetailView: View {
    @Environment(iCloudSyncManager.self) private var syncManager

    var body: some View {
        GeometryReader { geometry in
            let constants = ResponsiveConstants(geometry)
            List {
                Section {
                    SettingsRow(icon: syncManager.status.icon,
                                iconColor: syncManager.isAvailable ? .green : .secondary,
                                title: syncManager.status.displayText, constants: constants)
                        .accessibilityIdentifier("icloud.status")
                } footer: {
                    Text(syncManager.detailText)
                }

                if syncManager.storageMode == .cloudKit {
                    Section {
                        LabeledContent("Last upload", value: syncManager.lastUpload.map(formatDate) ?? "Not yet observed")
                        LabeledContent("Last download", value: syncManager.lastDownload.map(formatDate) ?? "Not yet observed")
                    } header: {
                        Text("Activity this session")
                    } footer: {
                        Text("Completed transfers on this device. Check your other devices to confirm changes arrived.")
                    }
                    Section {
                        Button("Check iCloud Status") {
                            Task { await syncManager.refresh() }
                        }
                        .disabled(syncManager.isCheckingAccount)
                        .accessibilityIdentifier("icloud.checkStatus")
                    } footer: {
                        Text("Checks your account availability. iCloud schedules transfers automatically.")
                    }
                }

                Section("What syncs") {
                    Text("Gear and photos, maintenance history and reminders, shutter counts, and loans.")
                    Text("App preferences and backup files stay on each device.")
                        .foregroundStyle(.secondary)
                }

                if let message = syncManager.diagnosticMessage {
                    Section("Details") {
                        Text(message)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task { await syncManager.refresh() }
    }
}
