//
//  ThumbnailCache.swift
//  ShutterManager
//
//  Memory-bounded thumbnail cache for photo grids. Keyed by the source photo's
//  identifier so the same cell rebinds quickly when the grid scrolls back to it.
//

import UIKit
import ImageIO

enum ThumbnailCache {

    /// Backing NSCache — auto-evicts under memory pressure. Keyed by photo UUID string.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = Constants.Photos.thumbnailCacheCountLimit
        c.totalCostLimit = Constants.Photos.thumbnailCacheByteLimit
        return c
    }()

    /// Cache key for one photo at one rendered size. The size is part of the key because the grid's
    /// cell size is derived from the available width — it changes on rotation, on iPad Split View
    /// resizing, and across size classes. Keyed by photo id alone, the first size cached won.
    /// Coming back at a larger size returned the small thumbnail, upscaled and visibly soft (the
    /// same collision `downsample` exists to keep hero images out of).
    ///
    /// Sizes are bucketed to 64 px so a few points of layout jitter can't spray near-duplicate
    /// entries through a 100-entry cache and evict genuinely distinct photos.
    private static func cacheKey(_ key: UUID, pixelSize: CGFloat) -> NSString {
        let bucket = max(1, Int((pixelSize / 64).rounded(.up)))
        return "\(key.uuidString)@\(bucket)" as NSString
    }

    /// Returns a cached thumbnail for this photo at this pixel size, if one is already available;
    /// otherwise nil. Safe on any thread.
    static func cached(for key: UUID, pixelSize: CGFloat) -> UIImage? {
        return cache.object(forKey: cacheKey(key, pixelSize: pixelSize))
    }

    /// Generates a thumbnail from raw image data at the given pixel size and caches it.
    /// Uses ImageIO so the full-resolution image is never decoded into memory.
    static func makeThumbnail(from data: Data, key: UUID, pixelSize: CGFloat) async -> UIImage? {
        if let hit = cached(for: key, pixelSize: pixelSize) { return hit }

        let result = await downsample(data, pixelSize: pixelSize)
        if let result {
            let bytes = result.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(result, forKey: cacheKey(key, pixelSize: pixelSize), cost: bytes)
        }
        return result
    }

    /// One-off downsampled decode (NOT cached) — for hero/banner images that live in their own
    /// @State. A 1400 px banner is far too big to hold in a 100-entry grid cache, and it's needed
    /// once per screen rather than repeatedly while scrolling, so it stays out of the cache
    /// entirely. (Grid entries are keyed by size, so the two could no longer collide anyway.)
    static func downsample(_ data: Data, pixelSize: CGFloat) async -> UIImage? {
        // ImageIO + thumbnail options keep us memory-bounded — no full decode of the source.
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: cg)
        }.value
    }
}
