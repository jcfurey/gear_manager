//
//  SkyToolViews.swift
//  ShutterManager
//
//  The sun and moon planner and the Milky Way planner. Both work out a place's sky off the main
//  thread and show times in the place's own time zone.
//

import SwiftUI
import Charts
import MapKit

private typealias ToolKey = Constants.UserDefaultsKeys

/// The device-local key for the place the sky planners share.
private let plannerPlaceKey = ToolKey.toolValuesPrefix + "sky.place"

/// A binding that reads and writes a stored place.
private func placeBinding(_ stored: Binding<String>) -> Binding<PlaceValue?> {
    Binding(get: { PlaceValue(stored: stored.wrappedValue) }, set: { stored.wrappedValue = $0?.stored ?? "" })
}

/// Times in a place's time zone.
private extension Date {
    func time(in zone: TimeZone) -> String {
        formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
    }

    func day(in zone: TimeZone) -> String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone).weekday(.abbreviated))
    }
}

private func durationText(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
}

// MARK: - Sun and moon

struct SunMoonView: View {
    @AppStorage(plannerPlaceKey) private var storedPlace = ""
    @State private var date = Date()
    @State private var day: SkyDay?
    @State private var samples: [SkySample] = []
    @State private var phases: [PhaseEvent] = []
    @State private var selectedTime: Date?

    struct PhaseEvent: Identifiable, Sendable {
        let phase: MoonPhase
        let date: Date
        var id: Date { date }
    }

    private struct Key: Hashable {
        let place: PlaceValue?
        let day: Date
    }

    var body: some View {
        let place = PlaceValue(stored: storedPlace)
        Form {
            Section {
                PlaceRow(place: placeBinding($storedPlace))
                DateStepperRow(date: $date)
            }
            if let place {
                if let day, day.observer == place.coordinate {
                    content(day, place: place)
                } else {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            } else {
                Section {
                    ContentUnavailableView("Choose a Place", systemImage: "mappin.and.ellipse",
                                           description: Text("Use your location, a saved place, or find one on the map."))
                }
            }
        }
        .navigationTitle(Tool.sunAndMoon.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Key(place: place, day: Calendar.current.startOfDay(for: date))) {
            await compute(place: place)
        }
    }

    private func compute(place: PlaceValue?) async {
        guard let place else { return }
        let date = self.date
        let result = await Task.detached(priority: .userInitiated) {
            let day = SkyDay(date: date, observer: place.coordinate, timeZone: place.timeZone)
            let samples = Sky(observer: place.coordinate).samples(in: day.interval)
            let phases = MoonPhase.upcoming(after: day.interval.start, count: 4).map { PhaseEvent(phase: $0.phase, date: $0.date) }
            return (day, samples, phases)
        }.value
        guard !Task.isCancelled else { return }
        day = result.0
        samples = result.1
        phases = result.2
        selectedTime = nil
    }

    @ViewBuilder
    private func content(_ day: SkyDay, place: PlaceValue) -> some View {
        let zone = place.timeZone
        let sky = Sky(observer: place.coordinate)
        let focus = selectedTime ?? (day.interval.contains(Date()) ? Date() : day.solarNoon)
        Section {
            SkyChart(samples: samples, day: day, selection: $selectedTime, timeZone: zone)
                .frame(height: 220)
            let sun = sky.sun(at: focus)
            let moon = sky.moon(at: focus)
            LabeledContent("At \(focus.time(in: zone))") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Sun \(Self.position(sun))")
                    Text("Moon \(Self.position(moon))")
                }
                .font(.callout.monospacedDigit())
            }
        } header: {
            Text("Altitude")
        } footer: {
            Text("Drag across the chart to see a moment. Gold and blue bands are the golden and blue hours.")
        }

        Section("Sun") {
            switch day.sunVisibility {
            case .alwaysUp: Label("The sun doesn't set today", systemImage: "sun.max")
            case .alwaysDown: Label("The sun doesn't rise today", systemImage: "moon.zzz")
            case .risesOrSets: EmptyView()
            }
            eventRow("Astronomical dawn", day.astronomicalDawn, zone)
            eventRow("Nautical dawn", day.nauticalDawn, zone)
            eventRow("Civil dawn", day.civilDawn, zone)
            eventRow("Sunrise", day.sunrise, zone, azimuth: day.sunrise.map { sky.sun(at: $0).azimuth })
            ForEach(day.goldenHours, id: \.start) { window in
                rangeRow("Golden hour", window, zone, color: .orange)
            }
            ForEach(day.blueHours, id: \.start) { window in
                rangeRow("Blue hour", window, zone, color: .blue)
            }
            eventRow("Solar noon", day.solarNoon, zone,
                     detail: "\(ExposureScale.decimal(sky.sun(at: day.solarNoon).altitude, places: 1))° high")
            eventRow("Sunset", day.sunset, zone, azimuth: day.sunset.map { sky.sun(at: $0).azimuth })
            eventRow("Civil dusk", day.civilDusk, zone)
            eventRow("Nautical dusk", day.nauticalDusk, zone)
            eventRow("Astronomical dusk", day.astronomicalDusk, zone)
        }

        Section("Moon") {
            let elongation = Sky.moonElongation(at: day.interval.start.addingTimeInterval(43_200))
            LabeledContent {
                Text("\(Int((day.moonIllumination * 100).rounded()))% lit")
            } label: {
                Label(MoonPhase.name(elongation: elongation), systemImage: MoonPhase.systemImage(elongation: elongation))
            }
            switch day.moonVisibility {
            case .alwaysUp: Text("The moon stays up all day").foregroundStyle(.secondary)
            case .alwaysDown: Text("The moon stays down all day").foregroundStyle(.secondary)
            case .risesOrSets: EmptyView()
            }
            eventRow("Moonrise", day.moonrise, zone, azimuth: day.moonrise.map { sky.moon(at: $0).azimuth })
            eventRow("Moonset", day.moonset, zone, azimuth: day.moonset.map { sky.moon(at: $0).azimuth })
        }

        Section {
            SkyDirectionsMap(place: place, sunrise: day.sunrise.map { sky.sun(at: $0).azimuth },
                             sunset: day.sunset.map { sky.sun(at: $0).azimuth },
                             sun: sky.sun(at: focus), moon: sky.moon(at: focus))
                .frame(height: 240)
                .listRowInsets(EdgeInsets())
        } header: {
            Text("Directions")
        } footer: {
            Text("Lines toward sunrise (orange), sunset (red), and the sun (yellow) and moon (grey) at \(focus.time(in: zone)) when they're up.")
        }

        Section("Moon Phases") {
            ForEach(phases) { event in
                LabeledContent {
                    Text(event.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone)))
                } label: {
                    Label(event.phase.name, systemImage: event.phase.systemImage)
                }
            }
        }
    }

    static func position(_ position: HorizontalPosition) -> String {
        "\(ExposureScale.decimal(position.altitude, places: 0))° · \(Int(position.azimuth.rounded()))° \(AngleMath.compassPoint(position.azimuth))"
    }

    @ViewBuilder
    private func eventRow(_ title: String, _ date: Date?, _ zone: TimeZone, azimuth: Double? = nil, detail: String? = nil) -> some View {
        if let date {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(date.time(in: zone)).monospacedDigit()
                    if let azimuth {
                        Text("\(Int(azimuth.rounded()))° \(AngleMath.compassPoint(azimuth))").font(.caption).foregroundStyle(.secondary)
                    } else if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } label: {
                Text(title)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func rangeRow(_ title: String, _ window: DateInterval, _ zone: TimeZone, color: Color) -> some View {
        LabeledContent {
            Text("\(window.start.time(in: zone)) – \(window.end.time(in: zone))").monospacedDigit()
        } label: {
            Label {
                Text(title)
            } icon: {
                Circle().fill(color.opacity(0.7)).frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Day-by-day navigation with a date picker in between.
struct DateStepperRow: View {
    @Binding var date: Date

    var body: some View {
        HStack {
            Button {
                date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous day")
            Spacer()
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .labelsHidden()
            Button("Today") { date = Date() }
                .buttonStyle(.borderless)
                .font(.callout)
            Spacer()
            Button {
                date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next day")
        }
    }
}

/// Sun and moon altitude through the day, with the golden and blue hours shaded.
private struct SkyChart: View {
    let samples: [SkySample]
    let day: SkyDay
    @Binding var selection: Date?
    let timeZone: TimeZone

    var body: some View {
        Chart {
            ForEach(day.goldenHours, id: \.start) { window in
                RectangleMark(xStart: .value("Start", window.start), xEnd: .value("End", window.end),
                              yStart: .value("Bottom", -90), yEnd: .value("Top", 90))
                    .foregroundStyle(Color.orange.opacity(0.18))
            }
            ForEach(day.blueHours, id: \.start) { window in
                RectangleMark(xStart: .value("Start", window.start), xEnd: .value("End", window.end),
                              yStart: .value("Bottom", -90), yEnd: .value("Top", 90))
                    .foregroundStyle(Color.blue.opacity(0.18))
            }
            RuleMark(y: .value("Horizon", 0))
                .foregroundStyle(Color.secondary.opacity(0.6))
            ForEach(samples) { sample in
                LineMark(x: .value("Time", sample.time), y: .value("Altitude", sample.sun), series: .value("Body", "Sun"))
                    .foregroundStyle(by: .value("Body", "Sun"))
                LineMark(x: .value("Time", sample.time), y: .value("Altitude", sample.moon), series: .value("Body", "Moon"))
                    .foregroundStyle(by: .value("Body", "Moon"))
            }
            if let selection {
                RuleMark(x: .value("Selected", selection))
                    .foregroundStyle(Color.primary.opacity(0.5))
            }
        }
        .chartForegroundStyleScale(["Sun": Color.orange, "Moon": Color.gray])
        .chartYScale(domain: -90...90)
        .chartYAxis {
            AxisMarks(values: [-60, -30, 0, 30, 60]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)°") }
            }
        }
        .chartXScale(domain: day.interval.start...day.interval.end)
        .chartXSelection(value: $selection)
        .environment(\.timeZone, timeZone)
        .accessibilityLabel("Sun and moon altitude through the day")
    }
}

/// The place on a map with lines toward where the sun and moon rise, set, or are now.
private struct SkyDirectionsMap: View {
    let place: PlaceValue
    let sunrise: Double?
    let sunset: Double?
    let sun: HorizontalPosition
    let moon: HorizontalPosition

    /// Long enough to read at a few kilometres' zoom.
    private let length = 3_000.0

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(place.coordinate),
                                                        latitudinalMeters: length * 2.6, longitudinalMeters: length * 2.6))) {
            Marker(place.name, coordinate: CLLocationCoordinate2D(place.coordinate))
            if let sunrise { line(sunrise, .orange) }
            if let sunset { line(sunset, .red) }
            if sun.altitude > 0 { line(sun.azimuth, .yellow) }
            if moon.altitude > 0 { line(moon.azimuth, .gray) }
        }
        .id(place)
    }

    private func line(_ azimuth: Double, _ color: Color) -> some MapContent {
        MapPolyline(coordinates: [CLLocationCoordinate2D(place.coordinate),
                                  CLLocationCoordinate2D(place.coordinate.destination(bearing: azimuth, distance: length))])
            .stroke(color, lineWidth: 4)
    }
}

// MARK: - Milky Way

struct NightSkyView: View {
    @AppStorage(plannerPlaceKey) private var storedPlace = ""
    @State private var nights: [NightSky] = []
    @State private var computedFor: PlaceValue?

    static let nightCount = 21

    var body: some View {
        let place = PlaceValue(stored: storedPlace)
        Form {
            Section {
                PlaceRow(place: placeBinding($storedPlace))
            } footer: {
                Text("Dark hours are astronomical night with the moon down. The core counts once it's 10° above the horizon.")
            }
            if let place {
                if computedFor == place {
                    Section("Coming Nights") {
                        ForEach(nights, id: \.interval.start) { night in
                            NavigationLink {
                                NightDetailView(night: night, place: place)
                            } label: {
                                NightRow(night: night, timeZone: place.timeZone)
                            }
                        }
                    }
                } else {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            } else {
                Section {
                    ContentUnavailableView("Choose a Place", systemImage: "mappin.and.ellipse",
                                           description: Text("The Milky Way's core is best seen far from city lights."))
                }
            }
        }
        .navigationTitle(Tool.nightSky.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: place) {
            guard let place else { return }
            let count = Self.nightCount
            let result = await Task.detached(priority: .userInitiated) {
                (0..<count).map { offset in
                    NightSky(evening: Date().addingTimeInterval(Double(offset) * 86_400),
                             observer: place.coordinate, timeZone: place.timeZone)
                }
            }.value
            guard !Task.isCancelled else { return }
            nights = result
            computedFor = place
        }
    }
}

private struct NightRow: View {
    let night: NightSky
    let timeZone: TimeZone

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(night.interval.start.day(in: timeZone))
                if let first = night.coreVisible.first, let last = night.coreVisible.last {
                    Text("Core \(first.start.time(in: timeZone)) – \(last.end.time(in: timeZone)) · \(durationText(night.coreHours))")
                        .font(.caption).foregroundStyle(.secondary)
                } else if night.darkness.isEmpty {
                    Text("No astronomical night").font(.caption).foregroundStyle(.secondary)
                } else if night.darkAndMoonless.isEmpty {
                    Text("The moon is up all night").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Dark \(durationText(night.moonlessDarkHours)), core below 10°").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Label("\(Int((night.moonIllumination * 100).rounded()))%", systemImage: "moon")
                .font(.caption).foregroundStyle(.secondary)
            if night.coreHours > 0 {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Core visible")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NightDetailView: View {
    let night: NightSky
    let place: PlaceValue
    @State private var samples: [SkySample] = []

    var body: some View {
        let zone = place.timeZone
        Form {
            Section {
                Chart {
                    ForEach(night.darkAndMoonless, id: \.start) { window in
                        RectangleMark(xStart: .value("Start", window.start), xEnd: .value("End", window.end),
                                      yStart: .value("Bottom", -90), yEnd: .value("Top", 90))
                            .foregroundStyle(Color.indigo.opacity(0.2))
                    }
                    RuleMark(y: .value("Horizon", 0)).foregroundStyle(Color.secondary.opacity(0.6))
                    ForEach(samples) { sample in
                        LineMark(x: .value("Time", sample.time), y: .value("Altitude", sample.galacticCenter),
                                 series: .value("Body", "Core"))
                            .foregroundStyle(by: .value("Body", "Core"))
                        LineMark(x: .value("Time", sample.time), y: .value("Altitude", sample.moon),
                                 series: .value("Body", "Moon"))
                            .foregroundStyle(by: .value("Body", "Moon"))
                        LineMark(x: .value("Time", sample.time), y: .value("Altitude", sample.sun),
                                 series: .value("Body", "Sun"))
                            .foregroundStyle(by: .value("Body", "Sun"))
                    }
                }
                .chartForegroundStyleScale(["Core": Color.purple, "Moon": Color.gray, "Sun": Color.orange])
                .chartYScale(domain: -90...90)
                .chartXScale(domain: night.interval.start...night.interval.end)
                .environment(\.timeZone, zone)
                .frame(height: 220)
                .accessibilityLabel("Galactic core, moon and sun altitude through the night")
            } footer: {
                Text("Shaded: dark hours with the moon down.")
            }

            Section("Windows") {
                if night.coreVisible.isEmpty {
                    Text("No moonless dark time with the core 10° up.").foregroundStyle(.secondary)
                }
                ForEach(night.coreVisible, id: \.start) { window in
                    LabeledContent("Core up, dark, no moon",
                                   value: "\(window.start.time(in: zone)) – \(window.end.time(in: zone))")
                }
                ForEach(night.darkAndMoonless, id: \.start) { window in
                    LabeledContent("Dark, no moon", value: "\(window.start.time(in: zone)) – \(window.end.time(in: zone))")
                }
                ForEach(night.darkness, id: \.start) { window in
                    LabeledContent("Astronomical night", value: "\(window.start.time(in: zone)) – \(window.end.time(in: zone))")
                }
                if let best = night.coreBestAltitude {
                    LabeledContent("Core reaches", value: "\(Int(best.rounded()))°")
                }
                LabeledContent("Moon", value: "\(Int((night.moonIllumination * 100).rounded()))% lit")
            }
        }
        .navigationTitle(night.interval.start.day(in: zone))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let interval = night.interval, coordinate = place.coordinate
            samples = await Task.detached { Sky(observer: coordinate).samples(in: interval, step: 900) }.value
        }
    }
}
