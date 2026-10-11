//
//  LensMount.swift
//  ShutterManager
//
//  Common lens mounts, offered as suggestions.
//

import Foundation

/// Lens mounts. `GearItem.mount` stores the mount's name as text: these are suggestions, and
/// any other name can be typed. The names are stored, so **never rename one**; matching (a
/// lens to a body) compares names without regard to case or surrounding spaces.
enum LensMount {
    struct MountGroup: Identifiable {
        let title: String
        let mounts: [String]
        var id: String { title }
    }

    /// Suggested mounts, grouped for the picker.
    static let groups: [MountGroup] = [
        MountGroup(title: "Mirrorless", mounts: [
            "Canon RF", "Canon EF-M", "Nikon Z", "Sony E", "Fujifilm X", "Fujifilm G",
            "L-Mount", "Micro Four Thirds", "Hasselblad XCD", "Nikon 1", "Samsung NX"
        ]),
        MountGroup(title: "SLR", mounts: [
            "Canon EF", "Canon EF-S", "Nikon F", "Sony A", "Pentax K", "Four Thirds", "Sigma SA",
            "Pentax 645", "Pentax 67", "Hasselblad H"
        ]),
        MountGroup(title: "Classic and film", mounts: [
            "Leica M", "Leica R", "Canon FD", "Minolta MD", "Olympus OM", "Contax/Yashica",
            "M42", "M39", "Hasselblad V", "Mamiya 645", "Mamiya RB67", "Mamiya RZ67"
        ]),
        MountGroup(title: "Other", mounts: ["Fixed lens"])
    ]

    static var all: [String] { groups.flatMap(\.mounts) }

    /// Whether two stored mount names refer to the same mount.
    static func matches(_ first: String, _ second: String) -> Bool {
        let a = normalized(first), b = normalized(second)
        return !a.isEmpty && a == b
    }

    static func normalized(_ mount: String) -> String {
        mount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
