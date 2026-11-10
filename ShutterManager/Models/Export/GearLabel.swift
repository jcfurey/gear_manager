//
//  GearLabel.swift
//  ShutterManager
//
//  A QR label for a kit or a piece of gear, and a sheet of them to print. Plain values, so
//  `LabelSheetRenderer` can lay them out and draw them off the main actor.
//

import Foundation

/// One label: a QR code that opens the kit or item in the app, with enough written beside it to
/// know what it's stuck to without scanning.
struct GearLabel: Identifiable, Equatable, Sendable {
    let link: LabelLink
    /// The kit's or item's name.
    let title: String
    /// "Kit · 6 items" or the item's category.
    let subtitle: String
    /// What's in a kit, by name. Printed where the label has room.
    let contents: [String]

    var id: String { link.id }
}

extension GearLabel {
    @MainActor
    init(kit: Kit) {
        let gear = kit.orderedGear
        self.init(link: .kit(kit.id), title: kit.displayName,
                  subtitle: "Kit · \(gear.count == 1 ? "1 item" : "\(gear.count) items")",
                  contents: gear.map(\.displayName))
    }

    @MainActor
    init(item: GearItem) {
        self.init(link: .gear(item.id), title: item.displayName, subtitle: item.gearCategory.displayName, contents: [])
    }
}

/// Labels to print on one or more pages.
struct LabelSheet: Equatable, Sendable {
    /// How big each label is. Labels are cut from the page along dashed lines.
    enum Size: String, CaseIterable, Identifiable, Sendable {
        case large, small

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .large: return "Large"
            case .small: return "Small"
            }
        }

        /// Labels across and down a page.
        var columns: Int { self == .large ? 2 : 3 }
        var rows: Int { self == .large ? 4 : 6 }
        var perPage: Int { columns * rows }

        var detail: String {
            switch self {
            case .large: return "8 to a page, about 3¾ × 2½ in (9 × 6.5 cm). Room for a kit's contents."
            case .small: return "18 to a page, about 2½ × 1⅔ in (6 × 4.5 cm)."
            }
        }
    }

    var labels: [GearLabel]
    var size = Size.large
    /// Printed at the foot of every label, such as "If found: 555-0100". Blank leaves it out.
    var contactLine = ""

    var pageCount: Int {
        labels.isEmpty ? 0 : (labels.count + size.perPage - 1) / size.perPage
    }
}
