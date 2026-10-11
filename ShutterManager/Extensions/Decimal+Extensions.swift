//
//  Decimal+Extensions.swift
//  ShutterManager
//
//  Currency math in this app is stored as Decimal but most chart/analytics math
//  needs Double. These helpers keep the conversion in one place.
//

import Foundation

extension Decimal {
    /// Lossy conversion to Double for chart math, ratios, and other analytics
    /// where Decimal precision isn't required.
    var doubleValue: Double {
        return NSDecimalNumber(decimal: self).doubleValue
    }

    /// Build a Decimal from a Double without binary-float artifacts. `Decimal(1099.99)`
    /// yields 1099.9899999…; routing through the Double's shortest round-trippable string
    /// (`Decimal(string:)`) preserves the intended currency value. Used when decoding the
    /// Double-shaped export/backup JSON back into the Decimal-stored model.
    init(roundTripping double: Double) {
        self = Decimal(string: String(double)) ?? Decimal(double)
    }

    /// Parse a user-entered amount using a locale's decimal separator.
    ///
    /// `Decimal(string:)` is locale-independent (always expects `.`), but the
    /// `.decimalPad` keyboard shows the *locale's* separator — so comma-decimal
    /// locales would otherwise truncate or drop the entry. Precision-preserving
    /// (no Double round-trip). Returns nil for empty or unparseable input.
    ///
    /// The whole string must be a number (see `LocalizedNumberText`). This used to go through
    /// `NSDecimalNumber(string:locale:)`, which parses the longest numeric *prefix* and silently
    /// drops the rest: a US user typing "1,299.99" on an iPad/Mac keyboard (or pasting it) saved
    /// a purchase price of **$1**, and a German "0.07" saved 0 — both passing the callers'
    /// `>= 0` checks as valid amounts.
    ///
    /// - Parameter locale: Defaults to `.current` (what every call site wants); taking it as a
    ///   parameter lets the comma-decimal behaviour this exists for be tested directly.
    init?(localizedInput string: String, locale: Locale = .current) {
        guard let canonical = LocalizedNumberText.canonical(string, locale: locale),
              let value = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        self = value
    }
}

/// Canonicalizes number text typed (or pasted) for a locale into plain `[-]digits[.digits]`,
/// or returns nil when the text is not *entirely* one unambiguous number.
///
/// Shared by `Decimal(localizedInput:)` and `Double(localizedInput:)` so currency and
/// measurement fields accept exactly the same input:
/// - native digits (Arabic-Indic, Devanagari, …) are mapped to ASCII;
/// - the locale's decimal separator is the only accepted decimal point;
/// - the locale's grouping separator is accepted only in well-formed groups (a leading group of
///   1–3 digits, a final group of 3, and 2- or 3-digit groups between — which also covers Indian
///   lakh grouping). A misplaced one is rejected rather than guessed at: "12,5" in en_US or
///   "25.5" in de_DE is either a decimal typed with the other convention or a typo, and silently
///   reading it as 12 / 125 / 255 is worse than asking the user to fix the field.
private enum LocalizedNumberText {
    static func canonical(_ string: String, locale: Locale) -> String? {
        // Invisible bidi marks can come along with pasted right-to-left numbers.
        let bidiMarks: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{061C}"]
        var text = ""
        for scalar in string.trimmingCharacters(in: .whitespaces).unicodeScalars where !bidiMarks.contains(scalar) {
            if scalar.properties.numericType == .decimal,
               let value = scalar.properties.numericValue, value >= 0, value <= 9 {
                text += String(Int(value))
            } else {
                text.unicodeScalars.append(scalar)
            }
        }

        let decimalSeparator = locale.decimalSeparator ?? "."
        var grouping = locale.groupingSeparator ?? ""
        if grouping == decimalSeparator { grouping = "" }
        if !grouping.isEmpty, grouping.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) {
            // fr_FR and friends group with a (narrow) no-break space; a typed space means the same.
            for space in [" ", "\u{00A0}", "\u{202F}"] where space != grouping {
                text = text.replacingOccurrences(of: space, with: grouping)
            }
        } else if grouping == "\u{2019}" {
            // de_CH groups with a typographic apostrophe; keyboards type the ASCII one.
            text = text.replacingOccurrences(of: "'", with: grouping)
        }

        var sign = ""
        if let first = text.first, first == "-" || first == "+" || first == "\u{2212}" {
            if first != "+" { sign = "-" }
            text.removeFirst()
        }

        let parts = text.components(separatedBy: decimalSeparator)
        guard parts.count <= 2 else { return nil }
        var integer = parts[0]
        let fraction = parts.count == 2 ? parts[1] : ""

        if !grouping.isEmpty, integer.contains(grouping) {
            let groups = integer.components(separatedBy: grouping)
            guard let leading = groups.first, (1...3).contains(leading.count),
                  let trailing = groups.last, trailing.count == 3,
                  groups.dropFirst().dropLast().allSatisfy({ $0.count == 2 || $0.count == 3 }) else {
                return nil
            }
            integer = groups.joined()
        }

        func isDigits(_ value: String) -> Bool { value.allSatisfy { $0.isASCII && $0.isNumber } }
        guard !(integer.isEmpty && fraction.isEmpty), isDigits(integer), isDigits(fraction) else { return nil }
        return sign + (integer.isEmpty ? "0" : integer) + (fraction.isEmpty ? "" : "." + fraction)
    }
}

extension Optional where Wrapped == Decimal {
    /// Convenience for `value?.doubleValue ?? 0` in ROI/percent math.
    var doubleValueOrZero: Double {
        return self?.doubleValue ?? 0
    }
}

extension Double {
    /// Parse a user-entered measurement using a locale's decimal separator.
    ///
    /// The `Double(String)` initializer is locale-independent (always expects `.`), but the
    /// `.decimalPad` keyboard shows the *locale's* separator — so in a comma-decimal locale
    /// "25,5" parses as nil. For the tension calculator that mattered more than it does for a
    /// currency field: several call sites coalesced the nil to a default scale length, so a
    /// comma-typed value was silently replaced by 25.5" and the screen reported a confident,
    /// wrong tension (tension goes as scale length squared). Returns nil for empty or
    /// unparseable input so callers can say so instead of guessing.
    ///
    /// This is the `Double` counterpart of `Decimal(localizedInput:locale:)`, which fixed the
    /// same class of bug on the currency fields. Both share `LocalizedNumberText`: grouping
    /// separators used to be stripped wherever they appeared, so a German "25.5" (a dot typed on
    /// an iPad/Mac keyboard) read as a 255" scale length and an en_US "12,5" as 125.
    ///
    /// - Parameter locale: Defaults to `.current` (what every call site wants); taking it as a
    ///   parameter lets the comma-decimal behaviour this exists for be tested directly.
    init?(localizedInput string: String, locale: Locale = .current) {
        // Canonicalize the separators, then let Swift's own (correctly rounded) Double parser do
        // the conversion. Going through NSDecimalNumber instead would land up to an ulp off — its
        // `doubleValue` isn't always correctly rounded, so "64,77" came back as 64.77000000000001.
        // Immaterial for a measurement, but there's no reason to accept it when the separator is
        // the only thing that's actually locale-dependent.
        guard let canonical = LocalizedNumberText.canonical(string, locale: locale),
              let value = Double(canonical), value.isFinite else { return nil }
        self = value
    }
}
