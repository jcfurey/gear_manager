//
//  NumberFields.swift
//  ShutterManager
//
//  Form fields for measurements, counts and money where "not set" is a real state.
//

import SwiftUI

/// A labeled number field for a measurement stored with `0` meaning "not set".
///
/// Shows an empty field for 0, reads the locale's decimal separator (`Double(localizedInput:)`),
/// and writes 0 back when cleared. Text that doesn't parse, or is negative or past `maximum`,
/// shows in red and isn't written; leaving the field puts back the last valid value.
struct MeasurementField: View {
    let title: String
    @Binding var value: Double
    var unit: String? = nil
    var allowsDecimals = true
    var maximum: Double = Constants.DataLimits.maximumMeasurement

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField(title, text: $text)
                .keyboardType(allowsDecimals ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(parsed(text) == nil ? Color.red : Color.primary)
                .focused($isFocused)
                .accessibilityLabel(title)
            if let unit {
                Text(unit).foregroundStyle(.secondary)
            }
        }
        .onAppear { text = Self.text(for: value, allowsDecimals: allowsDecimals) }
        .onChange(of: text) { _, newText in
            if let number = parsed(newText) { value = number }
        }
        .onChange(of: value) { _, newValue in
            // A value set from outside (filled from a photo, say) replaces the text, unless the
            // user is typing it.
            if !isFocused, parsed(text) != newValue {
                text = Self.text(for: newValue, allowsDecimals: allowsDecimals)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { text = Self.text(for: value, allowsDecimals: allowsDecimals) }
        }
    }

    /// The value `text` stands for: 0 for empty, nil when it isn't a valid entry.
    private func parsed(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        guard let number = Double(localizedInput: trimmed), number >= 0, number <= maximum else { return nil }
        if !allowsDecimals, number != number.rounded() { return nil }
        return number
    }

    static func text(for value: Double, allowsDecimals: Bool = true) -> String {
        guard value > 0, value.isFinite else { return "" }
        return MeasurementInput.text(value, fractionDigits: allowsDecimals ? nil : 0)
    }
}

/// A whole-number field over an `Int` (0 = not set), built on `MeasurementField`.
struct CountField: View {
    let title: String
    @Binding var value: Int
    var unit: String? = nil
    var maximum: Double = Constants.DataLimits.maximumCount

    var body: some View {
        MeasurementField(title: title, value: Binding(
            get: { Double(value) },
            set: { value = Int(min(max($0, 0), maximum).rounded()) }
        ), unit: unit, allowsDecimals: false, maximum: maximum)
    }
}

/// A labeled amount in the app currency, stored as `Decimal?` (nil or 0 = not set).
///
/// Parses with `Decimal(localizedInput:)`, so the locale's separator works and a value is never
/// routed through `Double`. Invalid text shows in red and isn't written; leaving the field puts
/// back the last valid amount.
struct MoneyField: View {
    let title: String
    @Binding var value: Decimal?

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField(CurrencyFormatter.currencyCode, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isValid(text) ? Color.primary : Color.red)
                .focused($isFocused)
                .accessibilityLabel(title)
        }
        .onAppear { text = Self.text(for: value) }
        .onChange(of: text) { _, newText in
            guard isValid(newText) else { return }
            let amount = Decimal(localizedInput: newText.trimmingCharacters(in: .whitespaces))
            value = (amount == nil || amount == 0) ? nil : amount
        }
        .onChange(of: value) { _, newValue in
            if !isFocused { text = Self.text(for: newValue) }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { text = Self.text(for: value) }
        }
    }

    private func isValid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        guard let amount = Decimal(localizedInput: trimmed) else { return false }
        return amount >= 0 && amount <= Decimal(Constants.DataLimits.maximumMoney)
    }

    /// Plain, ungrouped text in the locale's format, so it parses back exactly.
    static func text(for value: Decimal?) -> String {
        guard let value, value != 0 else { return "" }
        return value.formatted(.number.grouping(.never))
    }
}
