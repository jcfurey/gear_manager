//
//  CloudForecastStoreTests.swift
//  ShutterManagerTests
//
//  The cloud forecasts on hand: nothing is asked for until the forecast is turned on, a place is
//  asked for to about a kilometre and no more than once an hour, and turning it off drops
//  everything. A stand-in plays Apple Weather.
//

import Foundation
import Testing
@testable import ShutterManager

@MainActor
struct CloudForecastStoreTests {
    /// Apple Weather's stand-in: answers with one cover for every hour asked for, and keeps
    /// what it was asked.
    private actor FakeWeather: CloudForecastProviding {
        struct Down: Error {}

        struct Asked: Equatable {
            let point: GeoCoordinate
            let range: DateInterval
        }

        private(set) var asked: [Asked] = []
        private(set) var creditsAsked = 0
        private var isDown = false
        private var isEmpty = false
        private var credit: CloudAttribution?
        private var isHolding = false
        private var held: [CheckedContinuation<Void, Never>] = []

        func goDown(_ down: Bool = true) { isDown = down }
        func answerWithNothing() { isEmpty = true }
        func offer(_ credit: CloudAttribution) { self.credit = credit }

        /// Makes every answer wait for `release()`.
        func hold() { isHolding = true }

        func release() {
            isHolding = false
            held.forEach { $0.resume() }
            held = []
        }

        func hours(at point: GeoCoordinate, in range: DateInterval) async throws -> [CloudHour] {
            asked.append(Asked(point: point, range: range))
            if isHolding {
                await withCheckedContinuation { held.append($0) }
            }
            if isDown { throw Down() }
            if isEmpty { return [] }
            return (0..<240).map { CloudHour(start: range.start.addingTimeInterval(Double($0) * 3600), cover: 0.25) }
        }

        func attribution() async throws -> CloudAttribution {
            creditsAsked += 1
            guard let credit else { throw Down() }
            return credit
        }
    }

    private static let greenwich = GeoCoordinate(latitude: 51.47693, longitude: -0.00054)
    private static let sydney = GeoCoordinate(latitude: -33.8568, longitude: 151.2153)
    /// Twenty minutes past an hour.
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000 * 3600 + 1200)

    private static func makeStore(_ weather: FakeWeather, on: Bool = true) -> CloudForecastStore {
        let store = CloudForecastStore(provider: weather, defaults: TestSupport.makeDefaults())
        store.setEnabled(on)
        return store
    }

    /// Waits, briefly, for the stand-in to have been asked `count` times.
    private static func waitUntilAsked(_ weather: FakeWeather, _ count: Int) async throws {
        for _ in 0..<400 {
            if await weather.asked.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The forecast was never asked for")
    }

    // MARK: - On and off

    @Test func nothingIsAskedForUntilItIsTurnedOn() async {
        let weather = FakeWeather()
        let store = Self.makeStore(weather, on: false)
        #expect(!store.isEnabled, "Off until the user turns it on")

        await store.load(for: Self.greenwich, now: Self.now)
        #expect(await weather.asked.isEmpty, "A place leaves the device only once the forecast is on")
        #expect(store.state(for: Self.greenwich) == .idle)
        #expect(store.forecast(for: Self.greenwich) == nil)
    }

    @Test func theSwitchIsRemembered() {
        let defaults = TestSupport.makeDefaults()
        let first = CloudForecastStore(provider: FakeWeather(), defaults: defaults)
        #expect(!first.isEnabled)
        first.setEnabled(true)
        #expect(defaults.bool(forKey: Constants.UserDefaultsKeys.cloudForecastEnabled))
        #expect(CloudForecastStore(provider: FakeWeather(), defaults: defaults).isEnabled, "The next launch finds it on")

        first.setEnabled(false)
        #expect(!CloudForecastStore(provider: FakeWeather(), defaults: defaults).isEnabled)
    }

    @Test func withNowhereToKeepItTheSwitchLastsTheSession() {
        // How the UI tests run: every launch starts with the forecast off.
        let store = CloudForecastStore(provider: FakeWeather(), defaults: nil)
        #expect(!store.isEnabled)
        store.setEnabled(true)
        #expect(store.isEnabled)
    }

    @Test func theSwitchIsNotASettingThatTravels() {
        // Turning it on is agreeing to send places to Apple: a file from another device can't.
        #expect(!Constants.UserDefaultsKeys.exportableSettings.contains(Constants.UserDefaultsKeys.cloudForecastEnabled))
    }

    // MARK: - Asking

    @Test func aPlaceIsAskedForToAboutAKilometreForTenDays() async throws {
        let weather = FakeWeather()
        let store = Self.makeStore(weather)
        await store.load(for: Self.greenwich, now: Self.now)

        let asked = try #require(await weather.asked.first)
        #expect(asked.point == GeoCoordinate(latitude: 51.48, longitude: 0), "Rounded: never the exact spot")
        #expect(asked.range == CloudForecast.requestRange(from: Self.now))
        #expect(asked.range.duration == 240 * 3600)

        let forecast = try #require(store.forecast(for: Self.greenwich))
        #expect(forecast.hours.count == 240)
        #expect(forecast.fetchedAt == Self.now)
        // A spot a few hundred metres away reads the same forecast, without asking.
        #expect(store.forecast(for: GeoCoordinate(latitude: 51.4771, longitude: -0.0012)) == forecast)
        #expect(store.state(for: Self.sydney) == .idle)
    }

    @Test func aFreshForecastIsNotAskedForAgain() async {
        let weather = FakeWeather()
        let store = Self.makeStore(weather)
        await store.load(for: Self.greenwich, now: Self.now)
        await store.load(for: Self.greenwich, now: Self.now.addingTimeInterval(1800))
        #expect(await weather.asked.count == 1, "Each asking counts against the app's allowance")

        let later = Self.now.addingTimeInterval(Constants.CloudForecast.lifetime + 60)
        await store.load(for: Self.greenwich, now: later)
        #expect(await weather.asked.count == 2, "An hour on, it's asked for again")
        #expect(store.forecast(for: Self.greenwich)?.fetchedAt == later)
    }

    @Test func twoScreensWaitingShareOneAsking() async throws {
        let weather = FakeWeather()
        await weather.hold()
        let store = Self.makeStore(weather)
        let first = Task { await store.load(for: Self.greenwich, now: Self.now) }
        try await Self.waitUntilAsked(weather, 1)
        #expect(store.state(for: Self.greenwich) == .loading)
        let second = Task { await store.load(for: Self.greenwich, now: Self.now) }
        await Task.yield()

        await weather.release()
        await first.value
        await second.value
        #expect(await weather.asked.count == 1)
        #expect(store.forecast(for: Self.greenwich) != nil)
    }

    @Test func anInvalidPlaceIsNotAskedFor() async {
        let weather = FakeWeather()
        let store = Self.makeStore(weather)
        await store.load(for: GeoCoordinate(latitude: .nan, longitude: 0), now: Self.now)
        await store.load(for: GeoCoordinate(latitude: 95, longitude: 0), now: Self.now)
        #expect(await weather.asked.isEmpty)
    }

    // MARK: - When it goes wrong

    @Test func aFailureShowsAndCanBeTriedAgain() async {
        let weather = FakeWeather()
        await weather.goDown()
        let store = Self.makeStore(weather)
        await store.load(for: Self.greenwich, now: Self.now)
        #expect(store.state(for: Self.greenwich) == .failed)
        #expect(store.forecast(for: Self.greenwich) == nil)

        await weather.goDown(false)
        await store.load(for: Self.greenwich, now: Self.now)
        #expect(store.forecast(for: Self.greenwich) != nil, "Try Again asks afresh")
    }

    @Test func anAnswerWithNoHoursIsAFailure() async {
        let weather = FakeWeather()
        await weather.answerWithNothing()
        let store = Self.makeStore(weather)
        await store.load(for: Self.greenwich, now: Self.now)
        #expect(store.state(for: Self.greenwich) == .failed)
    }

    @Test func anOlderForecastOutlastsAFailedRefresh() async {
        // Out in the field with no signal, this morning's forecast beats none.
        let weather = FakeWeather()
        let store = Self.makeStore(weather)
        await store.load(for: Self.greenwich, now: Self.now)
        await weather.goDown()
        await store.load(for: Self.greenwich, now: Self.now.addingTimeInterval(3 * 3600))
        #expect(await weather.asked.count == 2)
        #expect(store.forecast(for: Self.greenwich)?.fetchedAt == Self.now, "Kept, and it says when it's from")
    }

    // MARK: - Turning it off

    @Test func turningItOffDropsEveryForecast() async {
        let weather = FakeWeather()
        let store = Self.makeStore(weather)
        await store.load(for: Self.greenwich, now: Self.now)
        await store.load(for: Self.sydney, now: Self.now)
        store.setEnabled(false)
        #expect(store.state(for: Self.greenwich) == .idle)
        #expect(store.forecast(for: Self.sydney) == nil)

        store.setEnabled(true)
        #expect(store.forecast(for: Self.greenwich) == nil, "Back on starts from nothing")
        await store.load(for: Self.greenwich, now: Self.now)
        #expect(await weather.asked.count == 3)
    }

    @Test func anAnswerThatLandsAfterItWasTurnedOffIsDropped() async throws {
        let weather = FakeWeather()
        await weather.hold()
        let store = Self.makeStore(weather)
        let loading = Task { await store.load(for: Self.greenwich, now: Self.now) }
        try await Self.waitUntilAsked(weather, 1)

        store.setEnabled(false)
        await weather.release()
        await loading.value
        #expect(store.state(for: Self.greenwich) == .idle)
        store.setEnabled(true)
        #expect(store.forecast(for: Self.greenwich) == nil, "The old answer didn't slip in")
        #expect(store.state(for: Self.greenwich) == .idle)
    }

    // MARK: - How many are kept

    @Test func onlyTheLatestPlacesAreKept() async {
        let weather = FakeWeather()
        let store = Self.makeStore(weather)
        let places = (0...Constants.CloudForecast.maximumPlaces).map { GeoCoordinate(latitude: Double($0), longitude: 10) }
        for (index, place) in places.enumerated() {
            await store.load(for: place, now: Self.now.addingTimeInterval(Double(index)))
        }
        #expect(store.forecast(for: places[0]) == nil, "The one fetched longest ago goes")
        for place in places.dropFirst() {
            #expect(store.forecast(for: place) != nil)
        }
    }

    // MARK: - Credit

    @Test func theForecastersCreditIsFetchedOnceAForecastShows() async throws {
        let weather = FakeWeather()
        let credit = CloudAttribution(legalPage: URL(string: "https://example.com/legal"),
                                      lightMark: URL(string: "https://example.com/light.png"),
                                      darkMark: URL(string: "https://example.com/dark.png"))
        await weather.offer(credit)
        let store = Self.makeStore(weather)
        #expect(store.attribution == nil)
        #expect(await weather.creditsAsked == 0, "Nothing is asked of the service before a forecast is")

        await store.load(for: Self.greenwich, now: Self.now)
        await store.waitForPendingWork()
        #expect(store.attribution == credit)

        await store.load(for: Self.sydney, now: Self.now)
        await store.waitForPendingWork()
        #expect(await weather.creditsAsked == 1)
    }

    @Test func withoutTheServicesCreditAppleWeathersStandsIn() async throws {
        let weather = FakeWeather()
        let store = Self.makeStore(weather)
        await store.load(for: Self.greenwich, now: Self.now)
        await store.waitForPendingWork()
        #expect(store.attribution == nil)

        // What the row then shows: the trademark in text, and Apple's own page of sources.
        #expect(CloudAttribution.markText.hasSuffix(" Weather"))
        #expect(CloudAttribution.markText.unicodeScalars.first?.value == 0xF8FF, "The Apple logo")
        let page = try #require(CloudAttribution.appleWeatherLegalPage)
        #expect(page.scheme == "https")
        #expect(page.host == "weatherkit.apple.com")
    }

    // MARK: - What a screen waits on

    @Test func aScreenAsksAgainWhenThePlaceOrTheSwitchChanges() {
        let store = Self.makeStore(FakeWeather(), on: false)
        let off = store.request(for: Self.greenwich)
        store.setEnabled(true)
        let on = store.request(for: Self.greenwich)
        #expect(off != on, "Turning it on sets the waiting screen asking")
        #expect(on == store.request(for: GeoCoordinate(latitude: 51.4771, longitude: -0.0012)), "The same forecast point")
        #expect(on != store.request(for: Self.sydney))
        #expect(store.request(for: nil).point == nil)
    }

    @Test func whenAForecastIsFromReadsAsATimeOrADayAndTime() {
        let now = Date()
        #expect(WeatherAttributionRow.fetchedText(now, now: now) == now.formatted(date: .omitted, time: .shortened))
        let earlier = now.addingTimeInterval(-3 * 86_400)
        #expect(WeatherAttributionRow.fetchedText(earlier, now: now) == earlier.formatted(date: .abbreviated, time: .shortened))
    }
}
