//
//  DuplicateRecordsView.swift
//  ShutterManager
//
//  Settings → Find Duplicates: counts records the library holds twice and folds them into one.
//

import SwiftUI
import SwiftData

/// Looks for records held more than once (see `LibraryDeduplicator` for how that happens) and,
/// when asked, keeps one copy of each. A backup is made first.
struct DuplicateRecordsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppNavigation.self) private var navigation
    @Environment(iCloudSyncManager.self) private var syncManager

    @State private var found: LibraryDeduplicator.Report?
    @State private var removed: LibraryDeduplicator.Report?
    @State private var failure: String?
    @State private var confirming = false
    @State private var isWorking = false

    var body: some View {
        List {
            Section {
                if let removed {
                    Label(removed.total == 1 ? "Removed 1 extra copy." : "Removed \(removed.total) extra copies.",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(AppColors.goodText)
                        .accessibilityIdentifier("duplicatesRemovedLabel")
                } else if let found {
                    if found.isEmpty {
                        ContentUnavailableView("No Duplicates", systemImage: "checkmark.circle",
                            description: Text("Every record is in your library once."))
                    } else {
                        Text(found.total == 1
                             ? "1 record is in your library more than once:"
                             : "\(found.total) records are in your library more than once:")
                        ForEach(found.lines, id: \.self) { line in
                            Text(line).foregroundStyle(.secondary)
                        }
                    }
                } else if failure == nil {
                    ProgressView()
                }
                if let failure {
                    Text(failure).foregroundStyle(AppColors.badText)
                }
            } footer: {
                Text("Importing a file before iCloud has finished syncing the same library puts every record in twice. This finds records that share an ID.")
            }

            if let found, !found.isEmpty, removed == nil {
                Section {
                    Button(role: .destructive) {
                        confirming = true
                    } label: {
                        HStack {
                            Text("Remove the Extra Copies")
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("removeDuplicatesButton")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Of each set, the copy changed most recently is kept, with any photos, history and list entries that only another copy had. A backup is made first.")
                        if syncManager.storageMode == .cloudKit {
                            Text("Do this on one device only. Your other devices follow through iCloud; doing it on two at once can remove both copies of a record.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Find Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .task { look() }
        .confirmationDialog("Remove the extra copies?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("One copy of each record is kept. A backup is made first.")
        }
    }

    private func look() {
        do {
            found = try LibraryDeduplicator.find(in: context)
        } catch {
            failure = "The library couldn't be read: \(error.localizedDescription)"
        }
    }

    private func remove() {
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            do {
                try await BackupManager().createBackup(library: try LibraryContents.fetch(from: context))
            } catch {
                failure = "A backup couldn't be made first, so nothing was removed: \(error.localizedDescription)"
                return
            }
            do {
                let report = try LibraryDeduplicator.merge(in: context)
                try context.save()
                removed = report
                // Screens on the other tabs may be showing a copy that's gone.
                navigation.libraryWasReplaced()
                HapticFeedbackManager.shared.success()
                let items = try context.fetch(FetchDescriptor<GearItem>())
                await NotificationManager.shared.refreshGearReminders(for: items)
                await ShootAlertScheduler.refresh(in: context)
            } catch {
                context.rollback()
                failure = "The extra copies couldn't be removed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack { DuplicateRecordsView() }
        .modelContainer(PreviewModelContainer.make())
        .environment(AppNavigation())
        .environment(iCloudSyncManager())
}
