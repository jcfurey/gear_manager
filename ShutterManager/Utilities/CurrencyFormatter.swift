//
//  CurrencyFormatter.swift
//  ShutterManager
//
//  Single source of truth for currency display. Currency is stored as Decimal end-to-end;
//  these methods format it via cached, locale-aware NumberFormatters. nil amounts
//  return "Not specified" (or nil for the optional variant); a real zero formats as
//  a normal amount (e.g. "$0").
//
//  Every amount in the app — gear values, maintenance costs, price entries, alert targets and
//  suggestions, alert notifications — is typed into the same unlabeled fields, so all of them
//  are shown in the one app currency (the user's locale currency, `currencyCode`). There is
//  deliberately no USD-pinned variant any more: maintenance and price-tracking amounts used to
//  be formatted as USD while gear values used the locale currency, so a de_DE user saw "1.200 €"
//  for a gear value and "1.200,00 $" for a price entry typed the same way.
//

import Foundation

/// Currency formatting helpers backed by cached, locale-aware NumberFormatters.
enum CurrencyFormatter {

    /// Cached formatter for whole number currency display (no decimal places)
    /// Optimized for gear prices and market values where cents are not significant
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 0  // No cents for cleaner display
        return formatter
    }()

    /// Cached formatter for precise currency display with decimal places
    /// Used for detailed financial calculations requiring cent-level precision
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 2  // Standard currency precision
        return formatter
    }()

    /// ISO 4217 code of the app currency every amount is shown in (the locale's currency).
    /// For SwiftUI `.currency(code:)` fields and for tagging stored amounts.
    static var currencyCode: String {
        formatter.currencyCode ?? "USD"
    }

    // MARK: - Formatting (currency is stored as Decimal end-to-end)

    /// Formats a Decimal as currency without decimal places.
    static func format(_ value: Decimal?) -> String {
        guard let value = value else { return "Not specified" }
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? fallback(value)
    }

    /// Formats a Decimal as currency with decimal places.
    static func formatWithDecimals(_ value: Decimal?) -> String {
        guard let value = value else { return "Not specified" }
        return decimalFormatter.string(from: NSDecimalNumber(decimal: value)) ?? fallback(value)
    }

    /// Formats optional Decimal as currency, returning nil for a nil amount.
    static func formatOptional(_ value: Decimal?) -> String? {
        guard let value = value else { return nil }
        return formatter.string(from: NSDecimalNumber(decimal: value))
    }

    /// Last resort if a formatter ever declines a value: the app currency's symbol, not "$".
    private static func fallback(_ value: Decimal) -> String {
        "\(formatter.currencySymbol ?? "")\(value)"
    }
}
