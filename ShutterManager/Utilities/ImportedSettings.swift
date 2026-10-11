//
//  ImportedSettings.swift
//  ShutterManager
//
//  Validation for settings coming from an export or backup file.
//

import Foundation

/// Applies a settings dictionary read from an export or backup file to `UserDefaults`.
///
/// Import and restore both read untrusted files (hand-editable, moved between devices,
/// corruptible), so both go through these rules. Every key has a typed rule; an invalid value
/// is skipped and the current setting stays. Values are stored the way the app reads them.
enum ImportedSettings {
    private typealias K = Constants.UserDefaultsKeys

    /// Settings keys a file is allowed to write, so a crafted file can't overwrite arbitrary
    /// UserDefaults keys.
    private static let importableKeys = Set(K.exportableSettings)

    /// How one key's string value is checked and stored.
    private enum Rule {
        /// "true"/"false" (any case) or "1"/"0". Stored as `Bool`.
        case bool
        /// One of a fixed set of raw values, stored as `String`.
        case choice(Set<String>)
    }

    private static let rules: [String: Rule] = [
        K.hapticFeedback: .bool,
        K.darkModePreference: .choice(["system", "light", "dark"])
    ]

    /// Keys with a validation rule. Every `exportableSettings` key needs one to be importable.
    static var validatedKeys: Set<String> { Set(rules.keys) }

    /// Writes the allow-listed, validated subset of `settings` into `defaults`.
    /// - Returns: The keys that were written.
    @discardableResult
    static func apply(_ settings: [String: String], to defaults: UserDefaults) -> Set<String> {
        var written: Set<String> = []
        for (key, value) in settings {
            guard importableKeys.contains(key), let rule = rules[key] else { continue }
            switch rule {
            case .bool:
                switch value.lowercased() {
                case "true", "1": defaults.set(true, forKey: key)
                case "false", "0": defaults.set(false, forKey: key)
                default: continue
                }
            case .choice(let options):
                guard options.contains(value) else { continue }
                defaults.set(value, forKey: key)
            }
            written.insert(key)
        }
        return written
    }
}
