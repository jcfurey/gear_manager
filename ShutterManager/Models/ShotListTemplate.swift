//
//  ShotListTemplate.swift
//  ShutterManager
//
//  Shot-list templates: built-in starters and the ones you save.
//

import Foundation
import SwiftData

/// A saved shot list to start shoots from. Applying a template copies its items into the shoot.
@Model
final class ShotListTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var dateCreated: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ShotListTemplateItem.template)
    var items: [ShotListTemplateItem]? = []

    init(name: String = "", notes: String = "") {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.dateCreated = Date()
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil ?? "Untitled Template"
    }

    var orderedItems: [ShotListTemplateItem] {
        (items ?? []).sorted { ($0.order, $0.title) < ($1.order, $1.title) }
    }

    /// The items as plain values, for applying to a shoot.
    var entries: [ShotListEntry] { orderedItems.map { ShotListEntry(title: $0.title, notes: $0.notes) } }
}

/// One shot in a saved template.
@Model
final class ShotListTemplateItem {
    var id: UUID = UUID()
    var template: ShotListTemplate?
    var title: String = ""
    var notes: String = ""
    var order: Int = 0

    init(template: ShotListTemplate? = nil, title: String = "", notes: String = "", order: Int = 0) {
        self.id = UUID()
        self.template = template
        self.title = title
        self.notes = notes
        self.order = order
    }
}

/// A shot as a template lists it, before it's copied into a shoot.
struct ShotListEntry: Hashable, Sendable {
    var title: String
    var notes: String = ""
}

/// The built-in starting lists. They're values in the app, not stored, so they can improve in an
/// update without touching anyone's data.
enum ShotListStarter: String, CaseIterable, Identifiable, Sendable {
    case wedding, engagement, portraitSession, event, realEstate, product

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wedding: return "Wedding"
        case .engagement: return "Engagement"
        case .portraitSession: return "Portrait session"
        case .event: return "Event"
        case .realEstate: return "Real estate"
        case .product: return "Product"
        }
    }

    var systemImage: String {
        switch self {
        case .wedding: return "heart"
        case .engagement: return "sparkles"
        case .portraitSession: return "person.crop.square"
        case .event: return "party.popper"
        case .realEstate: return "house"
        case .product: return "shippingbox"
        }
    }

    var entries: [ShotListEntry] {
        switch self {
        case .wedding:
            return [
                ShotListEntry(title: "Details: rings, invitation, shoes, flowers"),
                ShotListEntry(title: "Getting ready, both sides"),
                ShotListEntry(title: "Dress or suit on, final touches"),
                ShotListEntry(title: "First look, if there is one"),
                ShotListEntry(title: "Venue, inside and out, before guests arrive"),
                ShotListEntry(title: "Guests arriving"),
                ShotListEntry(title: "Processional and the walk down the aisle"),
                ShotListEntry(title: "Vows and ring exchange"),
                ShotListEntry(title: "First kiss and recessional"),
                ShotListEntry(title: "Family formals", notes: "Get the list of groupings beforehand"),
                ShotListEntry(title: "Wedding party"),
                ShotListEntry(title: "Couple portraits"),
                ShotListEntry(title: "Reception room and table details"),
                ShotListEntry(title: "Entrance, toasts and speeches"),
                ShotListEntry(title: "First dance and parent dances"),
                ShotListEntry(title: "Cake cutting"),
                ShotListEntry(title: "Dance floor candids"),
                ShotListEntry(title: "Send-off")
            ]
        case .engagement:
            return [
                ShotListEntry(title: "Wide shot of the couple in the setting"),
                ShotListEntry(title: "Walking together, candid"),
                ShotListEntry(title: "Close embrace, faces together"),
                ShotListEntry(title: "The ring, close up"),
                ShotListEntry(title: "Laughing, unposed moments"),
                ShotListEntry(title: "Individual portraits of each"),
                ShotListEntry(title: "Second outfit or location"),
                ShotListEntry(title: "Golden-hour backlit portraits"),
                ShotListEntry(title: "Save-the-date frame with room for text")
            ]
        case .portraitSession:
            return [
                ShotListEntry(title: "Head and shoulders, looking at camera"),
                ShotListEntry(title: "Head and shoulders, looking away"),
                ShotListEntry(title: "Half length"),
                ShotListEntry(title: "Full length"),
                ShotListEntry(title: "Candid, between poses"),
                ShotListEntry(title: "Profile"),
                ShotListEntry(title: "Hands or a detail that says something about them"),
                ShotListEntry(title: "Environmental portrait in their space"),
                ShotListEntry(title: "Second outfit or background")
            ]
        case .event:
            return [
                ShotListEntry(title: "Venue and signage before doors open"),
                ShotListEntry(title: "Branding, décor and table details"),
                ShotListEntry(title: "Guests arriving and registration"),
                ShotListEntry(title: "Hosts and key people", notes: "Get the list of names beforehand"),
                ShotListEntry(title: "Speakers or performers on stage"),
                ShotListEntry(title: "Audience reactions"),
                ShotListEntry(title: "Networking and candid groups"),
                ShotListEntry(title: "Food and drink"),
                ShotListEntry(title: "Sponsors and partners"),
                ShotListEntry(title: "Wide shot of the full room"),
                ShotListEntry(title: "Closing moments")
            ]
        case .realEstate:
            return [
                ShotListEntry(title: "Front exterior, straight on"),
                ShotListEntry(title: "Front exterior, at an angle"),
                ShotListEntry(title: "Entry"),
                ShotListEntry(title: "Living room"),
                ShotListEntry(title: "Kitchen, wide"),
                ShotListEntry(title: "Kitchen details"),
                ShotListEntry(title: "Dining area"),
                ShotListEntry(title: "Main bedroom"),
                ShotListEntry(title: "Other bedrooms"),
                ShotListEntry(title: "Bathrooms"),
                ShotListEntry(title: "Back exterior and garden"),
                ShotListEntry(title: "Views and neighbourhood features"),
                ShotListEntry(title: "Twilight exterior", notes: "During blue hour, with the lights on")
            ]
        case .product:
            return [
                ShotListEntry(title: "Hero shot on a clean background"),
                ShotListEntry(title: "Front, back and sides"),
                ShotListEntry(title: "Three-quarter view"),
                ShotListEntry(title: "Top-down"),
                ShotListEntry(title: "Detail and texture close-ups"),
                ShotListEntry(title: "Scale shot, in hand or with a familiar object"),
                ShotListEntry(title: "Packaging"),
                ShotListEntry(title: "Lifestyle shot in use"),
                ShotListEntry(title: "Variants and colours")
            ]
        }
    }
}

extension Shoot {
    /// Copies `entries` to the end of the shot list. The caller saves.
    func appendShots(_ entries: [ShotListEntry], in context: ModelContext) {
        var order = ((shotList ?? []).map(\.order).max() ?? -1) + 1
        for entry in entries {
            let item = ShotListItem(shoot: self, title: entry.title, notes: entry.notes, order: order)
            context.insert(item)
            order += 1
        }
    }

    /// A new template with this shoot's shot list (ticks not included). The caller saves.
    @discardableResult
    func saveShotList(asTemplateNamed name: String, in context: ModelContext) -> ShotListTemplate {
        let template = ShotListTemplate(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(template)
        for (order, item) in orderedShotList.enumerated() {
            context.insert(ShotListTemplateItem(template: template, title: item.title, notes: item.notes, order: order))
        }
        return template
    }
}
