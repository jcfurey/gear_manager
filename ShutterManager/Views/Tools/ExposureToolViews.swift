//
//  ExposureToolViews.swift
//  ShutterManager
//
//  Equivalent exposure, ND filters with a bulb timer, and Sunny 16.
//

import SwiftUI
import SwiftData

private typealias ToolKey = Constants.UserDefaultsKeys

// MARK: - Equivalent exposure

struct EquivalentExposureView: View {
    enum Solve: String, CaseIterable, Identifiable {
        case shutter = "Shutter", aperture = "Aperture", iso = "ISO"
        var id: String { rawValue }
    }

    @AppStorage(ToolKey.toolValuesPrefix + "equivalent.aperture") private var aperture = 8.0
    @AppStorage(ToolKey.toolValuesPrefix + "equivalent.shutter") private var shutter = 1.0 / 256
    @AppStorage(ToolKey.toolValuesPrefix + "equivalent.iso") private var iso = 100.0
    @AppStorage(ToolKey.toolValuesPrefix + "equivalent.solve") private var solve = Solve.shutter
    @AppStorage(ToolKey.toolValuesPrefix + "equivalent.newAperture") private var newAperture = 2.0
    @AppStorage(ToolKey.toolValuesPrefix + "equivalent.newShutter") private var newShutter = 1.0 / 1024
    @AppStorage(ToolKey.toolValuesPrefix + "equivalent.newISO") private var newISO = 100.0

    private var base: ExposureSettings { ExposureSettings(aperture: aperture, shutter: shutter, iso: iso) }

    var body: some View {
        Form {
            Section {
                ScaleValuePicker(title: "Aperture", scale: ExposureScale.apertures(), value: $aperture)
                ScaleValuePicker(title: "Shutter", scale: ExposureScale.shutterSpeeds(), value: $shutter)
                ScaleValuePicker(title: "ISO", scale: ExposureScale.isoSpeeds(), value: $iso)
            } header: {
                Text("Metered Exposure")
            } footer: {
                Text("EV \(ExposureScale.decimal(base.ev100, places: 1)) at ISO 100")
            }

            Section("New Exposure") {
                Picker("Find", selection: $solve) {
                    ForEach(Solve.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("equivalent.solve")
                if solve != .aperture {
                    ScaleValuePicker(title: "Aperture", scale: ExposureScale.apertures(), value: $newAperture)
                }
                if solve != .shutter {
                    ScaleValuePicker(title: "Shutter", scale: ExposureScale.shutterSpeeds(), value: $newShutter)
                }
                if solve != .iso {
                    ScaleValuePicker(title: "ISO", scale: ExposureScale.isoSpeeds(), value: $newISO)
                }
            }

            Section("Result") {
                result
            }
        }
        .navigationTitle(Tool.equivalentExposure.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var result: some View {
        switch solve {
        case .shutter:
            let value = base.shutter(atAperture: newAperture, iso: newISO)
            ToolResultRow(title: "Shutter", value: ExposureScale.shutterLabel(value), detail: shutterDetail(value))
        case .aperture:
            let value = base.aperture(atShutter: newShutter, iso: newISO)
            ToolResultRow(title: "Aperture", value: ExposureScale.apertureLabel(value),
                          detail: value < 0.95 || value > 70 ? "Beyond the usual range of lenses" : nil)
        case .iso:
            let value = base.iso(atAperture: newAperture, shutter: newShutter)
            ToolResultRow(title: "ISO", value: ExposureScale.isoLabel(value),
                          detail: value < 6 || value > 102_400 ? "Beyond the usual range of cameras" : nil)
        }
    }

    private func shutterDetail(_ seconds: Double) -> String? {
        if seconds > 30.5 { return "Longer than 30 s: use Bulb mode" }
        if seconds < 1.0 / 8000 { return "Faster than most shutters" }
        return nil
    }
}

// MARK: - ND filter

struct NDFilterView: View {
    @AppStorage(ToolKey.toolValuesPrefix + "nd.shutter") private var shutter = 1.0 / 128
    /// The stacked filters, as their stops joined by commas ("10,3").
    @AppStorage(ToolKey.toolValuesPrefix + "nd.filters") private var filterList = "10"
    @AppStorage(ToolKey.toolValuesPrefix + "nd.film") private var filmStockID = ""

    @State private var customStops: Double = 0
    private let timers = ToolTimers.shared

    private var filters: [Double] {
        filterList.split(separator: ",").compactMap { Double($0) }.filter { $0 > 0 && $0 <= 30 }
    }

    private var totalStops: Double { filters.reduce(0, +) }
    private var filteredTime: Double { NDFilter.exposure(base: shutter, stops: totalStops) }
    private var reciprocity: ReciprocityResult? {
        FilmStock(id: filmStockID)?.reciprocity.correct(metered: filteredTime)
    }
    private var finalTime: Double { reciprocity?.corrected ?? filteredTime }

    var body: some View {
        Form {
            Section("Metered Without the Filter") {
                ScaleValuePicker(title: "Shutter", scale: ExposureScale.shutterSpeeds(), value: $shutter)
            }

            Section {
                ForEach(Array(filters.enumerated()), id: \.offset) { index, stops in
                    LabeledContent(filterName(stops), value: "\(ExposureScale.decimal(stops, places: 2)) stops")
                        .swipeActions {
                            Button("Remove", role: .destructive) { removeFilter(at: index) }
                        }
                }
                Menu {
                    ForEach(NDFilter.presets) { preset in
                        Button(preset.label) { addFilter(preset.stops) }
                    }
                } label: {
                    Label("Add a Filter", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("nd.addFilter")
                GearFillMenu(title: "Add from Inventory", systemImage: "camera.filters", categories: [.filter],
                             include: { $0.filterStops > 0 }) { item in
                    addFilter(item.filterStops)
                }
                HStack {
                    MeasurementField(title: "Other", value: $customStops, unit: "stops", maximum: 30)
                    Button("Add") {
                        addFilter(customStops)
                        customStops = 0
                    }
                    .disabled(customStops <= 0)
                    .accessibilityLabel("Add filter")
                }
            } header: {
                Text("Filters")
            } footer: {
                Text(filters.isEmpty ? "Add the filters in front of the lens. Stacked filters add their stops."
                     : "\(ExposureScale.decimal(totalStops, places: 2)) stops in all: filter factor \(Int(NDFilter.factor(stops: totalStops).rounded())).")
            }

            Section {
                FilmStockRow(stockID: $filmStockID, title: "Film (optional)")
            } footer: {
                Text("Choose a film to add its long-exposure (reciprocity) correction.")
            }

            Section("Exposure") {
                ToolResultRow(title: "With filters", value: ExposureScale.shutterLabel(filteredTime),
                              emphasized: reciprocity == nil || reciprocity?.basis == .noCorrection)
                if let reciprocity, reciprocity.basis != .noCorrection {
                    ReciprocityResultRows(result: reciprocity, stock: FilmStock(id: filmStockID))
                }
                bulbTimer
            }
        }
        .navigationTitle(Tool.ndFilter.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var bulbTimer: some View {
        if let exposure = timers.exposure {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                LabeledContent {
                    Text(exposure.isDone(at: context.date) ? "Done" : CountdownText.format(exposure.remaining(at: context.date)))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .accessibilityLabel(exposure.isDone(at: context.date) ? "Done"
                                            : CountdownText.spoken(exposure.remaining(at: context.date)))
                        .accessibilityAddTraits(.updatesFrequently)
                } label: {
                    Label("Timer", systemImage: "timer")
                }
            }
            Button("Stop Timer", role: .destructive) { timers.cancelExposure() }
                .accessibilityIdentifier("nd.stopTimer")
        } else {
            Button {
                HapticFeedbackManager.shared.buttonTap()
                timers.startExposure(seconds: finalTime, title: "\(ExposureScale.shutterLabel(finalTime)) exposure")
            } label: {
                Label("Start Bulb Timer", systemImage: "timer")
            }
            .disabled(finalTime < 1)
            .accessibilityIdentifier("nd.startTimer")
        }
    }

    private func filterName(_ stops: Double) -> String {
        NDFilter.presets.first { $0.stops == stops }.map { "\($0.factorName) (\($0.densityName))" } ?? "ND filter"
    }

    private func addFilter(_ stops: Double) {
        guard stops > 0, stops <= 30 else { return }
        filterList = (filters + [stops]).map { ExposureScale.decimal($0, places: 3) }.joined(separator: ",")
    }

    private func removeFilter(at index: Int) {
        var list = filters
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        filterList = list.map { ExposureScale.decimal($0, places: 3) }.joined(separator: ",")
    }
}

/// The corrected time and how far it can be trusted.
struct ReciprocityResultRows: View {
    let result: ReciprocityResult
    let stock: FilmStock?

    var body: some View {
        switch result.basis {
        case .noCorrection:
            ToolResultRow(title: "Exposure", value: ExposureScale.shutterLabel(result.corrected),
                          detail: "No correction needed")
        case .makerData, .extrapolated, .notRecommended:
            ToolResultRow(title: "Corrected for film", value: ExposureScale.shutterLabel(result.corrected),
                          detail: "+\(ExposureScale.decimal(result.extraStops, places: 1)) stops")
            if result.basis == .extrapolated {
                Label("Beyond the maker's figures: an estimate that continues their trend. Bracket.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(AppColors.warningText)
            } else if result.basis == .notRecommended {
                Label("The maker doesn't recommend exposures this long. This continues their trend; bracket.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(AppColors.warningText)
            }
        case .noData:
            ToolResultRow(title: "Exposure", value: ExposureScale.shutterLabel(result.corrected),
                          detail: "Uncorrected")
            Label(stock?.isCustom == true
                  ? "No reciprocity exponent was entered for this film."
                  : "The maker publishes no correction for this time. Bracket.",
                  systemImage: "info.circle")
                .font(.footnote).foregroundStyle(Color.secondary)
        }
        if let note = stock?.reciprocityNote, result.basis != .noCorrection {
            Text(note).font(.footnote).foregroundStyle(Color.secondary)
        }
    }
}

// MARK: - Sunny 16

struct SunnySixteenView: View {
    @AppStorage(ToolKey.toolValuesPrefix + "sunny.iso") private var iso = 100.0
    @AppStorage(ToolKey.toolValuesPrefix + "sunny.condition") private var condition = SunnySixteen.Condition.sunny

    private var exposure: ExposureSettings { SunnySixteen.exposure(iso: iso, condition: condition) }

    var body: some View {
        Form {
            Section {
                ScaleValuePicker(title: "ISO", scale: ExposureScale.isoSpeeds(), value: $iso)
            }
            Section("Light") {
                ForEach(SunnySixteen.Condition.allCases) { option in
                    Button {
                        HapticFeedbackManager.shared.selection()
                        condition = option
                    } label: {
                        HStack {
                            Image(systemName: option.systemImage).frame(width: 28).foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName).foregroundStyle(Color.primary)
                                Text(option.shadowHint).font(.caption).foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            if option == condition {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .accessibilityAddTraits(option == condition ? .isSelected : [])
                    .accessibilityIdentifier("sunny.\(option.rawValue)")
                }
            }
            Section {
                ToolResultRow(title: "Exposure",
                              value: "\(ExposureScale.apertureLabel(exposure.aperture)) · \(ExposureScale.shutterLabel(exposure.shutter))")
                ForEach(equivalents, id: \.aperture) { option in
                    ToolResultRow(title: ExposureScale.apertureLabel(option.aperture),
                                  value: ExposureScale.shutterLabel(option.shutter), emphasized: false)
                }
            } header: {
                Text("Exposure")
            } footer: {
                Text("The same exposure at other apertures. The rule assumes a front-lit subject in the middle of the day; meter when it matters.")
            }
        }
        .navigationTitle(Tool.sunnySixteen.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Full-stop apertures from f/2.8 to f/22 other than the rule's own.
    private var equivalents: [ExposureSettings] {
        ExposureScale.apertures(.full)
            .filter { (9...27).contains($0.thirds) }
            .filter { abs(log2($0.value / exposure.aperture)) > 0.1 }
            .map { ExposureSettings(aperture: $0.value, shutter: exposure.shutter(atAperture: $0.value, iso: iso), iso: iso) }
            .filter { $0.shutter <= 30 && $0.shutter >= 1.0 / 8000 }
    }
}
