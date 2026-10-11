//
//  Reciprocity.swift
//  ShutterManager
//
//  Long-exposure correction for film (reciprocity failure). Each stock's data comes from its
//  maker's datasheet (FilmStock). Foundation-only. Sources: docs/PHOTO_MATH_REFERENCES.md
//  § Reciprocity.
//

import Foundation

/// How a film's maker says to correct long exposures.
enum ReciprocityModel: Hashable, Sendable {
    /// Ilford's form: corrected time Tc = Tm^p for metered times Tm longer than `from` seconds.
    case powerLaw(exponent: Double, from: Double)
    /// A maker's table of metered time → corrected time. Between points, and from `uncorrectedUpTo`
    /// to the first point, the correction is interpolated on log–log axes. From
    /// `notRecommendedFrom` on, the maker advises against the exposure.
    case table(uncorrectedUpTo: Double, points: [ReciprocityPoint], notRecommendedFrom: Double? = nil)
    /// The maker says no correction is needed up to `seconds` and gives no figures beyond.
    case noCorrectionUpTo(seconds: Double)
    /// The maker publishes no long-exposure guidance.
    case unpublished
}

/// One row of a maker's table: meter this, expose that.
struct ReciprocityPoint: Hashable, Sendable {
    let metered: Double
    let corrected: Double

    init(metered: Double, corrected: Double) {
        self.metered = metered
        self.corrected = corrected
    }

    /// A row given as extra stops ("+1/3 stop"): the equivalent time, metered × 2^stops. Makers
    /// who give the correction as opening the aperture (Kodak's "change aperture" rows, Fujifilm)
    /// are shown as the time that matches it.
    init(metered: Double, extraStops: Double) {
        self.init(metered: metered, corrected: metered * pow(2, extraStops))
    }

    /// A row given as a multiplier on the metered time ("lengthen 8×", Foma).
    init(metered: Double, multiplier: Double) {
        self.init(metered: metered, corrected: metered * multiplier)
    }
}

/// A corrected exposure and how far to trust it.
struct ReciprocityResult: Equatable {
    enum Basis: Equatable {
        /// No correction needed at this time.
        case noCorrection
        /// Within the maker's formula range or between the table's rows.
        case makerData
        /// Beyond the maker's last row or stated range: an estimate that continues the trend.
        case extrapolated
        /// The maker gives no figures for this time; the metered time is shown unchanged.
        case noData
        /// The maker advises against an exposure this long. The time continues the table's trend.
        case notRecommended
    }

    let metered: Double
    let corrected: Double
    let basis: Basis

    /// Extra stops the correction adds: log₂(corrected ÷ metered).
    var extraStops: Double { log2(corrected / metered) }
}

extension ReciprocityModel {
    func correct(metered seconds: Double) -> ReciprocityResult? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        switch self {
        case let .powerLaw(exponent, from):
            // Below one second Tm^p would be shorter than Tm, so the law only ever lengthens.
            guard seconds > max(from, 1) else {
                return ReciprocityResult(metered: seconds, corrected: seconds, basis: .noCorrection)
            }
            return ReciprocityResult(metered: seconds, corrected: pow(seconds, exponent), basis: .makerData)

        case let .table(uncorrectedUpTo, points, notRecommendedFrom):
            guard seconds > uncorrectedUpTo, let first = points.first, let last = points.last else {
                return ReciprocityResult(metered: seconds, corrected: seconds, basis: .noCorrection)
            }
            if let limit = notRecommendedFrom, seconds >= limit {
                let curve = [ReciprocityPoint(metered: uncorrectedUpTo, corrected: uncorrectedUpTo)] + points
                let estimate = Self.logLogInterpolate(seconds, curve[curve.count - 2], last)
                return ReciprocityResult(metered: seconds, corrected: max(estimate, seconds), basis: .notRecommended)
            }
            // The curve starts from "no correction" at the threshold.
            let curve = [ReciprocityPoint(metered: uncorrectedUpTo, corrected: uncorrectedUpTo)] + points
            if seconds <= last.metered {
                guard let upper = curve.firstIndex(where: { $0.metered >= seconds }), upper > 0 else {
                    return ReciprocityResult(metered: seconds, corrected: first.corrected, basis: .makerData)
                }
                // On a row, the maker's own figure, not one rounded through logarithms.
                if curve[upper].metered == seconds {
                    return ReciprocityResult(metered: seconds, corrected: curve[upper].corrected, basis: .makerData)
                }
                let corrected = Self.logLogInterpolate(seconds, curve[upper - 1], curve[upper])
                return ReciprocityResult(metered: seconds, corrected: corrected, basis: .makerData)
            }
            let previous = curve[curve.count - 2]
            return ReciprocityResult(metered: seconds, corrected: Self.logLogInterpolate(seconds, previous, last),
                                     basis: .extrapolated)

        case let .noCorrectionUpTo(limit):
            return ReciprocityResult(metered: seconds, corrected: seconds,
                                     basis: seconds <= limit ? .noCorrection : .noData)

        case .unpublished:
            return ReciprocityResult(metered: seconds, corrected: seconds, basis: .noData)
        }
    }

    /// The straight line through two points on log–log axes, evaluated at `x`.
    private static func logLogInterpolate(_ x: Double, _ a: ReciprocityPoint, _ b: ReciprocityPoint) -> Double {
        let x0 = log(a.metered), x1 = log(b.metered)
        let y0 = log(a.corrected), y1 = log(b.corrected)
        guard x1 != x0 else { return b.corrected }
        let slope = (y1 - y0) / (x1 - x0)
        return exp(y0 + slope * (log(x) - x0))
    }
}
