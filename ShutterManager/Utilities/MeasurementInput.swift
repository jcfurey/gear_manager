import Foundation

/// Use the same locale for editable measurement text and its parser. Never group digits:
/// a period used as grouping in one locale is a decimal separator in another.
enum MeasurementInput {
    static func text(_ value: Double, fractionDigits: Int? = nil, locale: Locale = .current) -> String {
        let precision: NumberFormatStyleConfiguration.Precision = fractionDigits.map {
            .fractionLength($0)
        } ?? .fractionLength(0...15)
        return value.formatted(.number.grouping(.never).precision(precision).locale(locale))
    }
}

/// Read-only text for computed measurements (tension, scale length, frequency, density): the
/// user's locale decimal separator at a fixed precision, so a German user sees "16,26 lb" where
/// `String(format: "%.2f")` always printed "16.26". Display only — editable fields are written
/// with `MeasurementInput.text` and read back with `Double(localizedInput:)`; this output may
/// carry digit grouping and is not meant to be parsed.
enum MeasurementDisplay {
    static func text(_ value: Double, fractionDigits: Int, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }
}
