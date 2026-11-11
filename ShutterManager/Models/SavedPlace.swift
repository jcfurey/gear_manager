//
//  SavedPlace.swift
//  ShutterManager
//
//  Places you shoot, for planning the sun, moon and Milky Way there.
//

import Foundation
import SwiftData

/// A named place with its coordinates and time zone. Synced and exported.
@Model
final class SavedPlace {
    var id: UUID = UUID()
    var name: String = ""
    /// Degrees, north positive.
    var latitude: Double = 0
    /// Degrees, east positive.
    var longitude: Double = 0
    /// An IANA identifier ("Europe/London"); "" means the device's own time zone.
    var timeZoneIdentifier: String = ""
    var notes: String = ""
    var dateAdded: Date = Date()

    init(name: String = "", coordinate: GeoCoordinate = GeoCoordinate(latitude: 0, longitude: 0),
         timeZoneIdentifier: String = "", notes: String = "") {
        self.id = UUID()
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.notes = notes
        self.dateAdded = Date()
    }

    var coordinate: GeoCoordinate { GeoCoordinate(latitude: latitude, longitude: longitude) }

    var value: PlaceValue {
        PlaceValue(name: name, coordinate: coordinate, timeZoneIdentifier: timeZoneIdentifier, savedPlaceID: id)
    }
}

/// A place as the planners use it: saved, picked on the map, or the current location. Stored per
/// device (the planner remembers its last place) as JSON.
struct PlaceValue: Codable, Hashable, Sendable {
    var name: String
    var coordinate: GeoCoordinate
    /// "" means the device's time zone.
    var timeZoneIdentifier: String
    /// Set when the place came from (or was saved as) a `SavedPlace`.
    var savedPlaceID: UUID?

    var timeZone: TimeZone {
        timeZoneIdentifier.isEmpty ? .current : (TimeZone(identifier: timeZoneIdentifier) ?? .current)
    }

    /// "51.4769° N, 0.0005° W".
    var coordinateText: String { Self.coordinateText(coordinate) }

    static func coordinateText(_ coordinate: GeoCoordinate) -> String {
        let lat = String(format: "%.4f° %@", abs(coordinate.latitude), coordinate.latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.4f° %@", abs(coordinate.longitude), coordinate.longitude >= 0 ? "E" : "W")
        return "\(lat), \(lon)"
    }

    /// JSON for `@AppStorage`; "" when it can't be encoded.
    var stored: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    init(name: String, coordinate: GeoCoordinate, timeZoneIdentifier: String = "", savedPlaceID: UUID? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.savedPlaceID = savedPlaceID
    }

    /// Decodes `stored`; nil for "" or anything invalid.
    init?(stored: String) {
        guard let data = stored.data(using: .utf8),
              let value = try? JSONDecoder().decode(PlaceValue.self, from: data),
              value.coordinate.isValid else { return nil }
        self = value
    }

    /// Degrees typed or pasted into a coordinate field; nil when the text isn't a number.
    ///
    /// A coordinate copied from a map has a point for its decimals ("48.137154") whatever the
    /// region, so a point reads as the decimal separator everywhere; a comma is read by the
    /// region's own rules. Read the German way, "48.137154" was refused and "0.125" became 125.
    static func degrees(from text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{2212}", with: "-")
        if trimmed.contains("."), !trimmed.contains(",") {
            guard let value = Double(trimmed), value.isFinite else { return nil }
            return value
        }
        return Double(localizedInput: trimmed, locale: locale)
    }

    /// Degrees for a coordinate field, in the region's number format, to five decimals (about
    /// a metre). `degrees(from:)` reads it back.
    static func fieldText(degrees: Double, locale: Locale = .current) -> String {
        MeasurementInput.text(degrees, fractionDigits: 5, locale: locale)
    }
}
