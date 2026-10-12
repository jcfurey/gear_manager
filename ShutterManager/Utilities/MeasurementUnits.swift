//
//  MeasurementUnits.swift
//  ShutterManager
//
//  Metric or imperial for the tools' distances and temperatures.
//

import Foundation

/// Which units the tools show. Stored under `Constants.UserDefaultsKeys.measurementUnits`.
enum UnitPreference: String, CaseIterable, Identifiable {
    case automatic, metric, imperial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .metric: return "Metric (m, °C)"
        case .imperial: return "Imperial (ft, °F)"
        }
    }

    /// Whether to show metric units: the device region decides for `.automatic`.
    func usesMetric(locale: Locale = .current) -> Bool {
        switch self {
        case .metric: return true
        case .imperial: return false
        case .automatic: return locale.measurementSystem != .us
        }
    }
}

/// Conversions between what the user types and what the math uses (millimetres, °C).
struct MeasurementUnits: Equatable {
    let metric: Bool

    init(metric: Bool) { self.metric = metric }

    init(preference: String, locale: Locale = .current) {
        metric = (UnitPreference(rawValue: preference) ?? .automatic).usesMetric(locale: locale)
    }

    static let millimetresPerFoot = 304.8

    // MARK: - Distance

    var distanceUnit: String { metric ? "m" : "ft" }

    /// Millimetres for a distance typed in metres or feet.
    func millimetres(fromDisplay value: Double) -> Double {
        value * (metric ? 1000 : Self.millimetresPerFoot)
    }

    /// Metres or feet for a distance in millimetres.
    func displayDistance(millimetres: Double) -> Double {
        millimetres / (metric ? 1000 : Self.millimetresPerFoot)
    }

    /// "3.39 m", "11.1 ft", "∞". Short distances get more decimals.
    func format(millimetres: Double) -> String {
        guard millimetres.isFinite else { return "∞" }
        let value = displayDistance(millimetres: millimetres)
        let digits = abs(value) < 10 ? 2 : (abs(value) < 100 ? 1 : 0)
        return value.formatted(.number.precision(.fractionLength(0...digits))) + " " + distanceUnit
    }

    // MARK: - Temperature

    var temperatureUnit: String { metric ? "°C" : "°F" }

    func celsius(fromDisplay value: Double) -> Double {
        metric ? value : (value - 32) * 5 / 9
    }

    func displayTemperature(celsius: Double) -> Double {
        metric ? celsius : celsius * 9 / 5 + 32
    }

    /// "20 °C", "68 °F", to a tenth of a degree.
    func format(celsius: Double) -> String {
        displayTemperature(celsius: celsius).formatted(.number.precision(.fractionLength(0...1))) + " " + temperatureUnit
    }
}
