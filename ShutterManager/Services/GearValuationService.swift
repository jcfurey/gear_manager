//
//  GearValuationService.swift
//  ShutterManager
//
//  Collection value from the user's own figures.
//

import Foundation

/// Collection value summary derived entirely from the user's own figures: no estimate, no
/// market data. An item's value is its current value if the user entered one, else its purchase
/// price (`GearItem.effectiveValue`). Items with neither are left out of the total and counted
/// via `itemsWithValue`, so the UI can be honest about coverage.
enum GearValuationService {
    static func collectionValue(of gearItems: [GearItem]) -> CollectionValuation {
        var totalValue: Decimal = 0
        var totalPurchasePrice: Decimal = 0
        var itemsWithValue = 0
        for item in gearItems {
            if let value = item.effectiveValue {
                totalValue += value
                itemsWithValue += 1
            }
            if let purchasePrice = item.purchasePrice {
                totalPurchasePrice += purchasePrice
            }
        }
        return CollectionValuation(totalItems: gearItems.count, itemsWithValue: itemsWithValue,
                                   totalPurchasePrice: totalPurchasePrice, totalValue: totalValue)
    }
}

/// Collection-wide value summary, derived entirely from user-entered figures.
struct CollectionValuation: Equatable {
    let totalItems: Int
    /// How many items have a current value or a purchase price.
    let itemsWithValue: Int
    let totalPurchasePrice: Decimal
    let totalValue: Decimal

    var formattedTotalValue: String { CurrencyFormatter.format(totalValue) }
    var formattedTotalPurchasePrice: String { CurrencyFormatter.format(totalPurchasePrice) }

    /// True when at least one item has a value to total.
    var hasValues: Bool { itemsWithValue > 0 }
}
