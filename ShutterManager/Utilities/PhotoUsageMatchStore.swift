//
//  PhotoUsageMatchStore.swift
//  ShutterManager
//
//  The matches the user chose in Usage from Photos, remembered on this device.
//

import Foundation

/// Remembers which item the user said a body or lens named in photos is, so the next batch
/// matches it without asking. Cameras name themselves in their own way ("ILCE-7M4" for an
/// α7 IV), and many lenses give no serial number, so a name the matcher can't place stays that
/// way until the user places it once.
struct PhotoUsageMatchStore {
    var defaults: UserDefaults = .standard

    private var key: String { Constants.UserDefaultsKeys.photoUsageMatches }

    /// Group key to item ID.
    func load() -> [String: UUID] {
        let stored = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return stored.compactMapValues(UUID.init(uuidString:))
    }

    /// Remembers `itemID` for the group, or forgets the group when it's nil.
    func remember(_ itemID: UUID?, for groupKey: String) {
        var stored = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        stored[groupKey] = itemID?.uuidString
        // Old matches go first only in the sense that any may: the list has no order, and one
        // dropped match costs a single tap the next time that gear turns up.
        while stored.count > Constants.PhotoUsage.maximumRememberedMatches,
              let extra = stored.keys.first(where: { $0 != groupKey }) {
            stored[extra] = nil
        }
        defaults.set(stored, forKey: key)
    }
}
