//
//  MarketplaceSearch.swift
//  ShutterManager
//
//  Deep-links a *search* for a piece of gear into camera retailers and marketplaces. No API
//  access, no keys, no backend: the app builds a search URL and opens it in the browser, which
//  keeps the "no backend / Data Not Collected" posture, and physical-goods links may leave the
//  app. The app isn't affiliated with any of these sites.
//
//  Search formats:
//   - eBay:   www.ebay.com/sch/i.html?_nkw=…   (verified June 2026)
//   - Google: www.google.com/search?q=…
//   - MPB, KEH, B&H and Adorama: a Google search limited to the site (`site:mpb.com …`). Their
//     own search pages either render the query client-side or block automated checks, so their
//     query parameters couldn't be verified (October 2026). A site-restricted search always
//     works; switch a site to its own search URL once that's been confirmed on a device.
//

import Foundation

/// A retailer or marketplace the app can open a search in.
enum Marketplace: String, CaseIterable, Identifiable {
    case mpb
    case keh
    case ebay
    case bhPhoto
    case adorama
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mpb: return "MPB"
        case .keh: return "KEH"
        case .ebay: return "eBay"
        case .bhPhoto: return "B&H"
        case .adorama: return "Adorama"
        case .google: return "Google"
        }
    }

    /// SF Symbol for the row.
    var systemImage: String {
        switch self {
        case .mpb, .keh: return "arrow.triangle.2.circlepath.camera"
        case .ebay: return "tag"
        case .bhPhoto, .adorama: return "building.2"
        case .google: return "magnifyingglass"
        }
    }

    /// The site a site-restricted search is limited to, for retailers searched through Google.
    private var siteDomain: String? {
        switch self {
        case .mpb: return "mpb.com"
        case .keh: return "keh.com"
        case .bhPhoto: return "bhphotovideo.com"
        case .adorama: return "adorama.com"
        case .ebay, .google: return nil
        }
    }

    /// A search URL for `query`, or nil for an empty query. `URLComponents` percent-encodes the
    /// value, so spaces and punctuation in a make or model are handled safely.
    func searchURL(query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        switch self {
        case .ebay:
            components.host = "www.ebay.com"
            components.path = "/sch/i.html"
            components.queryItems = [URLQueryItem(name: "_nkw", value: trimmed)]
        default:
            components.host = "www.google.com"
            components.path = "/search"
            let search = siteDomain.map { "site:\($0) \(trimmed)" } ?? trimmed
            components.queryItems = [URLQueryItem(name: "q", value: search)]
        }
        return components.url
    }
}
