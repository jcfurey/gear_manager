//
//  FilmToolViews.swift
//  ShutterManager
//
//  Reciprocity correction, development recipes, and the development timer.
//

import SwiftUI
import SwiftData
import UIKit

private typealias ToolKey = Constants.UserDefaultsKeys

// MARK: - Reciprocity

struct ReciprocityView: View {
    @AppStorage(ToolKey.toolValuesPrefix + "reciprocity.film") private var stockID = FilmStock.builtIns.first?.id ?? ""
    @AppStorage(ToolKey.toolValuesPrefix + "reciprocity.metered") private var metered = 8.0

    private let timers = ToolTimers.shared
    private var stock: FilmStock? { FilmStock(id: stockID) }

    var body: some View {
        Form {
            Section {
                FilmStockRow(stockID: $stockID, allowsNone: false)
                MeasurementField(title: "Metered time", value: $metered, unit: "s", maximum: 86_400)
                    .accessibilityIdentifier("reciprocity.metered")
            } footer: {
                Text("The exposure your meter (or the ND calculator) gives, in seconds.")
            }

            if let stock, let result = stock.reciprocity.correct(metered: metered) {
                Section("Expose For") {
                    ReciprocityResultRows(result: result, stock: stock)
                    if timers.exposure == nil, result.corrected >= 1 {
                        Button {
                            timers.startExposure(seconds: result.corrected,
                                                 title: "\(stock.name) \(ExposureScale.shutterLabel(result.corrected))")
                        } label: {
                            Label("Start Bulb Timer", systemImage: "timer")
                        }
                    }
                }
                Section {
                    ReciprocityGuidance(stock: stock)
                } header: {
                    Text("From the Maker")
                } footer: {
                    if let source = stock.source {
                        Text("Source: \(source)")
                    }
                }
            }
        }
        .navigationTitle(Tool.reciprocity.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What the maker publishes for a stock, in words and rows.
private struct ReciprocityGuidance: View {
    let stock: FilmStock

    var body: some View {
        switch stock.reciprocity {
        case let .powerLaw(exponent, from):
            Text("Corrected time = metered time^\(ExposureScale.decimal(exponent, places: 2)) for metered times over \(ExposureScale.durationLabel(max(from, 1))).")
        case let .table(uncorrectedUpTo, points, notRecommendedFrom):
            Text("No correction up to \(ExposureScale.shutterLabel(uncorrectedUpTo)). Between the rows below, the calculator follows a straight line on log–log axes.")
            ForEach(points, id: \.metered) { point in
                LabeledContent("Meter \(ExposureScale.durationLabel(point.metered))") {
                    Text("Expose \(ExposureScale.durationLabel(point.corrected)) (+\(ExposureScale.decimal(log2(point.corrected / point.metered), places: 1)))")
                }
            }
            if let notRecommendedFrom {
                Text("Not recommended from \(ExposureScale.durationLabel(notRecommendedFrom)).")
            }
        case let .noCorrectionUpTo(seconds):
            Text("No correction needed up to \(ExposureScale.durationLabel(seconds)). The maker gives no figures beyond that.")
        case .unpublished:
            Text("The maker publishes no long-exposure figures for this film.")
        }
        if let note = stock.reciprocityNote {
            Text(note).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Recipes

struct DevelopmentRecipesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DevelopmentRecipe.name) private var recipes: [DevelopmentRecipe]

    @State private var showingNewRecipe = false
    private let timers = ToolTimers.shared

    var body: some View {
        List {
            if timers.development != nil {
                Section {
                    NavigationLink(value: RunningTimerDestination.development) {
                        Label("Development in Progress", systemImage: "timer")
                    }
                }
            }
            if recipes.isEmpty {
                ContentUnavailableView {
                    Label("No Recipes", systemImage: "flask")
                } description: {
                    Text("Save a recipe for each film and developer you use, then run it step by step.")
                } actions: {
                    Button("New Recipe") { showingNewRecipe = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ForEach(recipes) { recipe in
                    NavigationLink {
                        DevelopmentRecipeDetailView(recipe: recipe)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.name)
                            Text(Self.summary(recipe)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(Tool.development.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewRecipe = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New recipe")
                .accessibilityIdentifier("newRecipeButton")
            }
        }
        .sheet(isPresented: $showingNewRecipe) {
            DevelopmentRecipeEditor(recipe: nil)
        }
    }

    static func summary(_ recipe: DevelopmentRecipe) -> String {
        [recipe.filmStock?.displayName, recipe.chemistrySummary,
         recipe.totalDuration > 0 ? ExposureScale.durationLabel(Double(recipe.totalDuration)) : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(recipes[index]) }
        if !context.saveOrLog() { context.rollback() }
    }
}

struct DevelopmentRecipeDetailView: View {
    let recipe: DevelopmentRecipe

    @State private var showingEditor = false
    @State private var showingTimer = false
    @State private var confirmReplaceRun = false
    private let timers = ToolTimers.shared

    var body: some View {
        UnitsReader { units in
            List {
                Section {
                    if let stock = recipe.filmStock {
                        LabeledContent("Film", value: stock.displayName)
                    }
                    if !recipe.developer.isEmpty {
                        LabeledContent("Developer", value: recipe.developer)
                    }
                    if !recipe.dilution.isEmpty {
                        LabeledContent("Dilution", value: recipe.dilution)
                    }
                    LabeledContent("Temperature", value: units.format(celsius: recipe.temperatureCelsius))
                }
                Section {
                    ForEach(recipe.orderedSteps) { step in
                        LabeledContent {
                            Text(step.durationSeconds > 0 ? CountdownText.format(Double(step.durationSeconds)) : "No time")
                                .monospacedDigit()
                                .foregroundStyle(step.durationSeconds > 0 ? .primary : Color.orange)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.name.isEmpty ? "Step" : step.name)
                                Text(AgitationChoice(step.agitation).summary(step.agitation))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    if recipe.totalDuration > 0 {
                        Text("\(ExposureScale.durationLabel(Double(recipe.totalDuration))) in all, plus pouring time.")
                    }
                }
                if !recipe.notes.isEmpty {
                    Section("Notes") { Text(recipe.notes) }
                }
                Section {
                    Button {
                        if timers.development != nil {
                            confirmReplaceRun = true
                        } else {
                            startTimer()
                        }
                    } label: {
                        Label("Start Development Timer", systemImage: "timer")
                    }
                    .disabled(!recipe.isRunnable)
                    .accessibilityIdentifier("startDevelopmentButton")
                } footer: {
                    if !recipe.isRunnable {
                        Text("Give every step a time to run the timer.")
                    }
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditor = true }
                    .accessibilityIdentifier("editRecipeButton")
            }
        }
        .sheet(isPresented: $showingEditor) {
            DevelopmentRecipeEditor(recipe: recipe)
        }
        .navigationDestination(isPresented: $showingTimer) {
            DevelopmentTimerView()
        }
        .confirmationDialog("Replace the development in progress?", isPresented: $confirmReplaceRun, titleVisibility: .visible) {
            Button("Start \(recipe.name)", role: .destructive) { startTimer() }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func startTimer() {
        timers.beginDevelopment(recipeName: recipe.name, recipeID: recipe.id, steps: recipe.stepPlans)
        showingTimer = true
    }
}

// MARK: - Editing

/// The agitation presets the step editor offers.
enum AgitationChoice: String, CaseIterable, Identifiable {
    case off, everyMinute, everyThirtySeconds, continuous, custom

    var id: String { rawValue }

    init(_ pattern: AgitationPattern) {
        switch pattern {
        case AgitationPattern.none: self = .off
        case .everyMinute: self = .everyMinute
        case .everyThirtySeconds: self = .everyThirtySeconds
        case _ where pattern.initialSeconds >= 86_400: self = .continuous
        default: self = .custom
        }
    }

    var displayName: String {
        switch self {
        case .off: return "None"
        case .everyMinute: return "10 s each minute (Ilford)"
        case .everyThirtySeconds: return "5 s every 30 s (Kodak)"
        case .continuous: return "Continuous (rotary)"
        case .custom: return "Custom"
        }
    }

    var pattern: AgitationPattern? {
        switch self {
        case .off: return AgitationPattern.none
        case .everyMinute: return .everyMinute
        case .everyThirtySeconds: return .everyThirtySeconds
        case .continuous: return AgitationPattern(initialSeconds: 86_400, intervalSeconds: 0, durationSeconds: 0)
        case .custom: return nil
        }
    }

    func summary(_ pattern: AgitationPattern) -> String {
        switch self {
        case .custom:
            return "Agitate \(Int(pattern.initialSeconds)) s, then \(Int(pattern.durationSeconds)) s every \(Int(pattern.intervalSeconds)) s"
        case .off:
            return "No agitation"
        default:
            return displayName
        }
    }
}

struct DevelopmentRecipeEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// The recipe to edit, or nil for a new one.
    let recipe: DevelopmentRecipe?

    @State private var draft: DevelopmentRecipeDraft
    @State private var saveFailed = false

    init(recipe: DevelopmentRecipe?) {
        self.recipe = recipe
        _draft = State(initialValue: recipe.map(DevelopmentRecipeDraft.init(recipe:)) ?? DevelopmentRecipeDraft())
    }

    var body: some View {
        NavigationStack {
            UnitsReader { units in
                Form {
                    Section {
                        TextField("Name", text: $draft.name)
                            .accessibilityIdentifier("recipeNameField")
                        FilmStockRow(stockID: $draft.filmStockID)
                        TextField("Developer", text: $draft.developer)
                        TextField("Dilution (e.g. 1+9)", text: $draft.dilution)
                        MeasurementField(title: "Temperature", value: Binding(
                            get: { units.displayTemperature(celsius: draft.temperatureCelsius) },
                            set: { draft.temperatureCelsius = units.celsius(fromDisplay: $0) }
                        ), unit: units.temperatureUnit, maximum: 212)
                    }

                    Section {
                        ForEach($draft.steps) { $step in
                            NavigationLink {
                                DevelopmentStepEditor(step: $step)
                            } label: {
                                LabeledContent(step.name.isEmpty ? "Step" : step.name,
                                               value: step.durationSeconds > 0 ? CountdownText.format(Double(step.durationSeconds)) : "Set time")
                            }
                        }
                        .onDelete { draft.steps.remove(atOffsets: $0) }
                        .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                        Button {
                            draft.steps.append(.init(name: "Step \(draft.steps.count + 1)"))
                        } label: {
                            Label("Add Step", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("addStepButton")
                        Menu {
                            ForEach(DevelopmentRecipe.Template.allCases) { template in
                                Button(template.displayName) { draft.addSteps(from: template) }
                            }
                        } label: {
                            Label("Add Usual Steps", systemImage: "list.bullet")
                        }
                        .accessibilityIdentifier("addTemplateStepsButton")
                    } header: {
                        Text("Steps")
                    } footer: {
                        Text("The usual steps come without times: take them from your developer's chart and your chemistry's instructions.")
                    }

                    Section("Notes") {
                        TextField("Push, pull, tank, water…", text: $draft.notes, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.canSave)
                        .accessibilityIdentifier("saveRecipeButton")
                }
            }
            .persistenceErrorAlert(isPresented: $saveFailed)
        }
    }

    private func save() {
        let target: DevelopmentRecipe
        if let recipe {
            target = recipe
        } else {
            target = DevelopmentRecipe()
            context.insert(target)
        }
        draft.apply(to: target, in: context)
        guard context.saveOrLog() else {
            context.rollback()
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.saveSuccess()
        dismiss()
    }
}

struct DevelopmentStepEditor: View {
    @Binding var step: DevelopmentRecipeDraft.Step

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $step.name)
                CountField(title: "Minutes", value: Binding(
                    get: { step.durationSeconds / 60 },
                    set: { step.durationSeconds = $0 * 60 + step.durationSeconds % 60 }
                ), maximum: 600)
                .accessibilityIdentifier("stepMinutesField")
                CountField(title: "Seconds", value: Binding(
                    get: { step.durationSeconds % 60 },
                    set: { step.durationSeconds = (step.durationSeconds / 60) * 60 + min($0, 59) }
                ), maximum: 59)
            } header: {
                Text("Time")
            }

            Section {
                Picker("Agitation", selection: Binding(
                    get: { AgitationChoice(step.agitation) },
                    set: { choice in
                        if let pattern = choice.pattern {
                            step.agitation = pattern
                        } else if AgitationChoice(step.agitation) != .custom {
                            step.agitation = AgitationPattern(initialSeconds: 30, intervalSeconds: 60, durationSeconds: 10)
                        }
                    }
                )) {
                    ForEach(AgitationChoice.allCases) { Text($0.displayName).tag($0) }
                }
                if AgitationChoice(step.agitation) == .custom {
                    CountField(title: "First", value: seconds(\.initialSeconds), unit: "s", maximum: 3600)
                    CountField(title: "Then every", value: seconds(\.intervalSeconds), unit: "s", maximum: 3600)
                    CountField(title: "For", value: seconds(\.durationSeconds), unit: "s", maximum: 3600)
                }
            } header: {
                Text("Agitation")
            } footer: {
                Text("The timer alerts you at each agitation and 10 seconds before the step ends.")
            }

            Section("Notes") {
                TextField("Notes", text: $step.notes, axis: .vertical)
            }
        }
        .navigationTitle(step.name.isEmpty ? "Step" : step.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func seconds(_ keyPath: WritableKeyPath<AgitationPattern, Double>) -> Binding<Int> {
        Binding(
            get: { Int(step.agitation[keyPath: keyPath]) },
            set: { step.agitation[keyPath: keyPath] = Double($0) }
        )
    }
}

// MARK: - Timer

struct DevelopmentTimerView: View {
    private let timers = ToolTimers.shared

    var body: some View {
        Group {
            if let run = timers.development {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    DevelopmentRunView(run: run, now: context.date, timers: timers)
                }
            } else {
                ContentUnavailableView("No Development Running", systemImage: "flask",
                                       description: Text("Start one from a recipe."))
            }
        }
        .navigationTitle(timers.development?.recipeName ?? "Development")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if timers.development != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("End", role: .destructive) { timers.endDevelopment() }
                        .accessibilityIdentifier("endDevelopmentButton")
                }
            }
        }
        // A darkroom timer you can glance at: the screen stays on while this is showing.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

private struct DevelopmentRunView: View {
    let run: ToolTimers.DevelopmentRun
    let now: Date
    let timers: ToolTimers
    /// The countdown grows with the user's text size, from 64 points at the default.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 64

    var body: some View {
        let session = run.session
        let phase = session.phase(at: now)
        List {
            Section {
                VStack(spacing: 12) {
                    Text(session.currentStep?.name ?? "Done")
                        .font(.title2.weight(.semibold))
                    Text(countdown(phase, session))
                        .font(.system(size: countdownSize, weight: .light, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel(CountdownText.spoken(remaining(phase, session)))
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("developmentCountdown")
                    if case .running(_, true) = phase {
                        Label("Agitate", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    }
                    controls(phase, session)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .sensoryFeedback(.impact(weight: .heavy), trigger: isAgitating(phase)) { wasAgitating, agitating in
                    agitating && !wasAgitating
                }
            }
            Section("Steps") {
                ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                    HStack {
                        Image(systemName: index < session.currentIndex ? "checkmark.circle.fill"
                              : (index == session.currentIndex ? "circle.inset.filled" : "circle"))
                            .foregroundStyle(index <= session.currentIndex ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                        Text(step.name)
                        Spacer()
                        Text(CountdownText.format(step.duration)).monospacedDigit().foregroundStyle(.secondary)
                            .accessibilityLabel(CountdownText.spoken(step.duration))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(index < session.currentIndex ? "Done"
                                        : (index == session.currentIndex ? "Current step" : "Not started"))
                }
            }
        }
    }

    private func isAgitating(_ phase: DevelopmentSession.Phase) -> Bool {
        if case .running(_, true) = phase { return true }
        return false
    }

    private func countdown(_ phase: DevelopmentSession.Phase, _ session: DevelopmentSession) -> String {
        CountdownText.format(remaining(phase, session))
    }

    /// Seconds left in the step, or its whole length before it starts.
    private func remaining(_ phase: DevelopmentSession.Phase, _ session: DevelopmentSession) -> Double {
        switch phase {
        case .ready: return session.currentStep?.duration ?? 0
        case let .running(remaining, _), let .paused(remaining): return remaining
        case .stepComplete, .finished: return 0
        }
    }

    @ViewBuilder
    private func controls(_ phase: DevelopmentSession.Phase, _ session: DevelopmentSession) -> some View {
        switch phase {
        case .ready:
            Button("Start \(session.currentStep?.name ?? "")") { timers.startStep() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("startStepButton")
        case .running:
            Button("Pause") { timers.pauseStep() }
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityIdentifier("pauseStepButton")
        case .paused:
            HStack {
                Button("Resume") { timers.startStep() }.buttonStyle(.borderedProminent)
                Button("Restart Step") { timers.restartStep() }.buttonStyle(.bordered)
            }
            .controlSize(.large)
        case .stepComplete:
            let isLast = session.currentIndex + 1 >= session.steps.count
            Button(isLast ? "Finish" : "Next: \(session.steps[session.currentIndex + 1].name)") { timers.nextStep() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("nextStepButton")
        case .finished:
            Label("All steps done", systemImage: "checkmark.circle.fill").foregroundStyle(AppColors.goodText)
        }
    }
}
