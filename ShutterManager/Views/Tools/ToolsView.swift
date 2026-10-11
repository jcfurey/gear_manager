//
//  ToolsView.swift
//  ShutterManager
//
//  The Tools tab: photography calculators grouped by what they're for, with any running timer
//  at the top.
//

import SwiftUI

/// Every calculator, in the order the Tools tab lists them.
enum Tool: String, CaseIterable, Identifiable, Hashable {
    case equivalentExposure, ndFilter, sunnySixteen
    case depthOfField, fieldOfView
    case sunAndMoon, nightSky, astro
    case timeLapse, flash, printSize
    case reciprocity, development

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case exposure = "Exposure"
        case optics = "Optics"
        case sky = "Sky"
        case calculators = "Calculators"
        case film = "Film"
    }

    var group: Group {
        switch self {
        case .equivalentExposure, .ndFilter, .sunnySixteen: return .exposure
        case .depthOfField, .fieldOfView: return .optics
        case .sunAndMoon, .nightSky, .astro: return .sky
        case .timeLapse, .flash, .printSize: return .calculators
        case .reciprocity, .development: return .film
        }
    }

    var title: String {
        switch self {
        case .equivalentExposure: return "Equivalent Exposure"
        case .ndFilter: return "ND Filter"
        case .sunnySixteen: return "Sunny 16"
        case .depthOfField: return "Depth of Field"
        case .fieldOfView: return "Field of View"
        case .sunAndMoon: return "Sun & Moon"
        case .nightSky: return "Milky Way"
        case .astro: return "Astro Exposure"
        case .timeLapse: return "Time-Lapse"
        case .flash: return "Flash"
        case .printSize: return "Print Size"
        case .reciprocity: return "Reciprocity"
        case .development: return "Development Timer"
        }
    }

    var subtitle: String {
        switch self {
        case .equivalentExposure: return "Trade aperture, shutter and ISO"
        case .ndFilter: return "Long exposures, with a bulb timer"
        case .sunnySixteen: return "Expose without a meter"
        case .depthOfField: return "Near and far limits, hyperfocal distance"
        case .fieldOfView: return "Angle of view and crop equivalents"
        case .sunAndMoon: return "Golden and blue hours, twilight, moon phases"
        case .nightSky: return "Dark, moonless nights with the core up"
        case .astro: return "Sharp stars (NPF and 500 rules), star trails"
        case .timeLapse: return "Interval, frames, clip length and storage"
        case .flash: return "Guide number, distance and aperture"
        case .printSize: return "Print sizes and resolution"
        case .reciprocity: return "Long-exposure correction for film"
        case .development: return "Your recipes, step by step"
        }
    }

    var systemImage: String {
        switch self {
        case .equivalentExposure: return "plusminus.circle"
        case .ndFilter: return "circle.lefthalf.filled"
        case .sunnySixteen: return "sun.max"
        case .depthOfField: return "camera.metering.center.weighted"
        case .fieldOfView: return "angle"
        case .sunAndMoon: return "sun.horizon"
        case .nightSky: return "moon.stars"
        case .astro: return "sparkles"
        case .timeLapse: return "timelapse"
        case .flash: return "bolt"
        case .printSize: return "printer"
        case .reciprocity: return "film"
        case .development: return "flask"
        }
    }

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .equivalentExposure: EquivalentExposureView()
        case .ndFilter: NDFilterView()
        case .sunnySixteen: SunnySixteenView()
        case .depthOfField: DepthOfFieldView()
        case .fieldOfView: FieldOfViewView()
        case .sunAndMoon: SunMoonView()
        case .nightSky: NightSkyView()
        case .astro: AstroView()
        case .timeLapse: TimeLapseView()
        case .flash: FlashView()
        case .printSize: PrintSizeView()
        case .reciprocity: ReciprocityView()
        case .development: DevelopmentRecipesView()
        }
    }
}

struct ToolsView: View {
    private let timers = ToolTimers.shared

    var body: some View {
        NavigationStack {
            List {
                if timers.hasActiveTimer {
                    Section("Running") {
                        RunningTimersSection(timers: timers)
                    }
                }
                ForEach(Tool.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(Tool.allCases.filter { $0.group == group }) { tool in
                            NavigationLink(value: tool) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tool.title)
                                        Text(tool.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: tool.systemImage).foregroundStyle(Color.accentColor)
                                }
                            }
                            .accessibilityIdentifier("tool.\(tool.rawValue)")
                        }
                    }
                }
            }
            .navigationTitle("Tools")
            .navigationDestination(for: Tool.self) { tool in
                tool.destination
            }
            .navigationDestination(for: RunningTimerDestination.self) { destination in
                switch destination {
                case .exposure: NDFilterView()
                case .development: DevelopmentTimerView()
                }
            }
        }
    }
}

enum RunningTimerDestination: Hashable {
    case exposure, development
}

/// The running exposure countdown and development step, ticking once a second.
private struct RunningTimersSection: View {
    let timers: ToolTimers

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let exposure = timers.exposure {
                NavigationLink(value: RunningTimerDestination.exposure) {
                    LabeledContent {
                        Text(exposure.isDone(at: context.date) ? "Done" : CountdownText.format(exposure.remaining(at: context.date)))
                            .monospacedDigit()
                    } label: {
                        Label(exposure.title, systemImage: "timer")
                    }
                }
            }
            if let run = timers.development {
                NavigationLink(value: RunningTimerDestination.development) {
                    LabeledContent {
                        Text(Self.status(of: run.session, at: context.date)).monospacedDigit()
                    } label: {
                        Label(run.recipeName, systemImage: "flask")
                    }
                }
            }
        }
    }

    static func status(of session: DevelopmentSession, at date: Date) -> String {
        let name = session.currentStep?.name ?? ""
        switch session.phase(at: date) {
        case .ready: return "\(name): ready"
        case let .running(remaining, _): return "\(name) \(CountdownText.format(remaining))"
        case let .paused(remaining): return "\(name) paused \(CountdownText.format(remaining))"
        case .stepComplete: return "\(name) done"
        case .finished: return "Finished"
        }
    }
}

#Preview {
    ToolsView()
        .modelContainer(PreviewModelContainer.make())
}
