//
//  Optics.swift
//  ShutterManager
//
//  Depth of field, hyperfocal distance, field of view and crop-factor equivalents.
//  Foundation-only; lengths in millimetres. Sources: docs/PHOTO_MATH_REFERENCES.md § Depth of
//  field, § Field of view.
//

import Foundation

/// Depth of field for a thin lens focused at a distance.
///
/// Distances are from the lens, in millimetres. The thin-lens formulas are accurate to a few
/// percent for normal focusing distances; they overstate depth at macro distances, where the
/// app doesn't offer them (focus must be beyond `focalLength`).
struct DepthOfField: Equatable {
    let focalLength: Double
    let aperture: Double
    let focusDistance: Double
    let circleOfConfusion: Double

    /// Focus here and everything from half this distance to infinity is acceptably sharp:
    /// H = f²/(N·c) + f.
    let hyperfocal: Double
    let nearLimit: Double
    /// `.infinity` when focused at or beyond the hyperfocal distance.
    let farLimit: Double

    init?(focalLength f: Double, aperture N: Double, focusDistance s: Double, circleOfConfusion c: Double) {
        guard [f, N, s, c].allSatisfy({ $0.isFinite && $0 > 0 }), s > f else { return nil }
        focalLength = f
        aperture = N
        focusDistance = s
        circleOfConfusion = c
        let h = Self.hyperfocal(focalLength: f, aperture: N, circleOfConfusion: c)
        hyperfocal = h
        nearLimit = s * (h - f) / (h + s - 2 * f)
        farLimit = s < h ? s * (h - f) / (h - s) : .infinity
    }

    static func hyperfocal(focalLength f: Double, aperture N: Double, circleOfConfusion c: Double) -> Double {
        f * f / (N * c) + f
    }

    /// Far limit minus near limit; `.infinity` when the far limit is.
    var total: Double { farLimit - nearLimit }
    var inFront: Double { focusDistance - nearLimit }
    var behind: Double { farLimit - focusDistance }

    /// Near limit when focused at the hyperfocal distance: exactly H/2.
    var hyperfocalNearLimit: Double { hyperfocal / 2 }

    /// The usual circle of confusion: the format's diagonal divided by `divisor` (1500 by
    /// default; larger divisors are stricter).
    static func circleOfConfusion(for format: SensorFormat, divisor: Double = CircleOfConfusionStandard.standard.divisor) -> Double {
        format.diagonal / divisor
    }
}

/// How strict "acceptably sharp" is: the format diagonal is divided by this to get the circle of
/// confusion.
enum CircleOfConfusionStandard: Int, CaseIterable, Identifiable {
    case lenient = 1000
    case standard = 1500
    case zeiss = 1730
    case critical = 3000

    var id: Int { rawValue }
    var divisor: Double { Double(rawValue) }

    var displayName: String {
        switch self {
        case .lenient: return "Lenient (d/1000)"
        case .standard: return "Standard (d/1500)"
        case .zeiss: return "Zeiss (d/1730)"
        case .critical: return "Critical (d/3000)"
        }
    }

    var detail: String {
        switch self {
        case .lenient: return "Small prints and screens"
        case .standard: return "The usual standard, behind most lens scales"
        case .zeiss: return "A little stricter"
        case .critical: return "Large prints viewed up close, or high-resolution sensors"
        }
    }
}

/// Angles of view for a lens on a format, focused at infinity.
struct FieldOfView: Equatable {
    /// Degrees.
    let horizontal: Double
    let vertical: Double
    let diagonal: Double

    init?(focalLength f: Double, sensorWidth width: Double, sensorHeight height: Double) {
        guard [f, width, height].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        horizontal = Self.angle(f, width)
        vertical = Self.angle(f, height)
        diagonal = Self.angle(f, (width * width + height * height).squareRoot())
    }

    init?(focalLength f: Double, format: SensorFormat) {
        self.init(focalLength: f, sensorWidth: format.width, sensorHeight: format.height)
    }

    /// 2·atan(d / 2f), in degrees.
    static func angle(_ focalLength: Double, _ dimension: Double) -> Double {
        2 * atan(dimension / (2 * focalLength)) * 180 / .pi
    }

    /// The 35mm-equivalent focal length: f × crop factor.
    static func equivalentFocalLength(_ focalLength: Double, cropFactor: Double) -> Double {
        focalLength * cropFactor
    }

    /// The focal length giving the same diagonal angle of view on another format.
    static func matchingFocalLength(_ focalLength: Double, from source: SensorFormat, to target: SensorFormat) -> Double {
        focalLength * target.diagonal / source.diagonal
    }

    /// The width and height of the scene a lens frames at a distance (same units as the
    /// distance), by similar triangles. Accurate when the distance is many focal lengths.
    static func frameSize(focalLength f: Double, format: SensorFormat, distance: Double) -> (width: Double, height: Double)? {
        guard f > 0, distance > f, distance.isFinite else { return nil }
        return (distance * format.width / f, distance * format.height / f)
    }
}
