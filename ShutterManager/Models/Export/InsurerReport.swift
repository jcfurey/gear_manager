//
//  InsurerReport.swift
//  ShutterManager
//
//  What goes in a report for the user's insurer: who it's from, and each item's identifying
//  details, values and photos. A plain value, so `InsurerReportRenderer` can lay it out and draw it
//  off the main actor.
//
//  The report lists what the user entered. It is never called anything but "a report for your
//  insurer": the app doesn't value gear and has nothing to say about cover.
//

import Foundation
import ImageIO
import UIKit

struct InsurerReport: Sendable {
    /// Which of an item's photos the report shows.
    enum PhotoChoice: String, CaseIterable, Identifiable, Sendable {
        case none, cover, all

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .none: return "None"
            case .cover: return "Cover"
            case .all: return "All"
            }
        }
    }

    struct Options: Equatable, Sendable {
        /// Who the report is from. Blank leaves the line out.
        var ownerName = ""
        /// Whatever the insurer files it under, such as a policy or claim number.
        var reference = ""
        var photos = PhotoChoice.cover
    }

    /// One "Label: value" line under an item's name.
    struct Detail: Equatable, Sendable {
        let label: String
        let value: String
    }

    /// A photo sized for the page: a small JPEG and its pixel size, for fitting it to its box.
    struct Photo: Sendable {
        let jpeg: Data
        let pixelWidth: Int
        let pixelHeight: Int
        let caption: String?
    }

    struct Entry: Identifiable, Sendable {
        let id: UUID
        let name: String
        let category: GearCategory
        let details: [Detail]
        let purchasePrice: Decimal?
        let currentValue: Decimal?
        /// The cover photo first.
        let photos: [Photo]

        /// The figure the totals use: the current value if one was entered, else what was paid.
        var value: Decimal? { currentValue ?? purchasePrice }
    }

    let preparedDate: Date
    let ownerName: String
    let reference: String
    /// Grouped by category in the catalog's order, by name within each.
    let entries: [Entry]

    static let title = "Gear Inventory"

    /// "A report for your insurer, prepared 10 November 2026".
    var subtitle: String {
        "A report for your insurer, prepared \(preparedDate.formatted(date: .long, time: .omitted))"
    }

    /// Said on the report itself, so nobody takes entered figures for an appraisal.
    static let disclaimer = "Values and details are as the owner entered them. This report is not a valuation."

    var totalValue: Decimal { entries.reduce(Decimal.zero) { $0 + ($1.value ?? .zero) } }
    var totalPurchasePrice: Decimal { entries.reduce(Decimal.zero) { $0 + ($1.purchasePrice ?? .zero) } }
    var entriesWithValue: Int { entries.filter { $0.value != nil }.count }
    var entriesWithPurchasePrice: Int { entries.filter { $0.purchasePrice != nil }.count }

    /// The summary under the heading: counts, totals, and how many items the totals leave out.
    var summaryLines: [Detail] {
        var lines = [Detail(label: "Items", value: "\(entries.count)")]
        lines.append(Detail(label: "Total value", value: Self.total(totalValue, covering: entriesWithValue, of: entries.count)))
        lines.append(Detail(label: "Total paid", value: Self.total(totalPurchasePrice, covering: entriesWithPurchasePrice,
                                                                   of: entries.count)))
        return lines
    }

    private static func total(_ amount: Decimal, covering counted: Int, of all: Int) -> String {
        let text = CurrencyFormatter.formatWithDecimals(amount)
        return counted < all ? "\(text) (\(counted) of \(all) items have one)" : text
    }

    /// The entries of each category that has any, in the catalog's order.
    var entriesByCategory: [(category: GearCategory, entries: [Entry])] {
        let grouped = Dictionary(grouping: entries, by: \.category)
        return GearCategory.allCases.compactMap { category in
            guard let members = grouped[category], !members.isEmpty else { return nil }
            return (category, members)
        }
    }
}

// MARK: - Building from the library

extension InsurerReport {
    /// Longest edge, in pixels, of a photo in the report. Photos print about two inches wide, so
    /// this is roughly 200 dpi and keeps a report of a few hundred photos to a few megabytes.
    static let photoPixelSize: CGFloat = 420

    /// The report for `items`. Photos are read and shrunk one at a time, so a large library
    /// never has every stored photo in memory at once.
    @MainActor
    static func make(items: [GearItem], options: Options, preparedDate: Date = Date()) async -> InsurerReport {
        var entries: [Entry] = []
        let sorted = items.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        for item in sorted {
            var photos: [Photo] = []
            for stored in storedPhotos(of: item, choice: options.photos) {
                if let photo = await reportPhoto(from: stored.imageData, caption: stored.caption?.nonEmptyOrNil) {
                    photos.append(photo)
                }
            }
            entries.append(Entry(id: item.id, name: item.displayName, category: item.gearCategory,
                                 details: details(for: item), purchasePrice: item.purchasePrice,
                                 currentValue: item.currentValue, photos: photos))
        }
        return InsurerReport(preparedDate: preparedDate,
                             ownerName: options.ownerName.trimmingCharacters(in: .whitespacesAndNewlines),
                             reference: options.reference.trimmingCharacters(in: .whitespacesAndNewlines),
                             entries: entries)
    }

    /// The photos the choice asks for, cover first.
    @MainActor
    private static func storedPhotos(of item: GearItem, choice: PhotoChoice) -> [GearPhoto] {
        let ordered = (item.photos ?? []).sorted {
            $0.isPrimary != $1.isPrimary ? $0.isPrimary : $0.order < $1.order
        }
        switch choice {
        case .none: return []
        case .cover: return Array(ordered.prefix(1))
        case .all: return ordered
        }
    }

    /// What identifies the item and dates its purchase. Notes stay out: they're the owner's own.
    @MainActor
    static func details(for item: GearItem) -> [Detail] {
        var details: [Detail] = []
        func add(_ label: String, _ value: String?) {
            if let value = value?.nonEmptyOrNil { details.append(Detail(label: label, value: value)) }
        }
        add("Serial number", item.serialNumber)
        add("Year made", item.manufacturingYear.map { String($0) })
        add("Purchased", item.purchaseDate?.formatted(date: .abbreviated, time: .omitted))
        add("Purchase price", item.purchasePrice.map(CurrencyFormatter.formatWithDecimals))
        add("Current value", item.currentValue.map(CurrencyFormatter.formatWithDecimals))
        if item.gearCategory.hasShutter, let reading = item.latestShutterReading {
            add("Shutter count", "\(reading.count.formatted()) on \(reading.date.formatted(date: .abbreviated, time: .omitted))")
        }
        add("Product code", item.upcCode)
        return details
    }

    /// `data` as a small JPEG with its pixel size, or nil when it isn't an image.
    static func reportPhoto(from data: Data, caption: String?) async -> Photo? {
        let pixelSize = photoPixelSize
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { return nil }
            return Photo(jpeg: jpeg, pixelWidth: image.width, pixelHeight: image.height, caption: caption)
        }.value
    }
}
