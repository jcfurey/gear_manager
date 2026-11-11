//
//  CloudForecastTests.swift
//  ShutterManagerTests
//
//  A forecast's hours and what they say about a window of time. Foundation-only, so it also
//  runs on Linux.
//

import Foundation
import Testing
@testable import ShutterManager

struct CloudForecastTests {
    /// The top of an hour.
    private static let base = Date(timeIntervalSinceReferenceDate: 800_000 * 3600)

    private static func hour(_ offset: Int, cover: Double, low: Double = 0, medium: Double = 0, high: Double = 0,
                             rain: Double = 0, condition: String = "") -> CloudHour {
        CloudHour(start: base.addingTimeInterval(Double(offset) * 3600), cover: cover, low: low, medium: medium, high: high,
                  precipitationChance: rain, condition: condition, symbolName: condition.isEmpty ? "" : "cloud")
    }

    private static func window(from start: Double, to end: Double) -> DateInterval {
        DateInterval(start: base.addingTimeInterval(start * 3600), end: base.addingTimeInterval(end * 3600))
    }

    private static let forecast = CloudForecast(hours: [
        hour(0, cover: 0.2, low: 0.1, high: 0.1, rain: 0.05, condition: "Mostly Clear"),
        hour(1, cover: 0.6, low: 0.2, medium: 0.3, high: 0.4, rain: 0.4, condition: "Mostly Cloudy"),
        hour(2, cover: 1.0, low: 0.9, medium: 0.5, high: 0.2, rain: 0.1, condition: "Cloudy")
    ], fetchedAt: base)

    // MARK: - Hours

    @Test func anHourHoldsItsSharesToTheSky() {
        let odd = CloudHour(start: Self.base, cover: 1.4, low: -0.2, medium: .nan, high: .infinity, precipitationChance: 2)
        #expect(odd.cover == 1)
        #expect(odd.low == 0)
        #expect(odd.medium == 0, "Not a number reads as clear, so a chart is never given a NaN")
        #expect(odd.high == 0)
        #expect(odd.precipitationChance == 1)
        #expect(odd.end == Self.base.addingTimeInterval(3600))
    }

    @Test func hoursArePutInOrderWithoutRepeats() {
        let jumbled = CloudForecast(hours: [Self.hour(2, cover: 0.3), Self.hour(0, cover: 0.1), Self.hour(2, cover: 0.9),
                                            Self.hour(1, cover: 0.2)], fetchedAt: Self.base)
        #expect(jumbled.hours.map(\.cover) == [0.1, 0.2, 0.3], "The first of two that start together is kept")
        #expect(jumbled.coverage == Self.window(from: 0, to: 3))
        #expect(CloudForecast(hours: [], fetchedAt: Self.base).coverage == nil)
    }

    @Test func theHourAtAMoment() {
        #expect(Self.forecast.hour(at: Self.base)?.cover == 0.2)
        #expect(Self.forecast.hour(at: Self.base.addingTimeInterval(3599))?.cover == 0.2)
        #expect(Self.forecast.hour(at: Self.base.addingTimeInterval(3600))?.cover == 0.6, "An hour ends where the next begins")
        #expect(Self.forecast.hour(at: Self.base.addingTimeInterval(-1)) == nil)
        #expect(Self.forecast.hour(at: Self.base.addingTimeInterval(3 * 3600)) == nil)
    }

    @Test func theHoursThatOverlapAWindow() {
        #expect(Self.forecast.hours(overlapping: Self.window(from: 0.5, to: 1.5)).map(\.cover) == [0.2, 0.6])
        #expect(Self.forecast.hours(overlapping: Self.window(from: 1, to: 2)).map(\.cover) == [0.6], "Touching isn't overlapping")
        #expect(Self.forecast.hours(overlapping: Self.window(from: 5, to: 6)).isEmpty)
    }

    // MARK: - A window's clouds

    @Test func aWindowInsideOneHourReadsThatHour() throws {
        let summary = try #require(Self.forecast.summary(for: Self.window(from: 1.25, to: 1.75)))
        #expect(abs(summary.cover - 0.6) < 1e-9)
        #expect(abs(summary.high - 0.4) < 1e-9)
        #expect(summary.condition == "Mostly Cloudy")
        #expect(summary.headline == "Mostly Cloudy · 60% cloud")
        #expect(summary.layers == "Low 20% · mid 30% · high 40%")
        #expect(summary.precipitation == "Chance of precipitation 40%")
    }

    @Test func aWindowAcrossHoursWeighsEachByItsShare() throws {
        // 15 minutes of the first hour, 45 of the second.
        let summary = try #require(Self.forecast.summary(for: Self.window(from: 0.75, to: 1.75)))
        #expect(abs(summary.cover - (0.2 * 0.25 + 0.6 * 0.75)) < 1e-9)
        #expect(abs(summary.low - (0.1 * 0.25 + 0.2 * 0.75)) < 1e-9)
        #expect(summary.precipitationChance == 0.4, "The highest chance among its hours")
        #expect(summary.condition == "Mostly Cloudy", "The words of the hour that holds most of it")
    }

    @Test func theFirstHourWinsAnEvenSplit() throws {
        let summary = try #require(Self.forecast.summary(for: Self.window(from: 0.5, to: 1.5)))
        #expect(summary.condition == "Mostly Clear")
        #expect(abs(summary.cover - 0.4) < 1e-9)
    }

    @Test func aMomentReadsItsHour() throws {
        let summary = try #require(Self.forecast.summary(for: Self.window(from: 2.5, to: 2.5)))
        #expect(summary.cover == 1)
        #expect(summary.headline == "Cloudy · 100% cloud")
        // The forecast's very first moment counts as inside it.
        #expect(Self.forecast.summary(for: Self.window(from: 0, to: 0))?.cover == 0.2)
    }

    @Test func aWindowUnderWayIsReadFromTheForecastsStart() throws {
        // It began half an hour before the forecast does; what's left is the first half hour.
        let summary = try #require(Self.forecast.summary(for: Self.window(from: -0.5, to: 0.5)))
        #expect(abs(summary.cover - 0.2) < 1e-9)
    }

    @Test func aWindowThatIsOverIsPast() {
        #expect(Self.forecast.outlook(for: Self.window(from: -2, to: -1)) == .past)
        #expect(Self.forecast.outlook(for: Self.window(from: -1, to: 0)) == .past, "It ended as the forecast began")
        #expect(Self.forecast.outlook(for: Self.window(from: -1, to: -1)) == .past)
        #expect(Self.forecast.summary(for: Self.window(from: -2, to: -1)) == nil)
    }

    @Test func aWindowPastTheForecastsEndIsTooFarAhead() {
        #expect(Self.forecast.outlook(for: Self.window(from: 5, to: 6)) == .tooFarAhead)
        #expect(Self.forecast.outlook(for: Self.window(from: 2.5, to: 3.5)) == .tooFarAhead,
                "Half known isn't known: the missing part may be the part that matters")
        #expect(Self.forecast.outlook(for: Self.window(from: 3, to: 3)) == .tooFarAhead, "The forecast's end is outside it")
        #expect(CloudForecast(hours: [], fetchedAt: Self.base).outlook(for: Self.window(from: 0, to: 1)) == .tooFarAhead)
    }

    @Test func aGapInTheHoursLeavesAWindowUnknown() {
        let gapped = CloudForecast(hours: [Self.hour(0, cover: 0.2), Self.hour(2, cover: 0.8)], fetchedAt: Self.base)
        #expect(gapped.outlook(for: Self.window(from: 0.5, to: 2.5)) == .tooFarAhead)
        #expect(gapped.summary(for: Self.window(from: 2, to: 3))?.cover == 0.8)
    }

    @Test func aSummaryWithoutWordsIsJustTheNumber() throws {
        let plain = CloudForecast(hours: [Self.hour(0, cover: 0.349)], fetchedAt: Self.base)
        let summary = try #require(plain.summary(for: Self.window(from: 0, to: 1)))
        #expect(summary.headline == "35% cloud")
    }

    // MARK: - Words and numbers

    @Test func sharesReadAsWholePercentages() {
        #expect(CloudText.percent(0) == "0%")
        #expect(CloudText.percent(0.004) == "0%")
        #expect(CloudText.percent(0.005) == "1%")
        #expect(CloudText.percent(0.995) == "100%")
        #expect(CloudText.percent(7) == "100%")
        #expect(CloudText.percent(-1) == "0%")
        #expect(CloudText.percent(.nan) == "0%")
    }

    // MARK: - Asking

    @Test func aRequestRunsFromTheTopOfTheHourForTenDays() {
        let range = CloudForecast.requestRange(from: Self.base.addingTimeInterval(1234))
        #expect(range.start == Self.base)
        #expect(range.duration == 240 * 3600)
        #expect(CloudForecast.requestRange(from: Self.base).start == Self.base)
        #expect(CloudForecast.requestRange(from: Self.base.addingTimeInterval(-1)).start == Self.base.addingTimeInterval(-3600))
    }

    @Test func aForecastGoesStale() {
        #expect(Self.forecast.isFresh(at: Self.base, lifetime: 3600))
        #expect(Self.forecast.isFresh(at: Self.base.addingTimeInterval(3599), lifetime: 3600))
        #expect(!Self.forecast.isFresh(at: Self.base.addingTimeInterval(3600), lifetime: 3600))
        #expect(!Self.forecast.isFresh(at: Self.base.addingTimeInterval(-10), lifetime: 3600), "A clock set back")
    }

    @Test func aForecastIsAskedForToAboutAKilometre() {
        let point = GeoCoordinate(latitude: 51.47693, longitude: -0.00054).forecastPoint
        #expect(point.latitude == 51.48)
        #expect(point.longitude == 0)
        let south = GeoCoordinate(latitude: -33.8568, longitude: 151.2153).forecastPoint
        #expect(abs(south.latitude - -33.86) < 1e-9)
        #expect(abs(south.longitude - 151.22) < 1e-9)
        #expect(GeoCoordinate(latitude: 89.999, longitude: 179.999).forecastPoint.isValid)
        // Two spots a few hundred metres apart ask for the same point, and share one forecast.
        #expect(GeoCoordinate(latitude: 51.4771, longitude: -0.0012).forecastPoint == point)
    }
}
