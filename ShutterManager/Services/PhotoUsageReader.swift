//
//  PhotoUsageReader.swift
//  ShutterManager
//
//  Reads a batch of photos for Usage from Photos: from the photo picker, files or a folder.
//

import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

extension PhotoUsageSample {
    init(_ metadata: CameraPhotoMetadata) {
        self.init(cameraMake: metadata.cameraMake, cameraModel: metadata.cameraModel,
                  bodySerialNumber: metadata.bodySerialNumber, lensMake: metadata.lensMake,
                  lensModel: metadata.lensModel, lensSerialNumber: metadata.lensSerialNumber,
                  shutterCount: metadata.shutterCount, dateTaken: metadata.dateTaken,
                  focalLength: metadata.focalLength, aperture: metadata.aperture)
    }
}

extension PhotoMetadataReader {
    /// The metadata of the image file at `url`, or nil when ImageIO can't read it. Only the
    /// file's metadata is read: the picture isn't decoded, so a 60 MB raw file costs little.
    static func read(contentsOf url: URL) -> CameraPhotoMetadata? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [String: Any] else {
            return nil
        }
        return CameraPhotoMetadata(properties: properties)
    }
}

/// Finds and reads the photos in files and folders.
enum PhotoUsageReader {
    static func sample(at url: URL) -> PhotoUsageSample? {
        PhotoMetadataReader.read(contentsOf: url).map { PhotoUsageSample($0) }
    }

    /// The image files in `urls`, with folders searched all the way down, up to `limit`.
    ///
    /// One file per shot: a raw file and the JPEG the camera wrote beside it share a name
    /// ("DSC_0412.NEF", "DSC_0412.JPG") and count once.
    static func imageFiles(in urls: [URL],
                           limit: Int = Constants.PhotoUsage.maximumPhotos) -> (files: [URL], wasCutShort: Bool) {
        var files: [URL] = []
        var shots = Set<String>()
        var wasCutShort = false

        /// False once the limit is reached.
        func add(_ url: URL) -> Bool {
            guard isImage(url) else { return true }
            let shot = url.deletingPathExtension().standardizedFileURL.path.lowercased()
            guard !shots.contains(shot) else { return true }
            guard files.count < limit else {
                wasCutShort = true
                return false
            }
            shots.insert(shot)
            files.append(url)
            return true
        }

        for url in urls {
            if isDirectory(url) {
                let enumerator = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let file = enumerator?.nextObject() as? URL {
                    if !add(file) { break }
                }
            } else {
                _ = add(url)
            }
            if wasCutShort { break }
        }
        return (files, wasCutShort)
    }

    private static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

/// A photo from the system picker. Its details are read from the file the system hands over,
/// while it's there: the photo itself is never copied or held in memory.
struct PickedPhotoSample: Transferable, Sendable {
    let sample: PhotoUsageSample?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            PickedPhotoSample(sample: PhotoUsageReader.sample(at: received.file))
        }
    }
}

/// Reads a chosen batch of photos off the main actor, reporting progress, and can be cancelled.
@MainActor
@Observable
final class PhotoUsageImporter {
    /// What a batch of photos said.
    struct Batch: Equatable, Sendable {
        var samples: [PhotoUsageSample] = []
        /// Chosen images that couldn't be read (not downloaded, damaged, or not really images).
        var unreadableCount = 0
        /// The folder held more photos than `Constants.PhotoUsage.maximumPhotos`.
        var wasCutShort = false
    }

    enum State: Equatable {
        case idle
        /// `total` is 0 while a folder is still being searched.
        case reading(done: Int, total: Int)
        case finished(Batch)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Reads photos chosen in the photo picker, one at a time.
    func read(photos items: [PhotosPickerItem]) {
        task?.cancel()
        state = .reading(done: 0, total: items.count)
        task = Task { [weak self] in
            var batch = Batch()
            for (index, item) in items.enumerated() {
                let picked = try? await item.loadTransferable(type: PickedPhotoSample.self)
                guard !Task.isCancelled else { return }
                if let sample = picked?.sample {
                    batch.samples.append(sample)
                } else {
                    batch.unreadableCount += 1
                }
                self?.state = .reading(done: index + 1, total: items.count)
            }
            self?.state = .finished(batch)
        }
    }

    /// Reads files and folders chosen in the file picker.
    func read(files urls: [URL]) {
        task?.cancel()
        state = .reading(done: 0, total: 0)
        task = Task { [weak self] in
            // What the file picker returns can be read only while its security scope is held.
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

            let listing = await Task.detached(priority: .userInitiated) {
                PhotoUsageReader.imageFiles(in: urls)
            }.value
            var batch = Batch(wasCutShort: listing.wasCutShort)
            let files = listing.files
            let size = Constants.PhotoUsage.readBatchSize
            for start in stride(from: 0, to: files.count, by: size) {
                guard !Task.isCancelled else { return }
                self?.state = .reading(done: start, total: files.count)
                let slice = Array(files[start..<min(start + size, files.count)])
                let samples = await Task.detached(priority: .userInitiated) {
                    slice.compactMap { PhotoUsageReader.sample(at: $0) }
                }.value
                batch.samples += samples
                batch.unreadableCount += slice.count - samples.count
            }
            guard !Task.isCancelled else { return }
            self?.state = .finished(batch)
        }
    }

    /// Shows `batch` as read.
    func finish(with batch: Batch) {
        task?.cancel()
        task = nil
        state = .finished(batch)
    }

    /// Stops reading and goes back to choosing photos.
    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }
}

#if DEBUG
extension PhotoUsageImporter.Batch {
    /// What the UI tests read in place of real photos (`-uiTestPhotoUsageSample`): three shots
    /// on a Nikon body that reports its shutter count, through a zoom at 24, 35 and 35 mm, and
    /// one on a Fujifilm.
    static var uiTestSample: Self {
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        var batch = Self()
        for (shot, focalLength) in [24.0, 35, 35].enumerated() {
            batch.samples.append(PhotoUsageSample(
                cameraMake: "Nikon", cameraModel: "Z6_3", bodySerialNumber: "3000123", lensMake: "Nikon",
                lensModel: "NIKKOR Z 24-70mm f/2.8 S", lensSerialNumber: nil, shutterCount: 20_000 + shot,
                dateTaken: day.addingTimeInterval(Double(shot) * 60), focalLength: focalLength, aperture: 4))
        }
        batch.samples.append(PhotoUsageSample(
            cameraMake: "Fujifilm", cameraModel: "X-T5", bodySerialNumber: nil, lensMake: nil,
            lensModel: "XF23mmF1.4 R LM WR", lensSerialNumber: nil, shutterCount: nil,
            dateTaken: day.addingTimeInterval(3600), focalLength: 23, aperture: 2))
        return batch
    }
}
#endif
