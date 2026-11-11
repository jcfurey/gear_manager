//
//  CloudForecastViews.swift
//  ShutterManager
//
//  The rows a screen shows for a place's cloud forecast: the offer to turn it on, the wait, the
//  clouds themselves, and Apple Weather's credit, which goes wherever its numbers do.
//

import SwiftUI
import Charts

/// A stretch of the cloud chart to shade, named for VoiceOver: a golden hour, the dark hours.
struct CloudBand: Identifiable {
    let name: String
    let interval: DateInterval
    let color: Color

    var id: String { "\(name) \(interval.start.timeIntervalSinceReferenceDate)" }
}

/// A window to give the clouds for, with the title its row carries: "Golden hour · 6:10 – 6:52 PM".
struct CloudWindow: Identifiable {
    let title: String
    let interval: DateInterval

    var id: String { "\(title) \(interval.start.timeIntervalSinceReferenceDate)" }
}

// MARK: - The rows for a place

/// A place's forecast as rows for a `Section`: the offer while the forecast is off, then the
/// wait or the failure, then `content` with Apple Weather's credit under it.
///
/// The screen that shows this also asks for the forecast, with
/// `task(id: CloudForecastStore.shared.request(for:))`.
struct CloudForecastRows<Content: View>: View {
    let coordinate: GeoCoordinate
    @ViewBuilder let content: (CloudForecast) -> Content

    private let store = CloudForecastStore.shared

    var body: some View {
        if !store.isEnabled {
            Text("See how cloudy it will be, from Apple Weather. To get the forecast, this place's position is sent to Apple, rounded to about a kilometre.")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            Button("Show Cloud Forecast") {
                store.setEnabled(true)
                Task { await store.load(for: coordinate) }
            }
            .accessibilityIdentifier("showCloudForecastButton")
        } else {
            switch store.state(for: coordinate) {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Getting the forecast")
                        .foregroundStyle(Color.secondary)
                }
                .accessibilityElement(children: .combine)
            case .failed:
                Text("The forecast couldn't be loaded. Check your connection and try again.")
                    .foregroundStyle(Color.secondary)
                Button("Try Again") {
                    Task { await store.load(for: coordinate) }
                }
                .accessibilityIdentifier("retryCloudForecastButton")
            case .loaded(let forecast):
                content(forecast)
                WeatherAttributionRow(fetchedAt: forecast.fetchedAt)
            }
        }
    }
}

// MARK: - The clouds

/// What a forecast says about a stretch of time: a chart of its hours, the hour at a chosen
/// moment, and each named window's clouds. When the forecast has none of it, a line saying why.
struct CloudRows: View {
    let forecast: CloudForecast
    let timeZone: TimeZone
    /// The stretch to chart, if any: a day, a night.
    var chart: DateInterval?
    var chartName = "Cloud cover through the day"
    var bands: [CloudBand] = []
    /// A moment to give the hour's detail for.
    var focus: Date?
    var windows: [CloudWindow] = []

    private struct Row: Identifiable {
        let window: CloudWindow
        let summary: CloudSummary
        var id: String { window.id }
    }

    var body: some View {
        let hours = chart.map { forecast.hours(overlapping: $0) } ?? []
        let rows = windows.compactMap { window in
            forecast.summary(for: window.interval).map { Row(window: window, summary: $0) }
        }
        if let chart, !hours.isEmpty {
            CloudChart(hours: hours, interval: chart, bands: bands, timeZone: timeZone, name: chartName)
                .frame(height: 140)
                .accessibilityIdentifier("cloudChart")
        }
        if let focus, let moment = forecast.summary(for: DateInterval(start: focus, duration: 0)) {
            CloudSummaryRow(title: "At \(focus.time(in: timeZone))", summary: moment)
        }
        ForEach(rows) { row in
            CloudSummaryRow(title: row.window.title, summary: row.summary)
        }
        if hours.isEmpty && rows.isEmpty {
            Text(missingText)
                .foregroundStyle(Color.secondary)
        }
    }

    /// Why there's nothing to show: the time has gone, or it's further off than the forecast.
    private var missingText: String {
        if let asked = chart ?? windows.first?.interval, forecast.outlook(for: asked) == .past {
            return "That time has passed, so there's no forecast for it."
        }
        return "The forecast reaches ten days ahead. Look again nearer the day."
    }
}

/// One window's clouds: its title, the weather in words with the share of sky covered, then the
/// cloud by height and the chance of anything falling.
struct CloudSummaryRow: View {
    let title: String
    let summary: CloudSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            HStack(spacing: 6) {
                if !summary.symbolName.isEmpty {
                    Image(systemName: summary.symbolName)
                        .accessibilityHidden(true)
                }
                Text(summary.headline)
            }
            Text(summary.layers)
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Text(summary.precipitation)
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The share of sky covered, hour by hour, on the place's clock.
struct CloudChart: View {
    let hours: [CloudHour]
    let interval: DateInterval
    let bands: [CloudBand]
    let timeZone: TimeZone
    let name: String

    var body: some View {
        Chart {
            ForEach(bands) { band in
                RectangleMark(xStart: .value("Start", band.interval.start), xEnd: .value("End", band.interval.end),
                              yStart: .value("Bottom", 0), yEnd: .value("Top", 100))
                    .foregroundStyle(band.color.opacity(0.18))
                    .accessibilityLabel(band.name)
                    .accessibilityValue("\(band.interval.start.time(in: timeZone)) to \(band.interval.end.time(in: timeZone))")
            }
            ForEach(hours) { hour in
                // An hour's cover is one number for the whole hour, so it's drawn as a block,
                // cut off where the chart ends.
                RectangleMark(xStart: .value("From", max(hour.start, interval.start)),
                              xEnd: .value("To", min(hour.end, interval.end)),
                              yStart: .value("Clear", 0), yEnd: .value("Cloud", hour.cover * 100))
                    .foregroundStyle(Color.gray.opacity(0.55))
                    .accessibilityLabel(hour.start.time(in: timeZone))
                    .accessibilityValue("\(CloudText.percent(hour.cover)) cloud")
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .placeHourAxis(interval, zone: timeZone)
        .accessibilityLabel(name)
    }
}

// MARK: - Credit

/// Apple Weather's credit, which its terms ask for wherever its data shows: the Apple Weather
/// mark and the link to its other data sources. Under the mark, when the forecast was fetched.
struct WeatherAttributionRow: View {
    let fetchedAt: Date

    @Environment(\.colorScheme) private var colorScheme
    private let store = CloudForecastStore.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                mark
                Text("Forecast from \(Self.fetchedText(fetchedAt))")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            if let page = store.attribution?.legalPage ?? CloudAttribution.appleWeatherLegalPage {
                Link("Other data sources", destination: page)
                    .font(.footnote)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("weatherLegalLink")
            }
        }
    }

    /// The service's own mark for the background it's on. Until it loads, and if it can't, the
    /// trademark in text.
    @ViewBuilder
    private var mark: some View {
        if let url = (colorScheme == .dark ? store.attribution?.darkMark : store.attribution?.lightMark) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                        .accessibilityLabel(CloudAttribution.spokenName)
                } else {
                    markText
                }
            }
            .frame(height: 16)
            .accessibilityIdentifier("weatherAttribution")
        } else {
            markText
                .accessibilityIdentifier("weatherAttribution")
        }
    }

    private var markText: some View {
        Text(CloudAttribution.markText)
            .font(.footnote.weight(.semibold))
            .accessibilityLabel(CloudAttribution.spokenName)
    }

    /// The time on this device's clock, with the day when it wasn't today: an old forecast kept
    /// through a spell with no signal should say how old.
    static func fetchedText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
