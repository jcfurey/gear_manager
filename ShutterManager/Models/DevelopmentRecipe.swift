//
//  DevelopmentRecipe.swift
//  ShutterManager
//
//  Saved film development recipes for the development timer.
//

import Foundation
import SwiftData

/// A film development recipe: the chemistry and an ordered list of timed steps.
@Model
final class DevelopmentRecipe {
    var id: UUID = UUID()
    var name: String = ""
    /// A `FilmStock` ID, or "" for a recipe not tied to one stock.
    var filmStockID: String = ""
    var developer: String = ""
    /// As written on the bottle or in the chart: "1+9", "stock", "1:50".
    var dilution: String = ""
    /// Process temperature in °C (shown in the user's units).
    var temperatureCelsius: Double = 20
    var notes: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \DevelopmentStep.recipe)
    var steps: [DevelopmentStep]? = []

    init(name: String = "", filmStockID: String = "", developer: String = "", dilution: String = "",
         temperatureCelsius: Double = 20, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.filmStockID = filmStockID
        self.developer = developer
        self.dilution = dilution
        self.temperatureCelsius = temperatureCelsius
        self.notes = notes
        self.dateCreated = Date()
        self.dateModified = Date()
    }

    func markModified() { dateModified = Date() }

    var orderedSteps: [DevelopmentStep] {
        (steps ?? []).sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    /// Seconds for every step.
    var totalDuration: Int { (steps ?? []).reduce(0) { $0 + max($1.durationSeconds, 0) } }

    /// Every step has a time, so the timer can run it.
    var isRunnable: Bool {
        let steps = orderedSteps
        return !steps.isEmpty && steps.allSatisfy { $0.durationSeconds > 0 }
    }

    /// The steps as the timer runs them.
    var stepPlans: [DevelopmentStepPlan] {
        orderedSteps.map {
            DevelopmentStepPlan(name: $0.name, duration: Double($0.durationSeconds), agitation: $0.agitation)
        }
    }

    var filmStock: FilmStock? { filmStockID.isEmpty ? nil : FilmStock(id: filmStockID) }

    /// "Ilfosol 3 1+9 · 20 °C"-style summary pieces, without the temperature (which the view
    /// formats in the user's units).
    var chemistrySummary: String? {
        [developer, dilution].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ").nonEmptyOrNil
    }
}

/// One timed step of a recipe.
@Model
final class DevelopmentStep {
    var id: UUID = UUID()
    var recipe: DevelopmentRecipe?
    var name: String = ""
    var order: Int = 0
    var durationSeconds: Int = 0
    var agitationInitialSeconds: Int = 0
    var agitationIntervalSeconds: Int = 0
    var agitationDurationSeconds: Int = 0
    var notes: String = ""

    init(recipe: DevelopmentRecipe? = nil, name: String = "", order: Int = 0, durationSeconds: Int = 0,
         agitation: AgitationPattern = .none, notes: String = "") {
        self.id = UUID()
        self.recipe = recipe
        self.name = name
        self.order = order
        self.durationSeconds = durationSeconds
        self.agitationInitialSeconds = Int(agitation.initialSeconds)
        self.agitationIntervalSeconds = Int(agitation.intervalSeconds)
        self.agitationDurationSeconds = Int(agitation.durationSeconds)
        self.notes = notes
    }

    var agitation: AgitationPattern {
        get {
            AgitationPattern(initialSeconds: Double(agitationInitialSeconds),
                             intervalSeconds: Double(agitationIntervalSeconds),
                             durationSeconds: Double(agitationDurationSeconds))
        }
        set {
            agitationInitialSeconds = Int(newValue.initialSeconds.rounded())
            agitationIntervalSeconds = Int(newValue.intervalSeconds.rounded())
            agitationDurationSeconds = Int(newValue.durationSeconds.rounded())
        }
    }
}

// MARK: - Starting points

extension DevelopmentRecipe {
    /// Step outlines for a new recipe. They name the usual steps and their agitation; the times
    /// are left for you to fill in from your chemistry's instructions.
    enum Template: String, CaseIterable, Identifiable {
        case blackAndWhite, colorNegative, slide

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .blackAndWhite: return "Black and white"
            case .colorNegative: return "Colour negative (C-41)"
            case .slide: return "Slide (E-6)"
            }
        }

        var steps: [(name: String, agitation: AgitationPattern)] {
            switch self {
            case .blackAndWhite:
                return [("Developer", .everyMinute), ("Stop", .everyMinute), ("Fixer", .everyMinute),
                        ("Wash", .none), ("Wetting agent", .none)]
            case .colorNegative:
                return [("Developer", .everyThirtySeconds), ("Blix", .everyThirtySeconds), ("Wash", .none),
                        ("Stabilizer", .none)]
            case .slide:
                return [("First developer", .everyThirtySeconds), ("Wash", .none),
                        ("Colour developer", .everyThirtySeconds), ("Wash", .none),
                        ("Blix", .everyThirtySeconds), ("Wash", .none), ("Stabilizer", .none)]
            }
        }
    }
}

// MARK: - Editing

/// An editable copy of a recipe. The editor changes this value and writes it to the recipe only
/// on Save, so Cancel leaves the library untouched.
struct DevelopmentRecipeDraft: Equatable {
    struct Step: Identifiable, Equatable {
        var id = UUID()
        var name = ""
        var durationSeconds = 0
        var agitation = AgitationPattern.none
        var notes = ""
    }

    var name = ""
    var filmStockID = ""
    var developer = ""
    var dilution = ""
    var temperatureCelsius = 20.0
    var notes = ""
    var steps: [Step] = []

    init() {}

    init(recipe: DevelopmentRecipe) {
        name = recipe.name
        filmStockID = recipe.filmStockID
        developer = recipe.developer
        dilution = recipe.dilution
        temperatureCelsius = recipe.temperatureCelsius
        notes = recipe.notes
        steps = recipe.orderedSteps.map {
            Step(id: $0.id, name: $0.name, durationSeconds: $0.durationSeconds, agitation: $0.agitation, notes: $0.notes)
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool { !trimmedName.isEmpty }

    /// Adds `template`'s steps after the existing ones, with no times yet.
    mutating func addSteps(from template: DevelopmentRecipe.Template) {
        steps += template.steps.map { Step(name: $0.name, agitation: $0.agitation) }
    }

    /// Writes the draft into `recipe`: fields, then steps matched by ID (kept steps update, new
    /// ones are inserted, removed ones deleted), ordered as the draft lists them. The caller saves.
    func apply(to recipe: DevelopmentRecipe, in context: ModelContext) {
        recipe.name = trimmedName
        recipe.filmStockID = filmStockID
        recipe.developer = developer.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.dilution = dilution.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.temperatureCelsius = temperatureCelsius.isFinite ? temperatureCelsius : 20
        recipe.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var existing = Dictionary((recipe.steps ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (order, draft) in steps.enumerated() {
            let step = existing.removeValue(forKey: draft.id) ?? {
                let inserted = DevelopmentStep(recipe: recipe)
                inserted.id = draft.id
                context.insert(inserted)
                return inserted
            }()
            step.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            step.order = order
            step.durationSeconds = max(draft.durationSeconds, 0)
            step.agitation = draft.agitation
            step.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for removed in existing.values {
            context.delete(removed)
        }
        recipe.markModified()
    }
}
