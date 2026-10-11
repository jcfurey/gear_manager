//
//  EnhancedDataExportView.swift
//  ShutterManager
//
//  Export sheet: choose JSON (complete, importable), CSV (spreadsheet) or PDF (inventory
//  report), what to include, and share the file.
//

import SwiftUI
import SwiftData

struct EnhancedDataExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \GearItem.dateAdded, order: .reverse) private var gearItems: [GearItem]
    @Query private var recipes: [DevelopmentRecipe]
    @Query private var places: [SavedPlace]

    @State private var selectedFormat = EnhancedExportFormat.json
    @State private var includePhotos = true
    @State private var includeSettings = true
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?

    private let exportService = DataExportService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(EnhancedExportFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("exportFormatPicker")
                } header: {
                    Text("Format")
                } footer: {
                    Text(selectedFormat.description)
                }

                if selectedFormat == .json {
                    Section {
                        Toggle("Photos", isOn: $includePhotos)
                        Toggle("App Settings", isOn: $includeSettings)
                    } header: {
                        Text("Include")
                    } footer: {
                        Text("Gear, maintenance, shutter counts, loans, development recipes and saved places are always included. Leaving photos out makes a much smaller file.")
                    }
                }

                Section {
                    StatRow(icon: "camera", label: "Gear Items", value: "\(gearItems.count)", color: .orange)
                    if selectedFormat == .json && includePhotos {
                        StatRow(icon: "photo.on.rectangle", label: "Photos",
                                value: "\(gearItems.reduce(0) { $0 + $1.totalPhotoCount })", color: .blue)
                    }
                    if selectedFormat == .json && !recipes.isEmpty {
                        StatRow(icon: "flask", label: "Development Recipes", value: "\(recipes.count)", color: .purple)
                    }
                    if selectedFormat == .json && !places.isEmpty {
                        StatRow(icon: "mappin.and.ellipse", label: "Saved Places", value: "\(places.count)", color: .teal)
                    }
                }

                Section {
                    Button(action: performExport) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                Text("Exporting…")
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export \(selectedFormat.displayName)")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isExporting || !hasAnythingToExport)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("exportButton")
                } footer: {
                    if let exportError {
                        Text(exportError).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: cleanup) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    /// CSV and PDF list gear; JSON also carries recipes and settings.
    private var hasAnythingToExport: Bool {
        !gearItems.isEmpty || (selectedFormat == .json && (includeSettings || !recipes.isEmpty || !places.isEmpty))
    }

    private func performExport() {
        guard !isExporting else { return }
        isExporting = true
        exportError = nil
        var configuration = DataExportService.ExportConfiguration(format: selectedFormat == .csv ? .csv : .json)
        // CSV and PDF never contain photos, so their DTOs skip the multi-MB blobs.
        configuration.includePhotos = selectedFormat == .json && includePhotos
        configuration.includeSettings = selectedFormat == .json && includeSettings
        Task {
            do {
                let library = try LibraryContents.fetch(from: modelContext)
                if selectedFormat == .pdf {
                    exportedFileURL = try await exportService.exportPDF(configuration: configuration, library: library)
                } else {
                    exportedFileURL = try await exportService.exportData(configuration: configuration, library: library)
                }
                showingShareSheet = true
            } catch {
                exportError = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func cleanup() {
        if let url = exportedFileURL {
            try? FileManager.default.removeItem(at: url)
            exportedFileURL = nil
        }
    }
}

/// Icon + label + value row for the export summary.
struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    EnhancedDataExportView()
        .modelContainer(PreviewModelContainer.make())
}
