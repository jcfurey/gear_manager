//
//  BackupManagementView.swift
//  ShutterManager
//
//  Backup settings, manual backups, and the backup history with restore and delete.

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "BackupManagementView")

/// Backup configuration (enable, frequency, retention), manual backup, and a history list
/// with restore/delete actions. Backed by BackupManager; restores replace current data.
struct BackupManagementView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext


    @StateObject private var backupManager = BackupManager()
    @State private var showingRestoreConfirmation = false
    @State private var selectedBackup: BackupMetadata?
    @State private var showingDeleteConfirmation = false
    @State private var backupToDelete: BackupMetadata?
    
    var body: some View {
        GeometryReader { geometry in
            let constants = ResponsiveConstants(geometry, dynamicTypeSize: dynamicTypeSize)
            
            List {
                    // Backup Configuration
                    Section {
                        Toggle("Enable Automatic Backups", isOn: $backupManager.configuration.isEnabled)
                            .onChange(of: backupManager.configuration.isEnabled) { _, _ in
                                HapticFeedbackManager.shared.toggle()
                                backupManager.saveConfiguration()
                            }
                        
                        if backupManager.configuration.isEnabled {
                            Picker("Frequency", selection: $backupManager.configuration.frequency) {
                                ForEach(BackupManager.BackupConfiguration.BackupFrequency.allCases, id: \.self) { frequency in
                                    Text(frequency.rawValue).tag(frequency)
                                }
                            }
                            .onChange(of: backupManager.configuration.frequency) { _, _ in
                                HapticFeedbackManager.shared.selection()
                                backupManager.saveConfiguration()
                            }
                            
                            Stepper("Keep \(backupManager.configuration.maxBackups) backups", value: $backupManager.configuration.maxBackups, in: 1...30)
                                .onChange(of: backupManager.configuration.maxBackups) { _, _ in
                                    backupManager.saveConfiguration()
                                }
                        }
                        
                        Toggle("Include Photos", isOn: $backupManager.configuration.includePhotos)
                            .onChange(of: backupManager.configuration.includePhotos) { _, _ in
                                backupManager.saveConfiguration(confirmPhotoChoice: true)
                            }
                        if !backupManager.configuration.includePhotos {
                            Text("These backups cannot restore gear or maintenance photos.")
                                .font(constants.captionFont)
                                .foregroundStyle(.orange)
                        }
                        if let lastBackup = backupManager.lastBackupDate {
                            HStack {
                                Text("Last Backup")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(lastBackup.formatted(date: .abbreviated, time: .shortened))
                                    .font(constants.captionFont)
                            }
                        }
                        // Automatic backups run while the app goes to the background, so their
                        // failures were only logged and the schedule could stop unnoticed.
                        if let failure = backupManager.lastAutomaticBackupFailure {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Last automatic backup failed")
                                        .font(constants.bodyFont.weight(.medium))
                                    Text(formatDetailedDate(failure.date))
                                        .font(constants.captionFont)
                                        .foregroundStyle(.secondary)
                                    Text(failure.message)
                                        .font(constants.captionFont)
                                    Text("Create a backup now to check that backups work again.")
                                        .font(constants.captionFont)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("automaticBackupFailure")
                        }
                    } header: {
                        Text("Automatic Backups")
                    } footer: {
                        Text("Saved on this device when you leave the app, if due.")
                            .font(constants.captionFont)
                    }
                    
                    // Manual Backup
                    Section {
                        Button(action: createManualBackup) {
                            HStack {
                                if backupManager.isBackingUp {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Creating Backup...")
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                        .accessibilityHidden(true)
                                    Text("Create Backup Now")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(backupManager.isBackingUp)
                        .buttonStyle(.borderedProminent)
                    } footer: {
                        if let error = backupManager.lastBackupError {
                            Text("Error: \(error)")
                                .foregroundColor(.red)
                        } else if backupManager.lastBackupReplacedValueCount > 0 {
                            // Values a backup can't hold (left by an older version or a mistyped
                            // unit) are written as blanks or zeros so the rest is backed up.
                            let count = backupManager.lastBackupReplacedValueCount
                            Text("Backed up. \(count) value\(count == 1 ? " that wasn't a usable number was" : "s that weren't usable numbers were") saved as blank or zero; your library keeps the originals.")
                                .accessibilityIdentifier("backup.replacedValues")
                        }
                    }
                    
                    // Backup History
                    Section {
                        if backupManager.availableBackups.isEmpty {
                            EmptyStateView.noBackups()
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .frame(minHeight: 200)
                        } else {
                            ForEach(backupManager.availableBackups) { backup in
                                // Tap = restore (behind the existing confirmation alert). The row
                                // displayed a disclosure chevron but had no tap action at all —
                                // Restore/Delete were reachable only via unhinted long-press/swipe.
                                Button {
                                    HapticFeedbackManager.shared.buttonTap()
                                    selectedBackup = backup
                                    showingRestoreConfirmation = true
                                } label: {
                                    BackupRow(backup: backup, constants: constants)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Restores this backup, after you confirm")
                                    .contextMenu {
                                        Button {
                                            HapticFeedbackManager.shared.buttonTap()
                                            selectedBackup = backup
                                            showingRestoreConfirmation = true
                                        } label: {
                                            Label("Restore", systemImage: "arrow.clockwise")
                                        }
                                        
                                        Button(role: .destructive) {
                                            HapticFeedbackManager.shared.delete()
                                            backupToDelete = backup
                                            showingDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            backupToDelete = backup
                                            showingDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            selectedBackup = backup
                                            showingRestoreConfirmation = true
                                        } label: {
                                            Label("Restore", systemImage: "arrow.clockwise")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        }
                    } header: {
                        Text("Backup History")
                    }
                }
            .navigationTitle("Backup Management")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Restore Backup", isPresented: $showingRestoreConfirmation) {
                    Button("Cancel", role: .cancel) {
                        selectedBackup = nil
                    }
                    Button("Restore", role: .destructive) {
                        if let backup = selectedBackup {
                            HapticFeedbackManager.shared.buttonTap()
                            restoreBackup(backup)
                        }
                    }
                } message: {
                    Text(selectedBackup?.restoreMessage ?? "This will replace current data with the backup.")
                }
            .alert("Delete Backup", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    backupToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let backup = backupToDelete {
                        deleteBackup(backup)
                    }
                }
            } message: {
                Text("Are you sure you want to delete this backup?")
            }
        }
    }
    
    private func createManualBackup() {
        HapticFeedbackManager.shared.buttonTap()
        Task {
            do {
                try await backupManager.createBackup(library: try LibraryContents.fetch(from: modelContext))
                HapticFeedbackManager.shared.exportSuccess()
            } catch {
                HapticFeedbackManager.shared.error()
                logger.error("Backup failed: \(error.localizedDescription, privacy: .public)")
                ToastNotificationManager.shared.backupFailed(error.localizedDescription)
            }
        }
    }
    
    private func restoreBackup(_ backup: BackupMetadata) {
        Task {
            do {
                try await backupManager.restoreBackup(backup, to: modelContext)
                selectedBackup = nil
                // A restore replaces the whole library in other tabs; without this the only
                // visible outcome on this screen was nothing at all.
                ToastNotificationManager.shared.backupRestored()
            } catch {
                logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
                ToastNotificationManager.shared.restoreFailed(error.localizedDescription)
            }
        }
    }
    
    private func deleteBackup(_ backup: BackupMetadata) {
        do {
            try backupManager.deleteBackup(backup)
            backupToDelete = nil
        } catch {
            logger.error("Delete failed: \(error.localizedDescription, privacy: .public)")
            ToastNotificationManager.shared.deleteFailed(error.localizedDescription)
        }
    }
}

// MARK: - Supporting Views

/// History-list row for a single backup: date, size, total item count, and a per-type
/// badge breakdown.
struct BackupRow: View {
    let backup: BackupMetadata
    let constants: ResponsiveConstants
    
    var body: some View {
        VStack(alignment: .leading, spacing: constants.itemSpacing / 2) {
            HStack {
                Image(systemName: "doc.zipper")
                    .foregroundColor(.blue)
                    .font(.system(size: constants.iconSize))
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.formattedDate)
                        .font(constants.bodyFont.weight(.medium))

                    Text(backup.formattedSize)
                        .font(constants.captionFont)
                        .foregroundColor(.secondary)
                    Text(backup.photoSummary)
                        .font(constants.captionFont)
                        .foregroundStyle(backup.includesPhotos == true ? Color.secondary : Color.orange)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(backup.isRecovered ? "Recovered file" : "\(backup.itemCounts.totalItems) items")
                        .font(constants.captionFont)
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(constants.footnoteFont)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
            
            // Item breakdown
            HStack(spacing: constants.itemSpacing) {
                if backup.itemCounts.gearItems > 0 {
                    ItemCountBadge(
                        icon: "camera",
                        count: backup.itemCounts.gearItems,
                        color: .orange,
                        label: "gear items",
                        constants: constants
                    )
                }
                
                if backup.itemCounts.otherRecords > 0 {
                    ItemCountBadge(
                        icon: "list.bullet.rectangle",
                        count: backup.itemCounts.otherRecords,
                        color: .blue,
                        label: "maintenance, shutter-count and loan records",
                        constants: constants
                    )
                }
            }
        }
        .padding(.vertical, constants.itemSpacing / 4)
    }
}

/// Small colored icon + count pill for one data type within a BackupRow.
struct ItemCountBadge: View {
    let icon: String
    let count: Int
    let color: Color
    /// Spoken name of the data type: the icon and color alone don't tell VoiceOver what "12" counts.
    var label: String = ""
    let constants: ResponsiveConstants

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(constants.footnoteFont)
            Text("\(count)")
                .font(constants.footnoteFont)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.15))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "\(count)" : "\(count) \(label)")
    }
}

#Preview {
    BackupManagementView()
        .modelContainer(PreviewModelContainer.make())
        .preferredColorScheme(.dark)
}
