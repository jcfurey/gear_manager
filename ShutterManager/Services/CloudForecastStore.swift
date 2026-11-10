//
//  CloudForecastStore.swift
//  ShutterManager
//
//  The cloud forecasts the planners and shoots show: asked for only once the user has turned
//  them on, to about a kilometre, and kept for the session only.
//

import Foundation
import Observation
import os

/// Where a forecast comes from. The app's is Apple Weather (`WeatherKitCloudProvider`); tests and
/// the UI tests stand in their own.
protocol CloudForecastProviding: Sendable {
    /// The forecast's hours at `point` within `range`.
    func hours(at point: GeoCoordinate, in range: DateInterval) async throws -> [CloudHour]
    /// Whose forecast it is, to credit beside it.
    func attribution() async throws -> CloudAttribution
}

/// The credit a forecast is shown with: the forecaster's mark, and a link to its sources.
struct CloudAttribution: Hashable, Sendable {
    let legalPage: URL?
    /// The mark as an image, for a light background and for a dark one.
    let lightMark: URL?
    let darkMark: URL?

    /// The Apple Weather trademark in text: the Apple logo, then "Weather". Shown until the
    /// service's own mark has loaded, and when it can't be.
    static let markText = "\u{F8FF} Weather"
    static let spokenName = "Apple Weather"
    /// Apple Weather's page of data sources, for when the service can't be asked for its link.
    static let appleWeatherLegalPage = URL(string: "https://weatherkit.apple.com/legal-attribution.html")
}

/// The forecasts on hand, by place.
///
/// Nothing is asked for until the user turns the forecast on (`setEnabled`): asking sends the
/// place to Apple Weather. A place is asked for at `GeoCoordinate.forecastPoint`, so nearby
/// spots share one forecast, and a forecast is asked for again only once it's
/// `Constants.CloudForecast.lifetime` old. Forecasts live in memory: none is written to disk
/// or synced.
@MainActor
@Observable
final class CloudForecastStore {
    static let shared = CloudForecastStore(provider: nil, defaults: CloudForecastStore.appDefaults)

    enum State: Equatable {
        /// Not asked for: the forecast is off, or no screen has needed this place yet.
        case idle
        case loading
        case loaded(CloudForecast)
        case failed
    }

    /// Whether the user has turned the forecast on.
    private(set) var isEnabled: Bool
    /// The forecaster's own credit, once it has been fetched.
    private(set) var attribution: CloudAttribution?
    private var states: [GeoCoordinate: State] = [:]

    @ObservationIgnored private let provider: CloudForecastProviding
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var loads: [GeoCoordinate: Task<Void, Never>] = [:]
    @ObservationIgnored private var attributionLoad: Task<Void, Never>?
    /// Rises each time the forecast is turned off, so an answer still on its way from before
    /// is dropped when it lands.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let logger = Logger(subsystem: Constants.App.loggerSubsystem, category: "CloudForecast")

    /// `provider` defaults to Apple Weather. `defaults` is where the switch is kept; with none
    /// it lasts for the session.
    init(provider: CloudForecastProviding? = nil, defaults: UserDefaults? = .standard) {
        self.provider = provider ?? Self.appProvider
        self.defaults = defaults
        isEnabled = defaults?.bool(forKey: Constants.UserDefaultsKeys.cloudForecastEnabled) ?? false
    }

    /// Apple Weather, or under `-uiTestCloudSample` a fixed forecast: the UI tests' simulator
    /// isn't signed for WeatherKit, and a test mustn't depend on the weather.
    private static var appProvider: CloudForecastProviding {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestCloudSample") { return SampleCloudProvider() }
        #endif
        return WeatherKitCloudProvider()
    }

    /// The UI tests start every launch with the forecast off, and leave nothing behind.
    private static var appDefaults: UserDefaults? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestInMemory") { return nil }
        #endif
        return .standard
    }

    // MARK: - On and off

    /// Turns the forecast on or off. Off drops every forecast on hand.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults?.set(enabled, forKey: Constants.UserDefaultsKeys.cloudForecastEnabled)
        guard !enabled else { return }
        generation += 1
        loads = [:]
        states = [:]
    }

    // MARK: - Reading

    func state(for coordinate: GeoCoordinate) -> State {
        guard isEnabled else { return .idle }
        return states[coordinate.forecastPoint] ?? .idle
    }

    func forecast(for coordinate: GeoCoordinate) -> CloudForecast? {
        if case .loaded(let forecast) = state(for: coordinate) { return forecast }
        return nil
    }

    /// What a screen waits on, for `task(id:)`: it changes when the place moves to another
    /// forecast point, and when the forecast is turned on or off.
    struct Request: Hashable {
        let point: GeoCoordinate?
        let isEnabled: Bool
    }

    func request(for coordinate: GeoCoordinate?) -> Request {
        Request(point: coordinate?.forecastPoint, isEnabled: isEnabled)
    }

    // MARK: - Asking

    /// Fetches the forecast for `coordinate` unless a fresh one is on hand, or one is already on
    /// its way. Does nothing while the forecast is off.
    func load(for coordinate: GeoCoordinate, now: Date = Date()) async {
        guard isEnabled, coordinate.isValid else { return }
        let point = coordinate.forecastPoint
        let current = states[point] ?? .idle
        if case .loaded(let forecast) = current, forecast.isFresh(at: now, lifetime: Constants.CloudForecast.lifetime) {
            return
        }
        if let running = loads[point] {
            await running.value
            return
        }
        // A forecast that has only gone stale stays up while the new one comes.
        if case .loaded = current { } else { states[point] = .loading }
        let provider = self.provider
        let range = CloudForecast.requestRange(from: now)
        let asked = generation
        let task = Task { @MainActor [weak self] in
            let result: Result<[CloudHour], Error>
            do {
                result = .success(try await provider.hours(at: point, in: range))
            } catch {
                result = .failure(error)
            }
            self?.finish(point, with: result, at: now, asked: asked)
        }
        loads[point] = task
        await task.value
    }

    private func finish(_ point: GeoCoordinate, with result: Result<[CloudHour], Error>, at now: Date, asked: Int) {
        // Turned off since it was asked for: not wanted, and `loads` is no longer this task's.
        guard asked == generation else { return }
        loads[point] = nil
        switch result {
        case .success(let hours) where !hours.isEmpty:
            states[point] = .loaded(CloudForecast(hours: hours, fetchedAt: now))
            trim(keeping: point)
            loadAttribution()
        case .success:
            logger.error("The forecast came back with no hours.")
            keepOrFail(point)
        case .failure(let error):
            logger.error("The forecast could not be loaded: \(error.localizedDescription, privacy: .public)")
            keepOrFail(point)
        }
    }

    /// An older forecast is better than none, out in the field with no signal: it stays, and
    /// the screens say when it's from.
    private func keepOrFail(_ point: GeoCoordinate) {
        if case .loaded = states[point] ?? .idle { return }
        states[point] = .failed
    }

    /// Lets go of the forecasts fetched longest ago, past `Constants.CloudForecast.maximumPlaces`.
    private func trim(keeping point: GeoCoordinate) {
        var fetched: [(point: GeoCoordinate, at: Date)] = states.compactMap { entry in
            guard entry.key != point, case .loaded(let forecast) = entry.value else { return nil }
            return (entry.key, forecast.fetchedAt)
        }
        fetched.sort { $0.at < $1.at }
        let extra = fetched.count + 1 - Constants.CloudForecast.maximumPlaces
        guard extra > 0 else { return }
        for entry in fetched.prefix(extra) { states[entry.point] = nil }
    }

    /// Fetches the forecaster's credit, once. Until it comes, and if it can't, the screens show
    /// Apple Weather's in words.
    private func loadAttribution() {
        guard attribution == nil, attributionLoad == nil else { return }
        let provider = self.provider
        let asked = generation
        attributionLoad = Task { @MainActor [weak self] in
            let credit = try? await provider.attribution()
            guard let self else { return }
            self.attributionLoad = nil
            if let credit, asked == self.generation { self.attribution = credit }
        }
    }

    /// Waits for everything asked for so far. For tests.
    func waitForPendingWork() async {
        for task in Array(loads.values) { await task.value }
        await attributionLoad?.value
    }
}

#if DEBUG
/// What the UI tests see in place of Apple Weather (`-uiTestCloudSample`): cloud that builds
/// and clears twice a day, the same on every run.
struct SampleCloudProvider: CloudForecastProviding {
    struct NoCredit: Error {}

    func hours(at point: GeoCoordinate, in range: DateInterval) async throws -> [CloudHour] {
        let count = Int((range.duration / CloudHour.length).rounded(.down))
        return (0..<count).map { index in
            let cover = 0.5 + 0.4 * sin(Double(index) * .pi / 6)
            return CloudHour(start: range.start.addingTimeInterval(Double(index) * CloudHour.length), cover: cover,
                             low: cover * 0.5, medium: cover * 0.3, high: cover * 0.6, precipitationChance: cover * 0.2,
                             condition: cover < 0.5 ? "Mostly Clear" : "Mostly Cloudy",
                             symbolName: cover < 0.5 ? "cloud.sun" : "cloud")
        }
    }

    /// None of its own: the screens fall back to Apple Weather's credit in words, with no
    /// image to fetch.
    func attribution() async throws -> CloudAttribution { throw NoCredit() }
}
#endif
