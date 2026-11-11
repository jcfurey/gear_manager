//
//  LabelLink.swift
//  ShutterManager
//
//  What a QR label points at. Foundation-only.
//

import Foundation

/// What a QR label points at: a kit or a piece of gear in the owner's library.
///
/// The code on a label holds only this, as a link such as `shuttermanager://kit/<ID>`. The ID
/// means nothing outside the library it came from, so a label gives away nothing about its owner
/// or what's in the bag. The Camera app opens the link in Shutter Manager; so does the scanner in
/// the app.
enum LabelLink: Hashable, Identifiable, Sendable {
    case kit(UUID)
    case gear(UUID)

    /// The app's URL scheme, registered in Info.plist.
    static let scheme = "shuttermanager"

    var id: String { text }

    /// The record's ID.
    var recordID: UUID {
        switch self {
        case .kit(let id), .gear(let id): return id
        }
    }

    private var kind: String {
        switch self {
        case .kit: return "kit"
        case .gear: return "gear"
        }
    }

    /// The link as the label's code carries it.
    var text: String { "\(Self.scheme)://\(kind)/\(recordID.uuidString)" }

    var url: URL? { URL(string: text) }

    /// The link in a scanned code or an opened URL; nil when it isn't one of this app's labels.
    /// Schemes and hosts aren't case-sensitive, so neither is this.
    init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == Self.scheme,
              let kind = components.host?.lowercased(),
              let id = UUID(uuidString: components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            return nil
        }
        switch kind {
        case "kit": self = .kit(id)
        case "gear": self = .gear(id)
        default: return nil
        }
    }

    init?(url: URL) {
        self.init(text: url.absoluteString)
    }
}
