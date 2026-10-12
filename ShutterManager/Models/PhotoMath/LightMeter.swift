//
//  LightMeter.swift
//  ShutterManager
//
//  Turning a reflected-light reading into exposure settings, on the cameras' third-stop scales.
//  Foundation-only. Sources: docs/PHOTO_MATH_REFERENCES.md § Light meter.
//

import Foundation

/// What a camera's auto-exposure settled on, and how far its picture is from the brightness it
/// aims for.
struct CameraExposure: Equatable, Sendable {
    /// The lens's f-number (fixed on phone cameras).
    var aperture: Double
    /// Seconds.
    var shutter: Double
    var iso: Double
    /// How many EV brighter than its target the picture is (`AVCaptureDevice.exposureTargetOffset`).
    /// Auto-exposure keeps it near 0 until it runs out of shutter or ISO range.
    var targetOffset: Double

    /// The scene as EV at ISO 100: the settings' EV₁₀₀ plus the offset. A picture one stop too
    /// bright means the scene is one EV brighter than the settings suit. Nil for unusable values.
    var ev100: Double? {
        let settings = ExposureSettings(aperture: aperture, shutter: shutter, iso: iso)
        guard settings.isValid, targetOffset.isFinite else { return nil }
        return settings.ev100 + targetOffset
    }
}

enum LightMeter {
    /// The EV range a reading or typed value is kept in: from faint starlight to beyond snow in
    /// full sun.
    static let evRange: ClosedRange<Double> = -10...25
    /// How far the calibration can move a reading, in EV.
    static let calibrationRange: ClosedRange<Double> = -5...5

    /// Which setting you choose; the meter solves for another.
    enum Priority: String, CaseIterable, Identifiable {
        case aperture, shutter, iso

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .aperture: return "Aperture"
            case .shutter: return "Shutter"
            case .iso: return "ISO"
            }
        }
    }

    /// Settings for a scene, with the solved setting on the camera's third-stop scale.
    struct Solution: Equatable {
        /// The settings to use: the two you chose as given, the solved one snapped to the scale.
        var settings: ExposureSettings
        /// The solved value before snapping.
        var exact: Double
        /// False when the solved value is off the scale: faster than 1/8000, wider than f/1,
        /// narrower than f/64, or an ISO outside 6–102400. Times longer than 30 s stay in range,
        /// unsnapped, for bulb exposures.
        var inRange: Bool
    }

    /// Solves for the setting `priority` leaves free.
    /// - Parameters:
    ///   - ev100: The scene as metered, without the filters.
    ///   - filterStops: Filters in front of the lens that the meter didn't see. Each stop needs
    ///     twice the exposure.
    static func solve(ev100: Double, priority: Priority, aperture: Double, shutter: Double, iso: Double,
                      filterStops: Double = 0) -> Solution? {
        guard ev100.isFinite, filterStops.isFinite,
              [aperture, shutter, iso].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        // The scene as the film or sensor sees it through the filters.
        let target = ev100 - filterStops
        switch priority {
        case .aperture:
            // log₂(N²/t) = EV₁₀₀ + log₂(S/100)
            let exact = aperture * aperture / pow(2, target + log2(iso / 100))
            let (value, inRange) = snapShutter(exact)
            return Solution(settings: ExposureSettings(aperture: aperture, shutter: value, iso: iso),
                            exact: exact, inRange: inRange)
        case .shutter:
            let exact = (shutter * pow(2, target + log2(iso / 100))).squareRoot()
            let (value, inRange) = snap(exact, to: ExposureScale.apertures())
            return Solution(settings: ExposureSettings(aperture: value, shutter: shutter, iso: iso),
                            exact: exact, inRange: inRange)
        case .iso:
            let exact = 100 * pow(2, log2(aperture * aperture / shutter) - target)
            let (value, inRange) = snap(exact, to: ExposureScale.isoSpeeds())
            return Solution(settings: ExposureSettings(aperture: aperture, shutter: shutter, iso: value),
                            exact: exact, inRange: inRange)
        }
    }

    /// Half a third of a stop: how far past either end of a scale a value still snaps to it.
    private static let snapTolerance = pow(2, 1.0 / 6)

    private static func snap(_ value: Double, to scale: [ScaleValue]) -> (Double, Bool) {
        let values = scale.map(\.value)
        guard value.isFinite, value > 0, let low = values.min(), let high = values.max(),
              value >= low / snapTolerance, value <= high * snapTolerance,
              let mark = ExposureScale.nearest(to: value, in: scale) else { return (value, false) }
        return (mark.value, true)
    }

    /// Shutter times snap to the scale; longer than 30 s they're kept as they are, for bulb.
    private static func snapShutter(_ seconds: Double) -> (Double, Bool) {
        let longest = ExposureScale.shutterValue(thirds: ExposureScale.shutterRange.lowerBound)
        if seconds.isFinite, seconds > longest * snapTolerance { return (seconds, true) }
        return snap(seconds, to: ExposureScale.shutterSpeeds())
    }

    /// Steadies a live reading. Small changes ease in by `factor` each sample; a change of `jump`
    /// EV or more (pointing at something else) is taken at once.
    static func smoothed(_ new: Double, previous: Double?, factor: Double = 0.3, jump: Double = 1) -> Double {
        guard let previous, previous.isFinite, abs(new - previous) < jump else { return new }
        return previous + (new - previous) * factor
    }

    /// The calibration that makes this meter agree with one you trust, metering the same scene:
    /// their difference to a tenth of an EV, within `calibrationRange`.
    static func calibration(trusted: Double, measured: Double) -> Double? {
        guard trusted.isFinite, measured.isFinite else { return nil }
        let difference = ((trusted - measured) * 10).rounded() / 10
        return min(max(difference, calibrationRange.lowerBound), calibrationRange.upperBound)
    }

    /// "+0.3", "−0.7", "0": a correction to a tenth of an EV, signed.
    static func signedEVLabel(_ ev: Double) -> String {
        let text = evLabel(ev)
        return ev.isFinite && (ev * 10).rounded() > 0 ? "+" + text : text
    }

    /// "12.3", "−1", "0": EV to a tenth, with a true minus sign.
    static func evLabel(_ ev: Double) -> String {
        guard ev.isFinite else { return "—" }
        let rounded = (ev * 10).rounded() / 10
        if rounded == 0 { return "0" }
        let text = ExposureScale.decimal(abs(rounded), places: 1)
        return rounded < 0 ? "−" + text : text
    }
}
