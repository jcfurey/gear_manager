//
//  Calculators.swift
//  ShutterManager
//
//  Astrophotography exposure limits, star trails, time-lapse planning, flash guide numbers and
//  print size. Foundation-only. Sources: docs/PHOTO_MATH_REFERENCES.md § Astro, § Time-lapse,
//  § Flash, § Print size.
//

import Foundation

// MARK: - Astro

/// The longest exposure before stars visibly trail, for a fixed (untracked) camera.
enum AstroExposure {
    /// The 500 rule: 500 ÷ (focal length × crop factor) seconds. A film-era rule of thumb; on
    /// high-resolution sensors stars trail visibly sooner, which the NPF rule accounts for.
    static func rule500(focalLength: Double, cropFactor: Double) -> Double? {
        guard focalLength > 0, cropFactor > 0, focalLength.isFinite, cropFactor.isFinite else { return nil }
        return 500 / (focalLength * cropFactor)
    }

    /// The simplified NPF rule (Michaud): (35·N + 30·p) ÷ f seconds, with N the f-number, p the
    /// pixel pitch in µm and f the real focal length in mm.
    static func npf(focalLength: Double, aperture: Double, pixelPitchMicrons: Double) -> Double? {
        guard [focalLength, aperture, pixelPitchMicrons].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return (35 * aperture + 30 * pixelPitchMicrons) / focalLength
    }

    /// Pixel pitch in µm: sensor width ÷ horizontal pixels (the long side of each).
    static func pixelPitch(sensorWidth: Double, sensorHeight: Double, pixelsWide: Int, pixelsHigh: Int) -> Double? {
        let longSide = max(sensorWidth, sensorHeight)
        let longPixels = max(pixelsWide, pixelsHigh)
        guard longSide > 0, longPixels > 0 else { return nil }
        return longSide * 1000 / Double(longPixels)
    }
}

/// Star trails from the Earth's rotation.
enum StarTrails {
    /// The sky turns 360° in a sidereal day of 23 h 56 min 4.1 s: about 15.041° per hour.
    static let siderealDaySeconds = 86_164.0905
    static let degreesPerHour = 360 / (siderealDaySeconds / 3600)

    /// How far the stars turn around the celestial pole in `seconds`, in degrees.
    static func rotation(seconds: Double) -> Double {
        seconds / siderealDaySeconds * 360
    }

    /// How long the stars take to turn `degrees` around the pole, in seconds.
    static func duration(forRotation degrees: Double) -> Double {
        degrees / 360 * siderealDaySeconds
    }

    /// Frames for a stacked trail: total time ÷ (exposure + gap between frames), rounded down.
    static func frames(totalSeconds: Double, exposure: Double, gap: Double = 0) -> Int {
        let cycle = exposure + max(gap, 0)
        guard totalSeconds > 0, exposure > 0, cycle.isFinite, totalSeconds.isFinite else { return 0 }
        return Int((totalSeconds / cycle).rounded(.down))
    }
}

// MARK: - Time-lapse

/// A time-lapse: how many frames an event gives at an interval, and how long the clip plays.
struct TimeLapsePlan: Equatable {
    /// Seconds of real time the sequence covers.
    let eventDuration: Double
    /// Seconds between frames.
    let interval: Double
    let framesPerSecond: Double

    init?(eventDuration: Double, interval: Double, framesPerSecond: Double) {
        guard [eventDuration, interval, framesPerSecond].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        self.eventDuration = eventDuration
        self.interval = interval
        self.framesPerSecond = framesPerSecond
    }

    /// Whole frames the event gives: event ÷ interval, rounded down.
    var frames: Int { Int((eventDuration / interval).rounded(.down)) }

    /// Seconds the finished clip plays: frames ÷ fps.
    var clipDuration: Double { Double(frames) / framesPerSecond }

    /// How much faster than real time the clip plays: interval × fps.
    var speedUp: Double { interval * framesPerSecond }

    /// Card space for the sequence, in the units of `fileSize`.
    func storage(fileSize: Double) -> Double { Double(frames) * fileSize }

    /// An exposure fits an interval when it ends before the next frame starts, leaving the camera
    /// `margin` seconds to write the file.
    func fits(exposure seconds: Double, margin: Double = 0.5) -> Bool {
        seconds + margin <= interval
    }

    /// The interval that turns an event into a clip of the given length: event ÷ (clip × fps).
    static func interval(eventDuration: Double, clipDuration: Double, framesPerSecond: Double) -> Double? {
        guard [eventDuration, clipDuration, framesPerSecond].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return eventDuration / (clipDuration * framesPerSecond)
    }
}

// MARK: - Flash

/// Manual flash exposure from a guide number. Guide numbers here are in metres at ISO 100, the
/// way makers quote them; GN = distance × f-number.
enum FlashExposure {
    /// The guide number scales with the square root of the ISO ratio.
    static func isoFactor(_ iso: Double) -> Double { (iso / 100).squareRoot() }

    /// The flash-to-subject distance that's correctly exposed: GN·√(ISO/100) ÷ N.
    static func distance(guideNumber: Double, aperture: Double, iso: Double) -> Double? {
        guard [guideNumber, aperture, iso].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return guideNumber * isoFactor(iso) / aperture
    }

    /// The f-number for a subject at `distance`: GN·√(ISO/100) ÷ distance.
    static func aperture(guideNumber: Double, distance: Double, iso: Double) -> Double? {
        guard [guideNumber, distance, iso].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return guideNumber * isoFactor(iso) / distance
    }

    /// The ISO 100 guide number a flash needs to light `distance` at `aperture` and `iso`.
    static func requiredGuideNumber(distance: Double, aperture: Double, iso: Double) -> Double? {
        guard [distance, aperture, iso].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return distance * aperture / isoFactor(iso)
    }

    /// The guide number at a fraction of full power (1/2, 1/4…): GN × √fraction.
    static func guideNumber(_ fullPower: Double, atPower fraction: Double) -> Double {
        fullPower * max(fraction, 0).squareRoot()
    }

    /// Manual power settings from full to 1/128.
    static let powerLevels: [(label: String, fraction: Double)] =
        (0...7).map { step in (step == 0 ? "1/1" : "1/\(1 << step)", 1 / Double(1 << step)) }

    static let feetPerMetre = 3.280_84
}

// MARK: - Print size

/// Print size from pixel dimensions and print resolution (dots per inch).
enum PrintSize {
    static let millimetresPerInch = 25.4

    /// Inches: pixels ÷ DPI.
    static func inches(pixels: Int, dpi: Double) -> Double? {
        guard pixels > 0, dpi > 0, dpi.isFinite else { return nil }
        return Double(pixels) / dpi
    }

    /// DPI when `pixels` cover `inches`.
    static func dpi(pixels: Int, inches: Double) -> Double? {
        guard pixels > 0, inches > 0, inches.isFinite else { return nil }
        return Double(pixels) / inches
    }

    /// Pixels needed to cover `inches` at `dpi`, rounded up.
    static func pixels(inches: Double, dpi: Double) -> Int? {
        guard inches > 0, dpi > 0, inches.isFinite, dpi.isFinite else { return nil }
        return Int((inches * dpi).rounded(.up))
    }

    /// How a resolution holds up, by common print-shop guidance.
    enum Quality: Int, Comparable {
        case low, viewedFromDistance, good, best

        static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

        init(dpi: Double) {
            switch dpi {
            case 300...: self = .best
            case 200..<300: self = .good
            case 150..<200: self = .viewedFromDistance
            default: self = .low
            }
        }

        var displayName: String {
            switch self {
            case .best: return "Best: close viewing"
            case .good: return "Good for most prints"
            case .viewedFromDistance: return "Fine viewed from a distance"
            case .low: return "Likely to look soft"
            }
        }
    }

    /// A paper size, in inches, short side first.
    struct Paper: Hashable, Identifiable {
        let name: String
        let shortSide: Double
        let longSide: Double
        var id: String { name }
    }

    static let papers: [Paper] = [
        Paper(name: "4 × 6 in", shortSide: 4, longSide: 6),
        Paper(name: "5 × 7 in", shortSide: 5, longSide: 7),
        Paper(name: "8 × 10 in", shortSide: 8, longSide: 10),
        Paper(name: "8 × 12 in", shortSide: 8, longSide: 12),
        Paper(name: "11 × 14 in", shortSide: 11, longSide: 14),
        Paper(name: "12 × 18 in", shortSide: 12, longSide: 18),
        Paper(name: "13 × 19 in", shortSide: 13, longSide: 19),
        Paper(name: "16 × 20 in", shortSide: 16, longSide: 20),
        Paper(name: "16 × 24 in", shortSide: 16, longSide: 24),
        Paper(name: "20 × 30 in", shortSide: 20, longSide: 30),
        Paper(name: "24 × 36 in", shortSide: 24, longSide: 36),
        Paper(name: "A5", shortSide: 148 / millimetresPerInch, longSide: 210 / millimetresPerInch),
        Paper(name: "A4", shortSide: 210 / millimetresPerInch, longSide: 297 / millimetresPerInch),
        Paper(name: "A3", shortSide: 297 / millimetresPerInch, longSide: 420 / millimetresPerInch),
        Paper(name: "A3+", shortSide: 329 / millimetresPerInch, longSide: 483 / millimetresPerInch),
        Paper(name: "A2", shortSide: 420 / millimetresPerInch, longSide: 594 / millimetresPerInch),
        Paper(name: "A1", shortSide: 594 / millimetresPerInch, longSide: 841 / millimetresPerInch)
    ]

    /// The DPI an image gets on a paper when it fills it, long side to long side. When the
    /// aspect ratios differ, the image is cropped to fill, so the tighter side decides.
    static func fillDPI(pixelsWide: Int, pixelsHigh: Int, paper: Paper) -> Double? {
        guard pixelsWide > 0, pixelsHigh > 0 else { return nil }
        let longPixels = Double(max(pixelsWide, pixelsHigh)), shortPixels = Double(min(pixelsWide, pixelsHigh))
        return min(longPixels / paper.longSide, shortPixels / paper.shortSide)
    }
}
