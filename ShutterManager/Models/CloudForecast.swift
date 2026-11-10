//
//  CloudForecast.swift
//  ShutterManager
//
//  A place's cloud forecast by the hour, and what it says about a window of time (a golden hour,
//  a dark night, a shoot). Foundation-only: the numbers come from Apple Weather through
//  `CloudForecastStore`, and nothing here knows that.
//

import Foundation

/// One hour of a place's forecast. Cover is a share of the sky, from 0 (clear) to 1 (overcast).
struct CloudHour: Hashable, Sendable, Identifiable {
    static let length: TimeInterval = 3600

    /// When the hour begins.
    let start: Date
    /// All cloud, whatever its height.
    let cover: Double
    /// Cloud by height: low is the cloud nearest the ground, high the thin cloud far above.
    let low: Double
    let medium: Double
    let high: Double
    /// The chance of rain, snow or anything else falling during the hour, from 0 to 1.
    let precipitationChance: Double
    /// The hour's weather in the forecaster's own words ("Mostly Clear"); may be empty.
    let condition: String
    /// An SF Symbol for the hour's weather; may be empty.
    let symbolName: String

    var id: Date { start }
    var end: Date { start.addingTimeInterval(Self.length) }

    /// Shares are held to 0...1, and anything that isn't a number reads as 0: a forecast is
    /// someone else's data, and a chart must not be given a NaN.
    init(start: Date, cover: Double, low: Double = 0, medium: Double = 0, high: Double = 0,
         precipitationChance: Double = 0, condition: String = "", symbolName: String = "") {
        self.start = start
        self.cover = Self.share(cover)
        self.low = Self.share(low)
        self.medium = Self.share(medium)
        self.high = Self.share(high)
        self.precipitationChance = Self.share(precipitationChance)
        self.condition = condition
        self.symbolName = symbolName
    }

    private static func share(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

/// The clouds over a window of time.
struct CloudSummary: Hashable, Sendable {
    /// Each hour counted by how much of the window it holds.
    let cover: Double
    let low: Double
    let medium: Double
    let high: Double
    /// The highest chance among the window's hours.
    let precipitationChance: Double
    /// From the hour that holds most of the window.
    let condition: String
    let symbolName: String

    /// "Mostly Clear · 20% cloud", or "20% cloud" when the forecast gave no words.
    var headline: String {
        let cloud = "\(CloudText.percent(cover)) cloud"
        return condition.isEmpty ? cloud : "\(condition) · \(cloud)"
    }

    /// "Low 5% · mid 10% · high 30%".
    var layers: String {
        "Low \(CloudText.percent(low)) · mid \(CloudText.percent(medium)) · high \(CloudText.percent(high))"
    }

    /// "Chance of precipitation 40%": rain, snow or anything else that falls.
    var precipitation: String {
        "Chance of precipitation \(CloudText.percent(precipitationChance))"
    }
}

enum CloudText {
    /// A share of the sky as a whole percentage: "35%".
    static func percent(_ share: Double) -> String {
        guard share.isFinite else { return "0%" }
        return "\(Int((min(max(share, 0), 1) * 100).rounded()))%"
    }
}

/// What a forecast can say about a window of time.
enum CloudOutlook: Hashable, Sendable {
    case forecast(CloudSummary)
    /// The window is over.
    case past
    /// The window ends later than the forecast reaches.
    case tooFarAhead
}

/// A place's forecast: its hours in order, and when it was fetched.
struct CloudForecast: Hashable, Sendable {
    /// How far ahead the hourly forecast reaches: ten days.
    static let reach: TimeInterval = 240 * CloudHour.length

    let hours: [CloudHour]
    let fetchedAt: Date

    /// Puts the hours in order, keeping the first of any that start together.
    init(hours: [CloudHour], fetchedAt: Date) {
        var seen = Set<Date>()
        self.hours = hours.sorted { $0.start < $1.start }.filter { seen.insert($0.start).inserted }
        self.fetchedAt = fetchedAt
    }

    /// The hours to ask for at `now`: from the top of the current hour, as far as the forecast
    /// reaches.
    static func requestRange(from now: Date) -> DateInterval {
        let seconds = now.timeIntervalSinceReferenceDate
        let top = Date(timeIntervalSinceReferenceDate: (seconds / CloudHour.length).rounded(.down) * CloudHour.length)
        return DateInterval(start: top, duration: reach)
    }

    /// Whether the forecast is recent enough to show without asking again.
    func isFresh(at now: Date, lifetime: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age < lifetime
    }

    /// The span the hours cover; nil for a forecast with none.
    var coverage: DateInterval? {
        guard let first = hours.first, let last = hours.last else { return nil }
        return DateInterval(start: first.start, end: last.end)
    }

    /// The hour that holds `date`.
    func hour(at date: Date) -> CloudHour? {
        hours.first { $0.start <= date && date < $0.end }
    }

    /// The hours that share any time with `window`.
    func hours(overlapping window: DateInterval) -> [CloudHour] {
        hours.filter { $0.start < window.end && $0.end > window.start }
    }

    /// The clouds over `window`.
    ///
    /// A window already under way is read from the forecast's first hour on: its earlier part
    /// has gone. One that runs past the forecast's last hour gets no summary, since the part
    /// that's missing may be the part that matters.
    func outlook(for window: DateInterval) -> CloudOutlook {
        guard let coverage else { return .tooFarAhead }
        guard window.end > coverage.start || (window.duration == 0 && window.end == coverage.start) else { return .past }
        guard window.end <= coverage.end else { return .tooFarAhead }
        let start = max(window.start, coverage.start)
        guard window.end > start else {
            // A moment, not a span: the hour it falls in.
            guard let moment = hour(at: start) else { return .tooFarAhead }
            return .forecast(CloudSummary(cover: moment.cover, low: moment.low, medium: moment.medium, high: moment.high,
                                          precipitationChance: moment.precipitationChance,
                                          condition: moment.condition, symbolName: moment.symbolName))
        }
        let parts = hours(overlapping: DateInterval(start: start, end: window.end)).map { each in
            (hour: each, seconds: min(each.end, window.end).timeIntervalSince(max(each.start, start)))
        }
        let total = parts.reduce(0) { $0 + $1.seconds }
        // A gap in the hours leaves the window part-known: say nothing rather than guess.
        guard total > 0, window.end.timeIntervalSince(start) - total < 1 else { return .tooFarAhead }
        func mean(_ value: (CloudHour) -> Double) -> Double {
            parts.reduce(0) { $0 + value($1.hour) * $1.seconds } / total
        }
        // `max(by:)` keeps the last of equals; the first hour should win a tie.
        var main = parts[0]
        for part in parts.dropFirst() where part.seconds > main.seconds { main = part }
        return .forecast(CloudSummary(cover: mean(\.cover), low: mean(\.low), medium: mean(\.medium), high: mean(\.high),
                                      precipitationChance: parts.map { $0.hour.precipitationChance }.max() ?? 0,
                                      condition: main.hour.condition, symbolName: main.hour.symbolName))
    }

    /// The summary for `window`, when there is one.
    func summary(for window: DateInterval) -> CloudSummary? {
        if case .forecast(let summary) = outlook(for: window) { return summary }
        return nil
    }
}

extension GeoCoordinate {
    /// The coordinate to two decimal places, about a kilometre. A forecast is asked for here,
    /// never for the exact spot: weather doesn't change over a kilometre, and where someone
    /// stood needn't leave the device.
    var forecastPoint: GeoCoordinate {
        // Adding zero turns a rounded "-0" into 0, so the two read as one point everywhere.
        GeoCoordinate(latitude: (latitude * 100).rounded() / 100 + 0, longitude: (longitude * 100).rounded() / 100 + 0)
    }
}
