//
//  DataManagementView.swift
//  ShutterManager
//
//  Import screen (DataImportView) and the share-sheet wrapper exports use.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// File-picker import: previews a chosen export, then merges it into the library through
/// `DataImportService`. Records the library already has (same ID) are skipped, so importing the
/// same file twice adds nothing.
struct DataImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showingDocumentPicker = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var showingConfirmation = false
    @State private var pendingImportURL: URL?
    @State private var importPreview: ImportPreview?

    private let importService = DataImportService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingDocumentPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .foregroundColor(.blue)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Select File to Import")
                                    .foregroundColor(.primary)
                                Text("A JSON export or backup from \(Constants.App.name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isImporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImporting)
                } footer: {
                    if let importError {
                        Text(importError).foregroundColor(.red)
                    } else if importSuccess {
                        Text("Data imported.").foregroundColor(.green)
                    }
                }

                if let preview = importPreview {
                    Section("This File Contains") {
                        LabeledContent("File", value: preview.fileName)
                        LabeledContent("Exported", value: preview.formattedDate)
                        previewRow("camera", "Gear items", preview.gearCount)
                        previewRow("photo.on.rectangle", "Photos", preview.photoCount)
                        previewRow("wrench.and.screwdriver", "Maintenance records", preview.maintenanceCount)
                        previewRow("chart.xyaxis.line", "Shutter-count readings", preview.shutterCountCount)
                        previewRow("arrow.left.arrow.right", "Loans", preview.loanCount)
                        previewRow("flask", "Development recipes", preview.recipeCount)
                        previewRow("mappin.and.ellipse", "Saved places", preview.placeCount)
                        previewRow("calendar", "Shoots", preview.shootCount)
                        previewRow("bag", "Kits", preview.kitCount)
                        previewRow("checklist", "Shot-list templates", preview.templateCount)
                        previewRow("film", "Film rolls", preview.filmRollCount)
                        if preview.hasSettings {
                            Label("App settings", systemImage: "gearshape")
                        }
                        Button("Import This Data") {
                            if pendingImportURL != nil { showingConfirmation = true }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("About Importing") {
                    ImportInfoRow(title: "What's Added",
                                  description: "Everything in the file that isn't already in your library. Items you already have are left as they are.")
                    ImportInfoRow(title: "Settings",
                                  description: "Appearance and haptics settings in the file replace the current ones.")
                    ImportInfoRow(title: "Before You Import",
                                  description: "Consider exporting or backing up your current library first.")
                }
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $showingDocumentPicker, allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            handleFileSelection(result)
        }
        .alert("Import Data", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Import") {
                if let url = pendingImportURL { performImport(from: url) }
            }
        } message: {
            Text("This adds the file's records to your library. It can't be undone.")
        }
    }

    @ViewBuilder
    private func previewRow(_ icon: String, _ label: String, _ count: Int) -> some View {
        if count > 0 {
            LabeledContent {
                Text("\(count)")
            } label: {
                Label(label, systemImage: icon)
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            analyzeFile(at: url)
        case .failure(let error):
            importError = error.localizedDescription
            importSuccess = false
        }
    }

    private func analyzeFile(at url: URL) {
        importError = nil
        importSuccess = false
        // Drop the previous file's preview first, so a file that can't be read never leaves the
        // old preview's Import button pointing at the old file.
        importPreview = nil
        pendingImportURL = nil
        Task {
            do {
                let preview = try await importService.previewImport(from: url)
                importPreview = preview
                pendingImportURL = url
            } catch {
                importError = "Couldn't read the file: \(error.localizedDescription)"
            }
        }
    }

    private func performImport(from url: URL) {
        isImporting = true
        importError = nil
        Task {
            do {
                try await importService.importData(from: url, to: modelContext, strategy: .merge)
                importSuccess = true
                importPreview = nil
                pendingImportURL = nil
                ToastNotificationManager.shared.dataImported()
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }
}

/// Title + description row for import-screen explanatory text.
struct ImportInfoRow: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// UIKit share sheet for an exported file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    DataImportView()
        .modelContainer(PreviewModelContainer.make())
}
