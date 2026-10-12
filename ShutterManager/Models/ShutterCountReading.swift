//
//  ShutterCountReading.swift
//  ShutterManager
//
//  A body's shutter count on a given day.
//

import Foundation
import SwiftData

/// One shutter-count reading for a camera body. A history of readings shows how fast the body
/// is wearing; the latest one compared with `GearItem.ratedShutterLife` drives the wear badge.
@Model
final class ShutterCountReading {
    var id: UUID = UUID()
    var gearItem: GearItem?
    var date: Date = Date()
    var count: Int = 0
    /// A `ShutterCountSource` raw value, stored as text so a source added later reads as
    /// `.manual` here instead of failing to decode.
    var sourceID: String = "manual"
    var note: String = ""

    init(gearItem: GearItem? = nil, date: Date = Date(), count: Int, source: ShutterCountSource = .manual,
         note: String = "") {
        self.id = UUID()
        self.gearItem = gearItem
        self.date = date
        self.count = count
        self.sourceID = source.rawValue
        self.note = note
    }

    var source: ShutterCountSource {
        get { ShutterCountSource(rawValue: sourceID) ?? .manual }
        set { sourceID = newValue.rawValue }
    }
}

/// Where a shutter count came from. Raw values are stored: never rename one.
enum ShutterCountSource: String, CaseIterable, Codable {
    /// Typed in by the user (read from the camera's menu or a service report).
    case manual
    /// Read from a photo's metadata.
    case photo

    var displayName: String {
        switch self {
        case .manual: return "Entered by hand"
        case .photo: return "Read from a photo"
        }
    }
}
