//
//  SafeConversion.swift
//  ShutterManager
//
//  Turning a calculator's Double into an Int without trapping. Foundation-only.
//

import Foundation

extension Int {
    /// `value` as an Int, cut off at what an Int can hold; 0 for NaN.
    ///
    /// `Int(_:)` traps on a Double it can't hold, and the calculators reach such numbers from
    /// ordinary input: four stacked 20-stop ND filters multiply an exposure past 2⁶³ seconds,
    /// and a time-lapse interval of zero divides to infinity.
    init(saturating value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= 9_223_372_036_854_775_808.0 {
            self = .max
        } else if value <= -9_223_372_036_854_775_808.0 {
            self = .min
        } else {
            self = Int(value)
        }
    }
}
