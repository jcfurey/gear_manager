//
//  ExposureScale.swift
//  ShutterManager
//
//  The standard aperture, shutter-speed and ISO scales, and labels in camera notation.
//  Foundation-only. Sources: docs/PHOTO_MATH_REFERENCES.md § Exposure.
//

import Foundation

/// The step size a scale moves in.
enum StopIncrement: String, CaseIterable, Identifiable {
    case full, half, third

    var id: String { rawValue }

    /// Steps per stop.
    var stepsPerStop: Int {
        switch self {
        case .full: return 1
        case .half: return 2
        case .third: return 3
        }
    }

    var displayName: String {
        switch self {
        case .full: return "Full stops"
        case .half: return "Half stops"
        case .third: return "Third stops"
        }
    }
}

/// One value on a standard scale: its exact value and the label a camera marks it with.
///
/// Calculations use `value`, which is exact (f/5.6 is 2^2.5 ≈ 5.657, 1/250 is 2^−8 = 1/256), so
/// moving along a scale changes exposure by exactly the steps moved. `label` is the rounded
/// number cameras print.
struct ScaleValue: Hashable, Identifiable {
    /// Position in third stops from the scale's origin (f/1, 1 s, ISO 100).
    let thirds: Int
    let value: Double
    let label: String

    var id: Int { thirds }
}

enum ExposureScale {
    // MARK: - Apertures

    /// Marked f-numbers in third stops from f/1 (index 0) to f/64 (index 36).
    private static let apertureLabels = [
        "1", "1.1", "1.2", "1.4", "1.6", "1.8", "2", "2.2", "2.5", "2.8", "3.2", "3.5", "4", "4.5",
        "5", "5.6", "6.3", "7.1", "8", "9", "10", "11", "13", "14", "16", "18", "20", "22", "25",
        "29", "32", "36", "40", "45", "51", "57", "64"
    ]

    /// f/1 to f/64 in the given increment. A half-stop scale uses the camera half-stop marks.
    static func apertures(_ increment: StopIncrement = .third) -> [ScaleValue] {
        switch increment {
        case .third:
            return apertureLabels.indices.map { ScaleValue(thirds: $0, value: apertureValue(thirds: $0),
                                                           label: "f/" + apertureLabels[$0]) }
        case .full:
            return stride(from: 0, through: 36, by: 3).map {
                ScaleValue(thirds: $0, value: apertureValue(thirds: $0), label: "f/" + apertureLabels[$0])
            }
        case .half:
            // Half stops don't land on third-stop indices; label them from the camera half scale.
            let labels = ["1", "1.2", "1.4", "1.7", "2", "2.4", "2.8", "3.3", "4", "4.8", "5.6", "6.7",
                          "8", "9.5", "11", "13", "16", "19", "22", "27", "32", "38", "45", "54", "64"]
            return labels.indices.map { index in
                let stops = Double(index) / 2
                return ScaleValue(thirds: Int((stops * 3).rounded()), value: pow(2, stops / 2),
                                  label: "f/" + labels[index])
            }
        }
    }

    /// The exact f-number `thirds` third stops above f/1: N = 2^(thirds/6).
    static func apertureValue(thirds: Int) -> Double { pow(2, Double(thirds) / 6) }

    /// "f/5.6" for any f-number: the marked value when it's within a sixth of a stop of a
    /// third-stop mark, else the number to one decimal.
    static func apertureLabel(_ fNumber: Double) -> String {
        guard fNumber.isFinite, fNumber > 0 else { return "—" }
        let thirds = 6 * log2(fNumber)
        let nearest = thirds.rounded()
        if abs(thirds - nearest) <= 0.5, let index = Int(exactly: nearest), apertureLabels.indices.contains(index) {
            return "f/" + apertureLabels[index]
        }
        return "f/" + decimal(fNumber, places: 1)
    }

    // MARK: - Shutter speeds

    /// Marked shutter speeds in third stops, from 30 s (index −15) to 1/8000 (index 39).
    /// Index 0 is 1 s; each step is a third of a stop shorter.
    private static let shutterLabels: [Int: String] = {
        let long = ["30\"", "25\"", "20\"", "15\"", "13\"", "10\"", "8\"", "6\"", "5\"", "4\"",
                    "3.2\"", "2.5\"", "2\"", "1.6\"", "1.3\"", "1\"", "0.8\"", "0.6\"", "1/2", "0.4\"", "0.3\""]
        let short = ["1/4", "1/5", "1/6", "1/8", "1/10", "1/13", "1/15", "1/20", "1/25", "1/30",
                     "1/40", "1/50", "1/60", "1/80", "1/100", "1/125", "1/160", "1/200", "1/250",
                     "1/320", "1/400", "1/500", "1/640", "1/800", "1/1000", "1/1250", "1/1600",
                     "1/2000", "1/2500", "1/3200", "1/4000", "1/5000", "1/6400", "1/8000"]
        var labels: [Int: String] = [:]
        for (offset, label) in long.enumerated() { labels[offset - 15] = label }
        for (offset, label) in short.enumerated() { labels[offset + 6] = label }
        return labels
    }()

    static let shutterRange = -15...39

    /// 30 s to 1/8000 in the given increment, slowest first.
    static func shutterSpeeds(_ increment: StopIncrement = .third) -> [ScaleValue] {
        switch increment {
        case .third:
            return shutterRange.map { ScaleValue(thirds: $0, value: shutterValue(thirds: $0), label: shutterLabels[$0] ?? "") }
        case .full:
            return stride(from: -15, through: 39, by: 3).map {
                ScaleValue(thirds: $0, value: shutterValue(thirds: $0), label: shutterLabels[$0] ?? "")
            }
        case .half:
            let labels = ["30\"", "20\"", "15\"", "10\"", "8\"", "6\"", "4\"", "3\"", "2\"", "1.5\"", "1\"",
                          "0.7\"", "1/2", "0.3\"", "1/4", "1/6", "1/8", "1/10", "1/15", "1/20", "1/30",
                          "1/45", "1/60", "1/90", "1/125", "1/180", "1/250", "1/350", "1/500", "1/750",
                          "1/1000", "1/1500", "1/2000", "1/3000", "1/4000", "1/6000", "1/8000"]
            return labels.indices.map { index in
                let stops = Double(index) / 2 - 5
                return ScaleValue(thirds: Int((stops * 3).rounded()), value: pow(2, -stops), label: labels[index])
            }
        }
    }

    /// The exact time `thirds` third stops shorter than 1 s: t = 2^(−thirds/3).
    static func shutterValue(thirds: Int) -> Double { pow(2, -Double(thirds) / 3) }

    /// "1/250", "0.6\"", "2\"" for times on the scale, and "45 s", "4 min 16 s", "1 h 2 min"
    /// for longer ones.
    static func shutterLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        if seconds > 30.5 { return durationLabel(seconds) }
        let thirds = -3 * log2(seconds)
        let nearest = thirds.rounded()
        if abs(thirds - nearest) <= 0.5, let index = Int(exactly: nearest), let label = shutterLabels[index] {
            return label
        }
        // Faster than 1/8000.
        return "1/\(Int((1 / seconds).rounded()))"
    }

    /// "45 s", "4 min 16 s", "1 h 2 min": whole seconds, for timers and long exposures.
    static func durationLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 10 { return decimal(seconds, places: 1) + " s" }
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        if minutes > 0 { return secs > 0 ? "\(minutes) min \(secs) s" : "\(minutes) min" }
        return "\(secs) s"
    }

    // MARK: - ISO

    /// Marked ISO speeds in third stops from ISO 6 (index −12) to ISO 102400 (index 30).
    /// Index 0 is ISO 100.
    private static let isoLabels = [
        6, 8, 10, 12, 16, 20, 25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640,
        800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 16000, 20000,
        25600, 32000, 40000, 51200, 64000, 80000, 102400
    ]

    static let isoRange = -12...30

    static func isoSpeeds(_ increment: StopIncrement = .third) -> [ScaleValue] {
        let step = increment == .full ? 3 : 1
        // There's no half-stop ISO scale in common use; half falls back to thirds.
        return stride(from: isoRange.lowerBound, through: isoRange.upperBound, by: step).map {
            ScaleValue(thirds: $0, value: isoValue(thirds: $0), label: "ISO \(isoLabels[$0 + 12])")
        }
    }

    /// The exact speed `thirds` third stops above ISO 100: 100 · 2^(thirds/3).
    static func isoValue(thirds: Int) -> Double { 100 * pow(2, Double(thirds) / 3) }

    /// "ISO 400": the marked speed when on the scale, else the rounded number.
    static func isoLabel(_ iso: Double) -> String {
        guard iso.isFinite, iso > 0 else { return "—" }
        let thirds = 3 * log2(iso / 100)
        let nearest = thirds.rounded()
        if abs(thirds - nearest) <= 0.5, let index = Int(exactly: nearest), isoRange.contains(index) {
            return "ISO \(isoLabels[index + 12])"
        }
        return "ISO \(Int(iso.rounded()))"
    }

    // MARK: - Snapping

    /// The scale value nearest `value` in stops (log₂), or nil for an empty scale.
    static func nearest(to value: Double, in scale: [ScaleValue]) -> ScaleValue? {
        guard value.isFinite, value > 0 else { return nil }
        return scale.min { abs(log2($0.value / value)) < abs(log2($1.value / value)) }
    }

    /// `value` with up to `places` decimals, "." separator, trailing zeros dropped: camera notation.
    static func decimal(_ value: Double, places: Int) -> String {
        var text = String(format: "%.\(places)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
