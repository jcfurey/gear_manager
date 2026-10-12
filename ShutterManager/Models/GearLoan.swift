//
//  GearLoan.swift
//  ShutterManager
//
//  Gear lent to someone, or rented from someone.
//

import Foundation
import SwiftData

/// A loan of one item: lent out to a person, or rented in from a person or company. An item is
/// "on loan" while it has a loan with no return date.
@Model
final class GearLoan {
    var id: UUID = UUID()
    var gearItem: GearItem?
    /// A `LoanDirection` raw value, stored as text (see `direction`).
    var directionID: String = "lentOut"
    /// Who has it, or who it was rented from.
    var person: String = ""
    /// Phone, email or anything else that helps get it back.
    var contact: String = ""
    var outDate: Date = Date()
    var dueDate: Date?
    var returnedDate: Date?
    var notes: String = ""

    init(gearItem: GearItem? = nil, direction: LoanDirection = .lentOut, person: String = "",
         contact: String = "", outDate: Date = Date(), dueDate: Date? = nil, notes: String = "") {
        self.id = UUID()
        self.gearItem = gearItem
        self.directionID = direction.rawValue
        self.person = person
        self.contact = contact
        self.outDate = outDate
        self.dueDate = dueDate
        self.notes = notes
    }

    var direction: LoanDirection {
        get { LoanDirection(rawValue: directionID) ?? .lentOut }
        set { directionID = newValue.rawValue }
    }

    var isOpen: Bool { returnedDate == nil }

    /// Open and past its due day (calendar days, so it turns overdue the morning after).
    var isOverdue: Bool {
        guard isOpen, let dueDate else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: Date())
    }

    /// "Lent to Sam" / "Rented from Lens Rentals"
    var summary: String {
        let who = person.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = who.isEmpty ? "someone" : who
        switch direction {
        case .lentOut: return "Lent to \(name)"
        case .rentedIn: return "Rented from \(name)"
        }
    }
}

/// Which way a loan goes. Raw values are stored: never rename one.
enum LoanDirection: String, CaseIterable, Codable, Identifiable {
    /// The user's gear, with someone else.
    case lentOut
    /// Someone else's gear, with the user.
    case rentedIn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lentOut: return "Lent out"
        case .rentedIn: return "Rented in"
        }
    }
}
