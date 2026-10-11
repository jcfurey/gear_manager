//
//  FilmRoll.swift
//  ShutterManager
//
//  The film roll log: what's in which camera, and where each roll is on its way to scans.
//

import Foundation
import SwiftData

/// One roll (or sheet box) of film, from loading to scanning.
@Model
final class FilmRoll {
    var id: UUID = UUID()
    /// A `FilmStock` ID, built-in or `custom:`.
    var filmStockID: String = ""
    /// A film `SensorFormat` ID ("film35mm", "film6x6"…), or "" when not set.
    var formatID: String = ""
    /// The speed it's exposed at; 0 means the box speed.
    var ratedISO: Int = 0
    /// Development: stops of push (positive) or pull (negative).
    var pushPullStops: Double = 0
    var frameCount: Int = 36
    var framesShot: Int = 0
    /// A `FilmRollStatus` raw value, stored as text (see `status`).
    var statusID: String = "loaded"
    var loadedDate: Date = Date()
    /// When it came out of the camera; nil while it's still loaded.
    var finishedDate: Date? = nil
    var lab: String = ""
    var notes: String = ""
    var dateCreated: Date = Date()

    /// The camera it's in (or was shot in). `GearItem.filmRolls` holds the inverse.
    var camera: GearItem?
    /// The shoot it was used on. `Shoot.filmRolls` holds the inverse.
    var shoot: Shoot?

    init(filmStockID: String = "", formatID: String = SensorFormat.film35mm.id, ratedISO: Int = 0,
         frameCount: Int? = nil, camera: GearItem? = nil, loadedDate: Date = Date()) {
        self.id = UUID()
        self.filmStockID = filmStockID
        self.formatID = formatID
        self.ratedISO = ratedISO
        self.frameCount = frameCount ?? FilmRoll.defaultFrameCount(formatID: formatID)
        self.camera = camera
        self.loadedDate = loadedDate
        self.dateCreated = Date()
    }
}

extension FilmRoll {
    var status: FilmRollStatus {
        get { FilmRollStatus(storedID: statusID) }
        set { statusID = newValue.rawValue }
    }

    var stock: FilmStock? { filmStockID.isEmpty ? nil : FilmStock(id: filmStockID) }

    var format: SensorFormat? { formatID.isEmpty ? nil : SensorFormat(id: formatID) }

    var isLoaded: Bool { status == .loaded }

    /// "Ilford HP5 Plus" or "Film" when no stock is set.
    var displayName: String { stock?.displayName ?? "Film" }

    /// The speed to meter at: the rated speed, else the box speed; nil when neither is known.
    var meteringISO: Int? {
        if ratedISO > 0 { return ratedISO }
        if let iso = stock?.iso, iso > 0 { return iso }
        return nil
    }

    /// Stops between the rated and box speeds: what a lab means by push or pull. Nil without both.
    var ratedStopsFromBox: Double? {
        guard ratedISO > 0, let box = stock?.iso, box > 0 else { return nil }
        return log2(Double(ratedISO) / Double(box))
    }

    /// "Push +1", "Pull −1", or nil at normal development.
    var pushPullText: String? {
        guard pushPullStops.isFinite, abs(pushPullStops) >= 0.05 else { return nil }
        let amount = ExposureScale.decimal(abs(pushPullStops), places: 2)
        return pushPullStops > 0 ? "Push +\(amount)" : "Pull −\(amount)"
    }

    /// Moves the roll along. Leaving `.loaded` stamps when it came out of the camera; going back
    /// to `.loaded` clears it.
    func setStatus(_ newStatus: FilmRollStatus, at date: Date = Date()) {
        status = newStatus
        if newStatus == .loaded {
            finishedDate = nil
        } else if finishedDate == nil {
            finishedDate = date
        }
    }

    /// Exposures a roll of the format usually has.
    static func defaultFrameCount(formatID: String) -> Int {
        switch formatID {
        case SensorFormat.film35mm.id: return 36
        case SensorFormat.filmHalfFrame.id: return 72
        case SensorFormat.film645.id: return 15
        case SensorFormat.film6x6.id: return 12
        case SensorFormat.film6x7.id: return 10
        case SensorFormat.film6x9.id: return 8
        case SensorFormat.sheet4x5.id, SensorFormat.sheet8x10.id: return 10
        case SensorFormat.instaxMini.id, SensorFormat.instaxSquare.id, SensorFormat.instaxWide.id: return 10
        case SensorFormat.polaroid.id: return 8
        default: return 36
        }
    }
}

/// Where a roll is. Raw values are stored: never rename or remove one.
enum FilmRollStatus: String, CaseIterable, Identifiable, Sendable {
    case loaded, shot, atLab, developed, scanned

    var id: String { rawValue }

    /// A status from a newer version reads as `.shot`: out of the camera and on its way, so it's
    /// never offered as the camera's loaded roll. The stored text is kept as it is.
    init(storedID: String) {
        self = FilmRollStatus(rawValue: storedID) ?? .shot
    }

    var displayName: String {
        switch self {
        case .loaded: return "Loaded"
        case .shot: return "Shot"
        case .atLab: return "At the lab"
        case .developed: return "Developed"
        case .scanned: return "Scanned"
        }
    }

    var systemImage: String {
        switch self {
        case .loaded: return "film"
        case .shot: return "checkmark.circle"
        case .atLab: return "shippingbox"
        case .developed: return "drop"
        case .scanned: return "photo.on.rectangle"
        }
    }

    /// The next step, or nil once scanned.
    var next: FilmRollStatus? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

extension GearItem {
    /// The roll in this camera now: the most recently loaded one still marked loaded.
    var loadedRoll: FilmRoll? {
        (filmRolls ?? []).filter(\.isLoaded).max { $0.loadedDate < $1.loadedDate }
    }
}
