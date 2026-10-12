//
//  DevelopmentRecipeTests.swift
//  ShutterManagerTests
//
//  Development recipes: what the timer runs, and that export, import and backups carry them.
//

import Foundation
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct DevelopmentRecipeTests {
    private func export(_ recipes: [DevelopmentRecipe], gear: [GearItem] = []) throws -> Data {
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        let document = service.buildExportData(configuration: .init(format: .json),
                                               library: LibraryContents(gearItems: gear, developmentRecipes: recipes))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    @Test func stepsRunInOrderAndNeedTimes() throws {
        let container = try TestSupport.makeContainer()
        let recipe = TestSupport.insertSampleRecipe(into: container.mainContext)
        try container.mainContext.save()
        #expect(recipe.orderedSteps.map(\.name) == ["Developer", "Stop", "Fixer"])
        #expect(recipe.totalDuration == 700)
        #expect(recipe.isRunnable)
        #expect(recipe.stepPlans.first?.agitation == .everyMinute)
        #expect(recipe.chemistrySummary == "Ilfosol 3 1+9")
    }

    @Test func draftEditsApplyOnlyWhenSaved() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let recipe = TestSupport.insertSampleRecipe(into: context)
        try context.save()
        let stopID = recipe.orderedSteps[1].id

        var draft = DevelopmentRecipeDraft(recipe: recipe)
        #expect(draft.steps.map(\.name) == ["Developer", "Stop", "Fixer"])
        draft.name = "  HP5 at 800  "
        draft.steps[0].durationSeconds = 600
        draft.steps.remove(at: 1)                // drop Stop
        draft.steps.swapAt(0, 1)                 // Fixer first, for the test
        draft.addSteps(from: .blackAndWhite)     // five template steps, no times
        #expect(recipe.name == "HP5 in Ilfosol 3", "Nothing changes before apply")

        draft.apply(to: recipe, in: context)
        try context.save()
        #expect(recipe.name == "HP5 at 800")
        #expect(recipe.orderedSteps.map(\.name) == ["Fixer", "Developer", "Developer", "Stop", "Fixer", "Wash", "Wetting agent"])
        #expect(recipe.orderedSteps[1].durationSeconds == 600)
        #expect(!recipe.isRunnable, "Template steps have no times yet")
        #expect(try context.fetch(FetchDescriptor<DevelopmentStep>()).count == 7)
        #expect(!(try context.fetch(FetchDescriptor<DevelopmentStep>()).contains { $0.id == stopID }))
        #expect(!DevelopmentRecipeDraft().canSave)
    }

    @Test func agitationRoundTripsThroughTheStoredSeconds() {
        let step = DevelopmentStep(name: "Developer", durationSeconds: 600, agitation: .everyThirtySeconds)
        #expect(step.agitation == .everyThirtySeconds)
        step.agitation = .none
        #expect(step.agitationInitialSeconds == 0)
        #expect(step.agitation.isNone)
    }

    @Test func templatesNameTheUsualSteps() {
        #expect(DevelopmentRecipe.Template.blackAndWhite.steps.map(\.name).prefix(3) == ["Developer", "Stop", "Fixer"])
        #expect(DevelopmentRecipe.Template.colorNegative.steps.first?.name == "Developer")
        #expect(DevelopmentRecipe.Template.slide.steps.count == 7)
    }

    @Test func recipesRoundTripThroughJSON() async throws {
        let source = try TestSupport.makeContainer()
        let recipe = TestSupport.insertSampleRecipe(into: source.mainContext)
        try source.mainContext.save()
        let data = try export([recipe])

        let destination = try TestSupport.makeContainer()
        try await DataImportService(settingsStore: TestSupport.makeDefaults()).importData(
            from: data, to: destination.mainContext, strategy: .replace)
        let restored = try #require(try destination.mainContext.fetch(FetchDescriptor<DevelopmentRecipe>()).first)
        #expect(restored.id == recipe.id)
        #expect(restored.name == "HP5 in Ilfosol 3")
        #expect(restored.filmStockID == "ilfordHP5Plus")
        #expect(restored.dilution == "1+9")
        #expect(restored.temperatureCelsius == 20)
        #expect(restored.notes == "Box speed")
        #expect(restored.orderedSteps.map(\.durationSeconds) == [390, 10, 300])
        #expect(restored.orderedSteps.first?.agitation == .everyMinute)
        #expect(restored.orderedSteps.last?.notes == "Rapid Fixer 1+4")
        #expect(restored.orderedSteps.map(\.id) == recipe.orderedSteps.map(\.id))
    }

    @Test func mergingKeepsOneCopyAndReplaceRemovesRecipes() async throws {
        let source = try TestSupport.makeContainer()
        let recipe = TestSupport.insertSampleRecipe(into: source.mainContext)
        try source.mainContext.save()
        let withRecipe = try export([recipe])

        let destination = try TestSupport.makeContainer()
        let service = DataImportService(settingsStore: TestSupport.makeDefaults())
        try await service.importData(from: withRecipe, to: destination.mainContext, strategy: .merge)
        try await service.importData(from: withRecipe, to: destination.mainContext, strategy: .merge)
        let context = destination.mainContext
        #expect(try context.fetch(FetchDescriptor<DevelopmentRecipe>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<DevelopmentStep>()).count == 3)

        try await service.importData(from: try export([]), to: context, strategy: .replace)
        #expect(try context.fetch(FetchDescriptor<DevelopmentRecipe>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DevelopmentStep>()).isEmpty)
    }

    @Test func filesFromBeforeRecipesStillImport() throws {
        // An export written before `developmentRecipes` existed has no such key.
        let data = try export([])
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "developmentRecipes")
        let document = try ImportDocument.decode(try JSONSerialization.data(withJSONObject: json))
        #expect(document.recipes.isEmpty)
    }

    @Test func validationCoversRecipes() throws {
        let container = try TestSupport.makeContainer()
        let recipe = TestSupport.insertSampleRecipe(into: container.mainContext)
        recipe.temperatureCelsius = .nan
        let service = DataExportService(settingsStore: TestSupport.makeDefaults())
        var document = service.buildExportData(configuration: .init(format: .json),
                                               library: LibraryContents(gearItems: [], developmentRecipes: [recipe]))
        #expect(service.lastReplacedValueCount == 1)
        #expect(document.recipes.first?.temperatureCelsius == nil)
        try ImportDocument.validate(document)
        #expect(document.recordCount == 4)

        // A hand-edited step time past the limits is rejected.
        let recipeJSON = """
            {"id":"\(UUID().uuidString)","name":"Bad","dateCreated":"2026-01-01T00:00:00Z",
             "steps":[{"id":"\(UUID().uuidString)","name":"Developer","order":0,"durationSeconds":99999999999}]}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        document.developmentRecipes = [try decoder.decode(DevelopmentRecipeDTO.self, from: Data(recipeJSON.utf8))]
        #expect(throws: ImportError.self) { try ImportDocument.validate(document) }
    }

    @Test func deletingEverythingCoversEveryModel() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        TestSupport.insertSampleBody(into: context)
        TestSupport.insertSampleRecipe(into: context)
        try context.save()
        try context.deleteEveryRecord()
        try context.save()
        #expect(try context.fetch(FetchDescriptor<GearItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ShutterCountReading>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DevelopmentRecipe>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DevelopmentStep>()).isEmpty)
    }

    @Test func libraryContentsCountsRecipesAndSteps() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        TestSupport.insertSampleBody(into: context)
        TestSupport.insertSampleRecipe(into: context)
        try context.save()
        let library = try LibraryContents.fetch(from: context)
        #expect(library.gearItems.count == 1)
        #expect(library.developmentRecipes.count == 1)
        #expect(library.otherRecordCount == 9)
        #expect(!library.isEmpty)
        #expect(LibraryContents.empty.isEmpty)
    }
}
