//
//  AddGearView.swift
//  ShutterManager
//
//  Form for adding a gear item: by hand, from a barcode scan, or from a photo's metadata.
//

import SwiftUI
import SwiftData
import PhotosUI
import os

/// Modal form for a new `GearItem`. Edits an unmanaged draft, so Cancel leaves nothing behind;
/// Save inserts it.
struct AddGearView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var context

    @State private var draft = GearItem(category: .cameraBody)
    @State private var showingBarcodeScanner = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photoMetadata: IdentifiedMetadata?
    @State private var isReadingPhoto = false
    @State private var photoMessage: String?
    /// A shutter count kept from a photo, recorded as a reading when the item is saved.
    @State private var pendingShutterCount: Int?
    @State private var saveFailed = false

    private let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "AddGear")

    /// Wraps metadata so it can drive `.sheet(item:)`.
    struct IdentifiedMetadata: Identifiable {
        let id = UUID()
        let metadata: CameraPhotoMetadata
    }

    /// At least a make or model is required, so the form can't create blank items.
    private var hasName: Bool {
        draft.make?.nonEmptyOrNil != nil || draft.model?.nonEmptyOrNil != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                quickAddSection
                GearEditorSections(item: draft)
            }
            .navigationTitle("New Gear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasName)
                        .accessibilityIdentifier("saveGearButton")
                }
            }
        }
        .persistenceErrorAlert(isPresented: $saveFailed)
        .sheet(isPresented: $showingBarcodeScanner) {
            BarcodeScannerView(
                onBarcodeScanned: { draft.upcCode = $0 },
                onProductFound: applyProduct
            )
        }
        .sheet(item: $photoMetadata) { found in
            PhotoMetadataImportView(metadata: found.metadata, item: draft) { count in
                pendingShutterCount = count
            }
        }
        .onChange(of: pickedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await readMetadata(from: newItem) }
        }
    }

    // MARK: - Quick add

    private var quickAddSection: some View {
        Section {
            Button {
                showingBarcodeScanner = true
            } label: {
                quickAddLabel("Scan Barcode", detail: "Look up a product by its barcode", icon: "barcode.viewfinder")
            }
            PhotosPicker(selection: $pickedPhoto, matching: .images, preferredItemEncoding: .current) {
                quickAddLabel("Fill from a Photo",
                              detail: "Read the camera or lens from a photo it took",
                              icon: "photo.badge.magnifyingglass")
            }
            .disabled(isReadingPhoto)
            .accessibilityIdentifier("fillFromPhotoButton")
            if isReadingPhoto {
                ProgressView("Reading photo…")
            }
            if let photoMessage {
                Text(photoMessage).font(.caption).foregroundStyle(Color.secondary)
            }
            if let upc = draft.upcCode {
                LabeledContent("UPC", value: upc)
            }
            if let pendingShutterCount {
                LabeledContent("Shutter Count", value: pendingShutterCount.formatted())
            }
        } header: {
            Text("Quick Add")
        }
    }

    private func quickAddLabel(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Color.primary).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(Color.secondary)
            }
        }
    }

    // MARK: - Photo metadata

    /// Loads the picked photo's original bytes (metadata intact) and reads them.
    private func readMetadata(from item: PhotosPickerItem) async {
        isReadingPhoto = true
        photoMessage = nil
        defer {
            isReadingPhoto = false
            pickedPhoto = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoMessage = "That photo couldn't be loaded."
                return
            }
            let metadata = await Task.detached(priority: .userInitiated) { PhotoMetadataReader.read(data) }.value
            guard let metadata, !metadata.isEmpty else {
                photoMessage = "That photo has no camera details. Try an original from the camera rather than an edited or shared copy."
                return
            }
            photoMetadata = IdentifiedMetadata(metadata: metadata)
        } catch {
            logger.error("Could not load picked photo: \(error.localizedDescription, privacy: .public)")
            photoMessage = "That photo couldn't be loaded."
        }
    }

    // MARK: - Barcode

    private func applyProduct(_ product: ProductInfo) {
        draft.upcCode = product.barcode
        if !product.name.isEmpty, product.name != "Unknown Product" {
            draft.model = product.name
        }
        if let brand = product.displayBrand {
            draft.make = brand
        }
        if let description = product.displayDescription, !(draft.notes ?? "").contains(description) {
            draft.notes = [draft.notes?.nonEmptyOrNil, description].compactMap { $0 }.joined(separator: "\n\n")
        }
        if let category = product.category.flatMap(Self.category(forProductCategory:)) {
            draft.gearCategory = category
        }
        // Source attribution, once: re-scanning shouldn't stack duplicate lines.
        let source = "Product info from \(product.source.displayName)"
        if !(draft.notes ?? "").contains(source) {
            draft.notes = [draft.notes?.nonEmptyOrNil, source].compactMap { $0 }.joined(separator: "\n\n")
        }
    }

    /// Maps a lookup service's free-text category onto a gear category, when it clearly says.
    static func category(forProductCategory text: String) -> GearCategory? {
        let lowered = text.lowercased()
        let rules: [(keywords: [String], category: GearCategory)] = [
            (["lens"], .lens),
            (["drone"], .drone),
            (["tripod", "monopod", "gimbal", "stabilizer"], .support),
            (["flash", "strobe", "lighting"], .lighting),
            (["filter"], .filter),
            (["memory", "sd card", "cfexpress"], .memoryCard),
            (["battery", "charger", "power"], .power),
            (["microphone", "audio", "recorder"], .audio),
            (["bag", "case", "backpack"], .bag),
            (["camera"], .cameraBody)
        ]
        return rules.first { rule in rule.keywords.contains { lowered.contains($0) } }?.category
    }

    // MARK: - Save

    private func save() {
        guard hasName, context.saveOrLog() else {
            saveFailed = hasName
            return
        }
        draft.make = draft.make?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        draft.model = draft.model?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        draft.dateAdded = Date()
        draft.markModified()
        context.insert(draft)
        if let count = pendingShutterCount, draft.gearCategory.hasShutter {
            context.insert(ShutterCountReading(gearItem: draft, count: count, source: .photo))
        }
        guard context.saveOrLog() else {
            context.rollback()
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        let saved = draft
        Task { await NotificationManager.shared.updateReminders(for: saved) }
        ToastNotificationManager.shared.gearSaved()
        isPresented = false
    }
}
