//
//  PhotoIngest.swift
//  ShutterManager
//
//  Normalizes picked photos before they're stored (and synced): downsampled, re-encoded, no location.
//

import UIKit
import ImageIO
import os

/// Prepares a picked image for storage: downsampled to `Constants.Photos.maxStoredPixelSize` on
/// its long edge and re-encoded as JPEG.
///
/// Picked photos used to be persisted exactly as the picker handed them over — full-resolution
/// HEIC originals, several megabytes each, with no cap on dimensions or count. Display was already
/// memory-safe (`ThumbnailCache` decodes downsampled via ImageIO), so this was never a scrolling
/// problem; it was a *storage and sync* one. `GearPhoto` mirrors to the user's private CloudKit
/// database, so every original was uploaded and pulled back down on each device.
///
/// Downsampling happens through ImageIO, so the full-size image is never decoded into memory —
/// the same technique `ThumbnailCache` uses, applied at ingest instead of only at display.
enum PhotoIngest {

    private static let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "PhotoIngest")

    /// Returns storage-ready image data for `data`, or the original bytes if it can't be decoded
    /// or re-encoding wouldn't actually save space.
    ///
    /// Never fails: an image we can't process is stored as-is rather than dropped, since losing
    /// the user's photo is far worse than storing a large one.
    static func prepareForStorage(
        _ data: Data,
        maxPixelSize: CGFloat = Constants.Photos.maxStoredPixelSize,
        compressionQuality: CGFloat = Constants.Photos.storageCompressionQuality
    ) async -> Data {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                logger.warning("Could not decode picked image — storing original (\(data.count) bytes).")
                return data
            }

            // kCGImageSourceCreateThumbnailFromImageAlways + a max pixel size gives a decode that
            // is already scaled down, so the full-resolution bitmap never exists.
            // kCGImageSourceCreateThumbnailWithTransform bakes in the EXIF orientation, which
            // matters here because JPEG re-encoding below drops the original metadata.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let encoded = UIImage(cgImage: cgImage).jpegData(compressionQuality: compressionQuality) else {
                logger.warning("Could not re-encode picked image — storing original (\(data.count) bytes).")
                return data
            }

            // An already-small image (or one whose format beats JPEG at this quality) shouldn't be
            // made bigger just to satisfy the pipeline. The re-encoded JPEG carries no metadata;
            // the original keeps its own, so its location comes out first.
            guard encoded.count < data.count else { return removingLocation(from: data, source: source) }

            logger.debug("Prepared photo for storage: \(data.count) → \(encoded.count) bytes.")
            return encoded
        }.value
    }

    /// `data` with its GPS metadata removed, copied without re-encoding the image. Gear photos
    /// sync to iCloud and travel in exports, and where a gear photo was taken (often home) isn't
    /// something to keep. Returns the original when the format can't be copied that way.
    static func removingLocation(from data: Data, source: CGImageSource) -> Data {
        guard let type = CGImageSourceGetType(source) else { return data }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return data }
        let options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else {
            logger.warning("Could not remove location from a stored photo's metadata.")
            return data
        }
        return output as Data
    }
}
