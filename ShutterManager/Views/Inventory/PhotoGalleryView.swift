//
//  PhotoGalleryView.swift
//  ShutterManager
//
//  Photo gallery for a gear item: add, set the cover, caption and delete.

import SwiftUI
import SwiftData
import PhotosUI

/// Grid of a gear item's photos with add, set-primary, delete, and per-photo
/// detail/caption editing.
struct PhotoGalleryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    
    let gearItem: GearItem
    
    @State private var showingImagePicker = false
    @State private var selectedPhoto: GearPhoto?
    @State private var showingPhotoDetail = false
    @State private var editMode: EditMode = .inactive
    
    private var sortedPhotos: [GearPhoto] {
        (gearItem.photos ?? []).sorted { $0.order < $1.order }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let constants = ResponsiveConstants(geometry, dynamicTypeSize: dynamicTypeSize)
            
                ScrollView {
                    if sortedPhotos.isEmpty {
                        emptyStateView(constants: constants)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: constants.itemSpacing),
                            GridItem(.flexible(), spacing: constants.itemSpacing),
                            GridItem(.flexible(), spacing: constants.itemSpacing)
                        ], spacing: constants.itemSpacing) {
                            // Gallery photos. The cell takes a CLOSURE, not the Data itself —
                            // `photo.imageData` faults the multi-MB external-storage blob, and
                            // passing it as a stored property faulted every photo at cell
                            // construction (scroll hitches + tens of MB of retained raw Data).
                            ForEach(sortedPhotos) { photo in
                                PhotoGridItem(
                                    photoID: photo.id,
                                    loadImageData: { photo.imageData },
                                    isPrimary: photo.isPrimary,
                                    isLegacy: false,
                                    constants: constants,
                                    availableWidth: geometry.size.width
                                ) {
                                    selectedPhoto = photo
                                    showingPhotoDetail = true
                                }
                                .contextMenu {
                                    Button {
                                        setPrimaryPhoto(photo)
                                    } label: {
                                        Label(photo.isPrimary ? "Primary Photo" : "Set as Primary", systemImage: "star.fill")
                                    }
                                    
                                    Button(role: .destructive) {
                                        deletePhoto(photo)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(constants.padding)
                    }
                }
                .navigationTitle("Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingImagePicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add photo")
                    }
                }
                .photosPicker(isPresented: $showingImagePicker, selection: Binding(
                    get: { nil },
                    set: { item in
                        if let item = item {
                            loadPhoto(from: item)
                        }
                    }
                ), matching: .images)
                .sheet(isPresented: $showingPhotoDetail) {
                    if let photo = selectedPhoto {
                        PhotoDetailView(photo: photo, gearItem: gearItem)
                    }
                }
        }
    }
    
    private func emptyStateView(constants: ResponsiveConstants) -> some View {
        VStack(spacing: constants.itemSpacing * 2) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: constants.iconSize * 3))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            
            Text("No Photos Yet")
                .font(constants.titleFont.weight(.semibold))

            Text("Add photos to document your gear's condition and details")
                .font(constants.bodyFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, constants.padding * 2)

            Button {
                showingImagePicker = true
            } label: {
                Label("Add Photo", systemImage: "plus.circle.fill")
                    .font(constants.bodyFont)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(constants.padding * 2)
    }
    
    private func loadPhoto(from item: PhotosPickerItem) {
        Task {
            if let original = try? await item.loadTransferable(type: Data.self) {
                // Downsample + re-encode before storing. These records mirror to CloudKit, so the
                // picker's full-resolution original would otherwise be uploaded and re-downloaded
                // on every device. Runs off the main actor (see PhotoIngest).
                let data = await PhotoIngest.prepareForStorage(original)

                await MainActor.run {
                    // Orders after the current max, so delete-then-add can't collide.
                    gearItem.appendGalleryPhoto(data, in: modelContext)
                    modelContext.saveOrLog()
                }
            }
        }
    }
    
    private func setPrimaryPhoto(_ photo: GearPhoto) {
        // Only one photo may be primary at a time.
        gearItem.photos?.forEach { $0.isPrimary = false }
        photo.isPrimary = true
        modelContext.saveOrLog()
    }
    
    private func deletePhoto(_ photo: GearPhoto) {
        // Capture primary status before deleting — reading it off a deleted object is unreliable.
        let wasPrimary = photo.isPrimary
        modelContext.delete(photo)
        modelContext.saveOrLog()

        // If the deleted photo was primary, promote the first remaining photo.
        if wasPrimary, let firstPhoto = gearItem.photos?.sorted(by: { $0.order < $1.order }).first {
            firstPhoto.isPrimary = true
            modelContext.saveOrLog()
        }
    }
}

// MARK: - Supporting Views

/// One thumbnail cell in the gallery grid. Decodes a downsampled thumbnail
/// asynchronously via `ThumbnailCache` and marks the primary photo with a star.
struct PhotoGridItem: View {
    let photoID: UUID
    /// Deferred data access: evaluated only inside the thumbnail task, and only on a cache
    /// miss — never at cell construction (see the gallery ForEach).
    let loadImageData: () -> Data
    let isPrimary: Bool
    let isLegacy: Bool
    let constants: ResponsiveConstants
    /// The enclosing GeometryReader's available width (passed down from `PhotoGalleryView`),
    /// used instead of `UIScreen.main.bounds.width` so the grid sizes correctly under iPad
    /// Split View / Slide Over where the view is narrower than the full screen.
    let availableWidth: CGFloat
    let action: () -> Void

    @State private var thumbnail: UIImage?

    /// Target pixel size for the thumbnail. 3× the point size covers Retina displays
    /// without decoding the full-resolution image.
    private var thumbnailPixelSize: CGFloat { gridItemSize * 3 }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: gridItemSize, height: gridItemSize)
                        .clipped()
                        .cornerRadius(constants.cornerRadius)
                } else {
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: gridItemSize, height: gridItemSize)
                        .cornerRadius(constants.cornerRadius)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }
                
                if isPrimary {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(constants.bodyFont)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        // An image-only button: without a label VoiceOver announced each cell as an unnamed
        // "Button"/"Image", so the gallery couldn't be navigated or the cover photo identified.
        .accessibilityLabel(isPrimary ? "Primary photo" : "Photo")
        .accessibilityHint(isLegacy ? "" : "Opens photo details")
        // Keyed on the pixel size as well as the photo: the cell size follows the available width,
        // which changes on rotation / Split View resizing without recreating the cell. Keyed on
        // the id alone, the task never re-ran, so the thumbnail decoded for the old (smaller) size
        // stayed on screen upscaled and soft — the size-aware cache key was never consulted.
        .task(id: ThumbnailRequest(photoID: photoID, pixelSize: thumbnailPixelSize)) {
            let pixelSize = thumbnailPixelSize
            // A zero/negative width can occur on a transient first layout pass; wait for the
            // real size (the task re-runs when it arrives) rather than decoding at a bogus size.
            guard pixelSize > 0 else { return }
            if let cached = ThumbnailCache.cached(for: photoID, pixelSize: pixelSize) {
                thumbnail = cached
                return
            }
            let image = await ThumbnailCache.makeThumbnail(
                from: loadImageData(),
                key: photoID,
                pixelSize: pixelSize
            )
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
    }

    /// Identity of one thumbnail decode: which photo, at which pixel size.
    private struct ThumbnailRequest: Hashable {
        let photoID: UUID
        let pixelSize: CGFloat
    }

    private var gridItemSize: CGFloat {
        (availableWidth - (constants.padding * 4)) / 3
    }
}

/// Full-size view of a single photo with editable caption and primary toggle.
struct PhotoDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let photo: GearPhoto
    let gearItem: GearItem
    
    @State private var caption: String
    @State private var isPrimary: Bool
    @State private var image: UIImage?

    init(photo: GearPhoto, gearItem: GearItem) {
        self.photo = photo
        self.gearItem = gearItem
        _caption = State(initialValue: photo.caption ?? "")
        _isPrimary = State(initialValue: photo.isPrimary)
    }

    var body: some View {
        GeometryReader { geometry in
            let constants = ResponsiveConstants(geometry, dynamicTypeSize: dynamicTypeSize)

            NavigationStack {
                ScrollView {
                    VStack(spacing: constants.itemSpacing * 2) {
                        // Decode once at a bounded display size, including legacy/imported originals.
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(constants.cornerRadius)
                                .accessibilityLabel(photo.caption?.nonEmptyOrNil ?? "Photo of \(gearItem.displayName)")
                        }
                        
                        // Details section
                        VStack(alignment: .leading, spacing: constants.itemSpacing) {
                            // Caption
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Caption")
                                    .font(constants.captionFont.weight(.medium))
                                    .foregroundColor(.secondary)
                                
                                TextField("Add a caption...", text: $caption, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(3...6)
                            }
                            
                            // Primary photo toggle
                            Toggle("Use as Primary Photo", isOn: $isPrimary)
                                .font(constants.bodyFont)
                            
                            // Metadata
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Added: \(photo.dateAdded.formatted(date: .long, time: .shortened))")
                                    .font(constants.captionFont)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(constants.padding)
                    }
                    .padding(constants.padding)
                }
                .persistenceErrorAlert(isPresented: $saveFailed)
                .navigationTitle("Photo Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveChanges()
                        }
                    }
                }
                .task {
                    // Fault the blob on main (ModelContext-bound), decode off-main, once.
                    let data = photo.imageData
                    image = await ThumbnailCache.downsample(data, pixelSize: Constants.Photos.maxStoredPixelSize)
                }
            }
        }
    }
    
    private func saveChanges() {
        guard modelContext.saveOrLog() else { saveFailed = true; return }
        let previousCaption = photo.caption
        let previousPrimary = (gearItem.photos ?? []).map { ($0, $0.isPrimary) }
        photo.caption = caption.isEmpty ? nil : caption
        
        if isPrimary != photo.isPrimary {
            if isPrimary {
                // Remove primary from all other photos
                gearItem.photos?.forEach { $0.isPrimary = false }
            }
            photo.isPrimary = isPrimary
        }
        
        guard modelContext.saveOrLog() else {
            modelContext.rollback()
            photo.caption = previousCaption
            for (image, primary) in previousPrimary { image.isPrimary = primary }
            saveFailed = true
            return
        }
        dismiss()
    }
}

#Preview {
    let container = PreviewModelContainer.make()
    
    let sampleItem = GearItem(category: .cameraBody, make: "Nikon", model: "Z6 III")
    container.mainContext.insert(sampleItem)
    
    return PhotoGalleryView(gearItem: sampleItem)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
