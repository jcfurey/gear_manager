//
//  UPCLookupService.swift
//  ShutterManager
//

import Foundation

/// Service for looking up product information from UPC/barcode codes.
/// Uses the UPCitemdb trial API which covers electronics, musical instruments,
/// and general merchandise. Free tier: 100 lookups/day, no API key required.
/// Upgrade to a paid plan at upcitemdb.com for higher limits.
@MainActor
class UPCLookupService: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?
    
    /// One cache slot: a product, or a recorded miss.
    ///
    /// Misses are cached too. The free tier allows 100 lookups/day, and an unrecognized barcode
    /// is exactly the one a user rescans — pointing the camera at the same sticker again, or
    /// tapping the scan button after the "not found" sheet. Every one of those re-hit the API
    /// and spent quota re-learning the same answer. Only *authoritative* misses are stored: a
    /// network failure or a rate-limit response says nothing about the barcode, so those stay
    /// uncached and remain retryable.
    private enum CacheEntry {
        case found(ProductInfo)
        case notFound
    }

    /// Cache mapping barcode → lookup outcome
    private var cache: [String: CacheEntry] = [:]
    /// Insertion-ordered keys for true FIFO eviction
    private var cacheInsertionOrder: [String] = []
    /// Maximum cache entries before oldest is evicted
    private let maxCacheSize = 100

    /// Look up product information for a given barcode
    func lookupProduct(barcode: String) async -> ProductInfo? {
        // Check cache first — including remembered misses.
        switch cache[barcode] {
        case .found(let cachedProduct):
            lastError = nil
            return cachedProduct
        case .notFound:
            lastError = Self.notFoundMessage
            return nil
        case nil:
            break
        }

        isLoading = true
        lastError = nil

        defer { isLoading = false }

        let outcome = await lookupFromUPCItemDB(barcode: barcode)
        switch outcome {
        case .found(let product):
            store(.found(product), for: barcode)
            return product

        case .notFound:
            store(.notFound, for: barcode)
            lastError = Self.notFoundMessage
            return nil

        case .failed:
            // `lookupFromUPCItemDB` has already set a specific `lastError` (network, rate limit,
            // server error). Don't clobber it with the generic not-found message, and don't
            // cache — the barcode may well be valid; we simply couldn't ask.
            if lastError == nil {
                lastError = "UPC lookup failed. Try again later."
            }
            return nil
        }
    }

    private static let notFoundMessage = "Product not found in database"

    /// Outcome of one API round-trip, distinguishing "the database answered, and has no such
    /// product" from "we never got an answer". Only the former is safe to cache.
    private enum LookupOutcome {
        case found(ProductInfo)
        case notFound
        case failed
    }
    
    /// Look up product from UPCitemdb trial API.
    /// Covers electronics, musical instruments, and general retail products.
    private func lookupFromUPCItemDB(barcode: String) async -> LookupOutcome {
        // Build the URL via URLComponents so the barcode is percent-encoded as a query value
        // (a raw interpolation would produce nil/a malformed query for unexpected characters).
        var components = URLComponents(string: "https://api.upcitemdb.com/prod/trial/lookup")
        components?.queryItems = [URLQueryItem(name: "upc", value: barcode)]
        guard let url = components?.url else {
            lastError = "Couldn't build a lookup request for barcode \(barcode)."
            return .failed
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Unexpected response from the UPC lookup service."
                return .failed
            }

            guard httpResponse.statusCode == 200 else {
                // Distinguish real failures (rate limiting, server errors) from a genuine
                // "not found" so the caller isn't stuck with the generic not-found message.
                switch httpResponse.statusCode {
                case 429:
                    lastError = "Rate limit reached (HTTP 429): the free tier allows 100 lookups/day. Try again later or enter details manually."
                case 500...599:
                    lastError = "UPC lookup service error (HTTP \(httpResponse.statusCode)). Try again later."
                default:
                    lastError = "UPC lookup failed (HTTP \(httpResponse.statusCode))."
                }
                return .failed
            }

            let apiResponse = try JSONDecoder().decode(UPCItemDBResponse.self, from: data)

            // A non-"OK" code with HTTP 200 is an API-level failure (quota exhausted, malformed
            // request, service trouble), NOT a statement that the product doesn't exist. It used
            // to fall through to the generic "Product not found in database" with `lastError`
            // left nil, telling the user their barcode was unknown when the lookup never ran.
            guard apiResponse.code == "OK" else {
                lastError = "UPC lookup unavailable (\(apiResponse.code)). Try again later or enter details manually."
                return .failed
            }

            // Code "OK" with no items IS authoritative: the database answered and has no such
            // product. Safe to remember.
            guard let item = apiResponse.items?.first else {
                return .notFound
            }

            return .found(ProductInfo(
                name: item.title ?? "Unknown Product",
                brand: item.brand,
                description: item.description,
                imageURL: item.images?.first,
                category: item.category,
                barcode: barcode,
                source: .upcItemDB
            ))

        } catch {
            lastError = "Network error: \(error.localizedDescription)"
            return .failed
        }
    }
    
    /// Record a lookup outcome with true FIFO eviction.
    private func store(_ entry: CacheEntry, for barcode: String) {
        guard cache[barcode] == nil else { return } // already cached
        if cache.count >= maxCacheSize, let oldest = cacheInsertionOrder.first {
            cache.removeValue(forKey: oldest)
            cacheInsertionOrder.removeFirst()
        }
        cache[barcode] = entry
        cacheInsertionOrder.append(barcode)
    }
    
    /// Clear the entire cache
    func clearCache() {
        cache.removeAll()
        cacheInsertionOrder.removeAll()
    }
}

// MARK: - Data Models

/// Product information from UPC lookup
struct ProductInfo {
    let name: String
    let brand: String?
    let description: String?
    let imageURL: String?
    let category: String?
    let barcode: String
    let source: ProductSource
    
    /// Display-friendly brand name
    var displayBrand: String? {
        guard let brand = brand, !brand.isEmpty else { return nil }
        return brand
    }
    
    /// Display-friendly description
    var displayDescription: String? {
        guard let description = description, !description.isEmpty else { return nil }
        return description
    }
}

/// Source of product information
enum ProductSource {
    case upcItemDB
    case manual
    
    var displayName: String {
        switch self {
        case .upcItemDB:
            return "UPCitemdb"
        case .manual:
            return "Manual Entry"
        }
    }
}

// MARK: - API Response Models

/// UPCitemdb API response structure
private struct UPCItemDBResponse: Codable {
    let code: String
    let total: Int?
    let items: [UPCItemDBProduct]?
}

/// UPCitemdb product data
private struct UPCItemDBProduct: Codable {
    let ean: String?
    let title: String?
    let description: String?
    let brand: String?
    let model: String?
    let color: String?
    let category: String?
    let images: [String]?
}
