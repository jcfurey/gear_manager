//
//  GearPhoto.swift
//  ShutterManager
//
//  Model for managing multiple photos per gear item with captions and ordering.

import Foundation
import SwiftData

/// Represents a single photo associated with a gear item
@Model
final class GearPhoto {
    /// Unique identifier
    var id: UUID = UUID()

    /// Photo image data. Stored outside the SQLite store so multi-megabyte photos
    /// don't bloat the main DB and stay under CloudKit's per-field size limit.
    @Attribute(.externalStorage) var imageData: Data = Data()

    /// Optional caption or description
    var caption: String?

    /// Order in the photo gallery (0-based)
    var order: Int = 0

    /// Date photo was added
    var dateAdded: Date = Date()

    /// Associated gear item
    var gearItem: GearItem?

    /// Whether this is the primary/cover photo
    var isPrimary: Bool = false
    
    init(imageData: Data, caption: String? = nil, order: Int = 0, isPrimary: Bool = false) {
        self.id = UUID()
        self.imageData = imageData
        self.caption = caption
        self.order = order
        self.dateAdded = Date()
        self.isPrimary = isPrimary
    }
}
