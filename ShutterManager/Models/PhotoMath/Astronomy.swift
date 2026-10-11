//
//  Astronomy.swift
//  ShutterManager
//
//  Time scales, angles and coordinate conversions shared by the sun, moon and Milky Way
//  calculations. Foundation-only. Methods from Meeus, *Astronomical Algorithms* (2nd ed., 1998);
//  see docs/PHOTO_MATH_REFERENCES.md § Sun and moon.
//

import Foundation

/// A place on Earth. Latitude north and longitude east are positive, in degrees.
struct GeoCoordinate: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    /// The point `distance` metres away along `bearing` (degrees from north), on a sphere. For
    /// drawing sun and moon directions on a map.
    func destination(bearing: Double, distance: Double) -> GeoCoordinate {
        let radius = 6_371_000.0
        let angular = distance / radius
        let φ1 = latitude.radians, λ1 = longitude.radians, θ = bearing.radians
        let φ2 = asin(sin(φ1) * cos(angular) + cos(φ1) * sin(angular) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(angular) * cos(φ1), cos(angular) - sin(φ1) * sin(φ2))
        return GeoCoordinate(latitude: φ2.degrees, longitude: AngleMath.normalizedSigned(λ2.degrees))
    }
}

/// A body's position in the sky, as seen from a place.
struct HorizontalPosition: Equatable, Sendable {
    /// Degrees above the horizon (negative below), without atmospheric refraction.
    let altitude: Double
    /// Degrees east of true north.
    let azimuth: Double
}

/// Right ascension and declination, in degrees, of date.
struct EquatorialPosition: Equatable, Sendable {
    let rightAscension: Double
    let declination: Double
}

// MARK: - Angles

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

enum AngleMath {
    /// `degrees` in 0..<360.
    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// `degrees` in -180..<180.
    static func normalizedSigned(_ degrees: Double) -> Double {
        let value = normalized(degrees)
        return value >= 180 ? value - 360 : value
    }

    /// The compass point for an azimuth: "N", "NNE", …
    static func compassPoint(_ azimuth: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return points[Int((normalized(azimuth) / 22.5).rounded()) % 16]
    }
}

// MARK: - Time

/// Astronomical time for an instant: the Julian Day in Universal Time and in Terrestrial
/// (dynamical) Time, which the planetary theories use.
struct AstroTime: Equatable, Sendable {
    /// Julian Day, UT.
    let jd: Double
    /// Julian Ephemeris Day, TT = UT + ΔT.
    let jde: Double

    static let j2000 = 2_451_545.0

    init(_ date: Date) {
        jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        jde = jd + Self.deltaT(year: Self.decimalYear(jd: jd)) / 86_400
    }

    /// From a Julian Ephemeris Day (as Meeus's worked examples give it).
    init(jde: Double) {
        self.jde = jde
        jd = jde - Self.deltaT(year: Self.decimalYear(jd: jde)) / 86_400
    }

    var date: Date { Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400) }

    /// Julian centuries of TT from J2000.0.
    var centuries: Double { (jde - Self.j2000) / 36_525 }

    static func decimalYear(jd: Double) -> Double { 2000 + (jd - j2000) / 365.25 }

    /// ΔT = TT − UT in seconds: Espenak and Meeus's polynomials (NASA, 2006). Their 2005–2050
    /// fit runs a few seconds above the observed value in the 2020s, which moves the moon by
    /// about 3″, far below what the app shows.
    static func deltaT(year y: Double) -> Double {
        switch y {
        case 2005..<2050:
            let t = y - 2000
            return 62.92 + 0.32217 * t + 0.005589 * t * t
        case 2050..<2150:
            let u = (y - 1820) / 100
            return -20 + 32 * u * u - 0.5628 * (2150 - y)
        case 1986..<2005:
            let t = y - 2000
            return 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * pow(t, 3)
                + 0.000651814 * pow(t, 4) + 0.00002373599 * pow(t, 5)
        default:
            let u = (y - 1820) / 100
            return -20 + 32 * u * u
        }
    }
}

// MARK: - Earth's orientation

enum EarthOrientation {
    /// Nutation in longitude and obliquity, in degrees: Meeus ch. 22, the 0.5″ version.
    static func nutation(_ time: AstroTime) -> (longitude: Double, obliquity: Double) {
        let t = time.centuries
        let omega = (125.04452 - 1934.136261 * t).radians
        let sunL = (280.4665 + 36000.7698 * t).radians
        let moonL = (218.3165 + 481267.8813 * t).radians
        let dPsi = -17.20 * sin(omega) - 1.32 * sin(2 * sunL) - 0.23 * sin(2 * moonL) + 0.21 * sin(2 * omega)
        let dEps = 9.20 * cos(omega) + 0.57 * cos(2 * sunL) + 0.10 * cos(2 * moonL) - 0.09 * cos(2 * omega)
        return (dPsi / 3600, dEps / 3600)
    }

    /// Mean obliquity of the ecliptic, degrees (Meeus 22.2).
    static func meanObliquity(_ time: AstroTime) -> Double {
        let t = time.centuries
        return 23.439_291_111 - (46.8150 * t + 0.000_59 * t * t - 0.001_813 * t * t * t) / 3600
    }

    /// True obliquity: mean plus nutation.
    static func obliquity(_ time: AstroTime) -> Double {
        meanObliquity(time) + nutation(time).obliquity
    }

    /// Apparent sidereal time at Greenwich, degrees (Meeus 12.4, plus the equation of the
    /// equinoxes).
    static func greenwichSiderealTime(_ time: AstroTime) -> Double {
        let d = time.jd - AstroTime.j2000
        let t = d / 36_525
        let mean = 280.460_618_37 + 360.985_647_366_29 * d + 0.000_387_933 * t * t - t * t * t / 38_710_000
        let nutation = nutation(time)
        return AngleMath.normalized(mean + nutation.longitude * cos(obliquity(time).radians))
    }
}

// MARK: - Conversions

enum SkyCoordinates {
    /// Ecliptic longitude and latitude (degrees, of date) to right ascension and declination.
    static func equatorial(longitude λ: Double, latitude β: Double, obliquity ε: Double) -> EquatorialPosition {
        let l = λ.radians, b = β.radians, e = ε.radians
        let ra = atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
        let dec = asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
        return EquatorialPosition(rightAscension: AngleMath.normalized(ra.degrees), declination: dec.degrees)
    }

    /// Altitude and azimuth of `position` from `observer` at `time` (Meeus 13.5, 13.6).
    static func horizontal(_ position: EquatorialPosition, observer: GeoCoordinate, time: AstroTime) -> HorizontalPosition {
        let hourAngle = (EarthOrientation.greenwichSiderealTime(time) + observer.longitude - position.rightAscension).radians
        let φ = observer.latitude.radians, δ = position.declination.radians
        let altitude = asin(sin(φ) * sin(δ) + cos(φ) * cos(δ) * cos(hourAngle))
        // Meeus measures azimuth from the south; turn it to measure from the north.
        let fromSouth = atan2(sin(hourAngle), cos(hourAngle) * sin(φ) - tan(δ) * cos(φ))
        return HorizontalPosition(altitude: altitude.degrees, azimuth: AngleMath.normalized(fromSouth.degrees + 180))
    }

    /// Atmospheric refraction in degrees for a true altitude (Sæmundsson, Meeus 16.4): what to
    /// add to show where a body appears. Not used for rise and set, whose standard altitudes
    /// already include it.
    static func refraction(trueAltitude h: Double) -> Double {
        guard h > -2 else { return 0 }
        return 1.02 / tan((h + 10.3 / (h + 5.11)).radians) / 60
    }
}
