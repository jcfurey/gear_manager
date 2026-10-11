//
//  FilmStockTests.swift
//  ShutterManagerTests
//
//  Film stock IDs never change, custom stocks round-trip, and the catalog reproduces the makers'
//  own figures. Foundation-only, so it also runs on Linux (see CLAUDE.md).
//

import Foundation
import Testing
@testable import ShutterManager

struct FilmStockTests {
    // These IDs are stored in recipes and synced. Adding a stock is fine (add it here too);
    // renaming or removing one breaks existing libraries.
    @Test func filmStockIDsAreStable() {
        let frozen = [
            "ilfordPanFPlus", "ilfordFP4Plus", "ilfordHP5Plus", "ilfordDelta100", "ilfordDelta400",
            "ilfordDelta3200", "ilfordSFX200", "ilfordXP2Super", "ilfordOrthoPlus", "kentmerePan100",
            "kentmerePan400", "kodakTriX400", "kodakTMax100", "kodakTMax400", "kodakTMaxP3200",
            "kodakPortra160", "kodakPortra400", "kodakPortra800", "kodakEktar100", "kodakGold200",
            "kodakUltraMax400", "kodakColorPlus200", "kodakEktachromeE100", "fujiVelvia50", "fujiVelvia100",
            "fujiProvia100F", "fujiAcros100II", "fomapan100", "fomapan200", "fomapan400",
            "cinestill800T", "cinestill50D", "cinestill400D"
        ]
        for id in frozen {
            #expect(FilmStock(id: id) != nil, "Stored film stock \(id) was renamed or removed")
        }
        #expect(Set(FilmStock.builtIns.map(\.id)).count == FilmStock.builtIns.count, "Duplicate stock ID")
        #expect(FilmStock.makers == ["Ilford", "Kentmere", "Kodak", "Fujifilm", "Foma", "CineStill"])
    }

    @Test func everyTableRunsForwardAndOnlyLengthens() {
        for stock in FilmStock.builtIns {
            guard case let .table(uncorrected, points, notRecommended) = stock.reciprocity else { continue }
            #expect(!points.isEmpty, "\(stock.id) has an empty table")
            #expect(points.allSatisfy { $0.corrected >= $0.metered }, "\(stock.id) shortens an exposure")
            #expect(points.first.map { $0.metered >= uncorrected } ?? false)
            for (a, b) in zip(points, points.dropFirst()) {
                #expect(b.metered > a.metered && b.corrected > a.corrected, "\(stock.id) rows out of order")
            }
            if let notRecommended, let last = points.last {
                #expect(notRecommended > last.metered)
            }
        }
    }

    @Test func ilfordMatchesHarmansWorkedExample() throws {
        // Harman's HP5 Plus datasheet: metered 10 s gives 20.4 s (rounded to 20 s).
        let hp5 = try #require(FilmStock(id: "ilfordHP5Plus"))
        let result = try #require(hp5.reciprocity.correct(metered: 10))
        #expect(abs(result.corrected - 20.4) < 0.05)
        #expect(hp5.reciprocity.correct(metered: 1)?.basis == .noCorrection)
    }

    @Test func kodakTablesReproduceTheirRows() throws {
        let triX = try #require(FilmStock(id: "kodakTriX400"))
        #expect(triX.reciprocity.correct(metered: 1)?.corrected == 2)
        #expect(triX.reciprocity.correct(metered: 10)?.corrected == 50)
        #expect(triX.reciprocity.correct(metered: 100)?.corrected == 1200)
        #expect(triX.reciprocity.correct(metered: 1.0 / 60)?.basis == .noCorrection)
        #expect(triX.reciprocity.correct(metered: 400)?.basis == .extrapolated)
        let tmax400 = try #require(FilmStock(id: "kodakTMax400"))
        #expect(tmax400.reciprocity.correct(metered: 1)?.basis == .noCorrection)
        #expect(tmax400.reciprocity.correct(metered: 100)?.corrected == 300)
    }

    @Test func colourFilmsWithoutFiguresStayUncorrected() throws {
        let portra = try #require(FilmStock(id: "kodakPortra400"))
        #expect(portra.reciprocity.correct(metered: 0.5)?.basis == .noCorrection)
        #expect(portra.reciprocity.correct(metered: 30)?.basis == .noData)
        #expect(portra.reciprocity.correct(metered: 30)?.corrected == 30)
        #expect(FilmStock(id: "cinestill800T")?.reciprocity == .unpublished)
    }

    @Test func fujifilmLimitsAndSteps() throws {
        let velvia = try #require(FilmStock(id: "fujiVelvia50"))
        let eight = try #require(velvia.reciprocity.correct(metered: 8))
        #expect(abs(eight.extraStops - 0.5) < 1e-9)
        #expect(velvia.reciprocity.correct(metered: 64)?.basis == .notRecommended)
        let provia = try #require(FilmStock(id: "fujiProvia100F"))
        #expect(provia.reciprocity.correct(metered: 100)?.basis == .noCorrection)
        #expect(abs((provia.reciprocity.correct(metered: 240)?.extraStops ?? 0) - 1.0 / 3) < 1e-9)
        #expect(provia.reciprocity.correct(metered: 600)?.basis == .notRecommended)
        let acros = try #require(FilmStock(id: "fujiAcros100II"))
        #expect(acros.reciprocity.correct(metered: 60)?.basis == .noCorrection)
        #expect(abs((acros.reciprocity.correct(metered: 500)?.extraStops ?? 0) - 0.5) < 1e-9)
    }

    @Test func fomaMultipliers() throws {
        let foma100 = try #require(FilmStock(id: "fomapan100"))
        #expect(foma100.reciprocity.correct(metered: 10)?.corrected == 80)
        #expect(foma100.reciprocity.correct(metered: 0.5)?.basis == .noCorrection)
    }

    @Test func customStocksRoundTripThroughTheirID() throws {
        let custom = try #require(FilmStock.custom(name: "Lab: Special", iso: 320, process: .blackAndWhite, exponent: 1.3))
        #expect(custom.isCustom)
        let decoded = try #require(FilmStock(id: custom.id))
        #expect(decoded.name == "Lab: Special")
        #expect(decoded.iso == 320)
        #expect(decoded.process == .blackAndWhite)
        #expect(decoded.reciprocity == .powerLaw(exponent: 1.3, from: 1))
        let plain = try #require(FilmStock.custom(name: "", iso: 200, process: .c41))
        #expect(plain.reciprocity == .unpublished)
        #expect(plain.name == "ISO 200 C-41")
        #expect(FilmStock.custom(name: "Bad", iso: 0, process: .c41) == nil)
        #expect(FilmStock.custom(name: "Bad", iso: 100, process: .c41, exponent: 9) == nil)
        #expect(FilmStock(id: "custom:abc") == nil)
        #expect(FilmStock(id: "") == nil)
    }
}
