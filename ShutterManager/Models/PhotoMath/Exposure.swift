//
//  Exposure.swift
//  ShutterManager
//
//  Exposure value, equivalent exposures, ND filters and the Sunny 16 rule.
//  Foundation-only. Sources: docs/PHOTO_MATH_REFERENCES.md § Exposure, § ND filters, § Sunny 16.
//

import Foundation

/// An aperture, shutter time and ISO speed.
struct ExposureSettings: Equatable {
    /// f-number.
    var aperture: Double
    /// Seconds.
    var shutter: Double
    var iso: Double

    var isValid: Bool {
        [aperture, shutter, iso].allSatisfy { $0.isFinite && $0 > 0 }
    }

    /// EV at the given ISO: log₂(N²/t). Higher means less light reaches the film or sensor.
    var ev: Double { log2(aperture * aperture / shutter) }

    /// The scene brightness this exposure suits, as EV at ISO 100: EV − log₂(ISO/100).
    var ev100: Double { ev - log2(iso / 100) }

    /// The shutter time giving the same exposure at another aperture and ISO.
    func shutter(atAperture newAperture: Double, iso newISO: Double) -> Double {
        shutter * (newAperture * newAperture) / (aperture * aperture) * (iso / newISO)
    }

    /// The f-number giving the same exposure at another shutter time and ISO.
    func aperture(atShutter newShutter: Double, iso newISO: Double) -> Double {
        aperture * ((newShutter / shutter) * (newISO / iso)).squareRoot()
    }

    /// The ISO giving the same exposure at another aperture and shutter time.
    func iso(atAperture newAperture: Double, shutter newShutter: Double) -> Double {
        iso * (newAperture * newAperture) / (aperture * aperture) * (shutter / newShutter)
    }

    /// Stops more light than `other` gives (negative when darker).
    func stops(brighterThan other: ExposureSettings) -> Double {
        other.ev100 - ev100
    }
}

// MARK: - ND filters

/// Neutral-density filters, which the box can label three ways: stops, filter factor (ND8,
/// ND1000) or optical density (0.9, 3.0).
enum NDFilter {
    /// One stop per 0.3 of optical density, the convention filter makers label by: "0.9" is sold as
    /// 3 stops and "3.0" as 10. (Exactly, one stop is log₁₀ 2 ≈ 0.301.)
    static let densityPerStop = 0.3

    static func stops(density: Double) -> Double { density / densityPerStop }
    static func density(stops: Double) -> Double { stops * densityPerStop }
    static func factor(stops: Double) -> Double { pow(2, stops) }
    static func stops(factor: Double) -> Double { log2(factor) }

    /// The shutter time with filters totalling `stops` in front of the lens: t · 2^stops.
    /// Stacked filters add their stops.
    static func exposure(base seconds: Double, stops: Double) -> Double {
        seconds * pow(2, stops)
    }

    /// A filter as it's sold.
    struct Preset: Hashable, Identifiable {
        let stops: Double
        /// "ND8", "ND1000".
        let factorName: String
        /// "0.9", "3.0".
        let densityName: String

        var id: Double { stops }
        var label: String { "\(factorName) · \(densityName) · \(ExposureScale.decimal(stops, places: 1)) stops" }
    }

    static let presets: [Preset] = [
        Preset(stops: 1, factorName: "ND2", densityName: "0.3"),
        Preset(stops: 2, factorName: "ND4", densityName: "0.6"),
        Preset(stops: 3, factorName: "ND8", densityName: "0.9"),
        Preset(stops: 4, factorName: "ND16", densityName: "1.2"),
        Preset(stops: 5, factorName: "ND32", densityName: "1.5"),
        Preset(stops: 6, factorName: "ND64", densityName: "1.8"),
        Preset(stops: 7, factorName: "ND128", densityName: "2.1"),
        Preset(stops: 8, factorName: "ND256", densityName: "2.4"),
        Preset(stops: 9, factorName: "ND500", densityName: "2.7"),
        Preset(stops: 10, factorName: "ND1000", densityName: "3.0"),
        Preset(stops: 13, factorName: "ND8000", densityName: "3.9"),
        Preset(stops: 15, factorName: "ND32000", densityName: "4.5"),
        Preset(stops: 16, factorName: "ND65000", densityName: "4.8"),
        Preset(stops: 20, factorName: "ND1000000", densityName: "6.0")
    ]
}

// MARK: - Sunny 16

/// The Sunny 16 rule: in bright sun, f/16 at a shutter time of 1/ISO, opening up for duller light.
enum SunnySixteen {
    enum Condition: String, CaseIterable, Identifiable {
        case snowOrSand, sunny, slightOvercast, overcast, heavyOvercast, openShade

        var id: String { rawValue }

        /// The f-number the rule gives at 1/ISO.
        var aperture: Double {
            switch self {
            case .snowOrSand: return 22
            case .sunny: return 16
            case .slightOvercast: return 11
            case .overcast: return 8
            case .heavyOvercast: return 5.6
            case .openShade: return 4
            }
        }

        /// Stops more light than full sun needs.
        var stopsFromSunny: Int {
            switch self {
            case .snowOrSand: return -1
            case .sunny: return 0
            case .slightOvercast: return 1
            case .overcast: return 2
            case .heavyOvercast: return 3
            case .openShade: return 4
            }
        }

        var displayName: String {
            switch self {
            case .snowOrSand: return "Snow or sand"
            case .sunny: return "Bright sun"
            case .slightOvercast: return "Slight overcast"
            case .overcast: return "Overcast"
            case .heavyOvercast: return "Heavy overcast"
            case .openShade: return "Open shade or sunset"
            }
        }

        var shadowHint: String {
            switch self {
            case .snowOrSand: return "Dark, distinct shadows"
            case .sunny: return "Distinct shadows"
            case .slightOvercast: return "Soft edges on shadows"
            case .overcast: return "Shadows barely visible"
            case .heavyOvercast: return "No shadows"
            case .openShade: return "Subject in shade, or the sun on the horizon"
            }
        }

        var systemImage: String {
            switch self {
            case .snowOrSand: return "snowflake"
            case .sunny: return "sun.max"
            case .slightOvercast: return "cloud.sun"
            case .overcast: return "cloud"
            case .heavyOvercast: return "smoke"
            case .openShade: return "sun.horizon"
            }
        }
    }

    /// The rule's exposure at an exact ISO: the condition's aperture (exact, from the third-stop
    /// scale) and 1/ISO.
    static func exposure(iso: Double, condition: Condition) -> ExposureSettings {
        let sunnyAperture = ExposureScale.apertureValue(thirds: 24) // f/16
        let aperture = sunnyAperture / pow(2, Double(condition.stopsFromSunny) / 2)
        return ExposureSettings(aperture: aperture, shutter: 1 / iso, iso: iso)
    }
}
