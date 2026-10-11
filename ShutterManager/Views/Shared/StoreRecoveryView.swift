import SwiftUI

/// Works without a ModelContainer so a damaged library cannot hide the recovery tools.
struct StoreRecoveryView: View {
    @ObservedObject var store: AppStoreController
    @State private var isExporting = false
    @State private var archive: URL?
    @State private var isSharing = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ContentUnavailableView("Your Library Couldn’t Be Opened", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("You can retry, save a recovery copy of your stored data, or export an existing backup."))
                Button("Try Again") { store.retry() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                Button(isExporting ? "Preparing Recovery Copy…" : "Export Stored Data") {
                    isExporting = true
                    Task {
                        defer { isExporting = false }
                        do {
                            archive = try await store.exportRecoveryCopy()
                            isSharing = true
                        } catch { exportError = error.localizedDescription }
                    }
                }
                .disabled(isExporting)
                NavigationLink("Export a Backup") { RecoveryBackupsView() }
                Text("Keep a recovery copy before reinstalling the app. It includes the stored database and photos for recovery assistance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Library Recovery")
            .sheet(isPresented: $isSharing) {
                if let archive { ShareSheet(items: [archive]) }
            }
            .alert("Recovery Copy Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(exportError ?? "Please try again.") }
        }
    }
}

private struct RecoveryBackupsView: View {
    @StateObject private var backups = BackupManager()
    var body: some View {
        List {
            if backups.availableBackups.isEmpty {
                ContentUnavailableView("No Local Backups", systemImage: "archivebox")
            }
            ForEach(backups.availableBackups) { backup in
                ShareLink(item: backup.fileURL) {
                    VStack(alignment: .leading) {
                        Text(backup.formattedDate)
                        Text(backup.photoSummary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Available Backups")
    }
}
