//
//  LightMeterView.swift
//  ShutterManager
//
//  The Light Meter tab: a reflected-light reading from the camera (or typed by hand), turned
//  into an aperture, shutter time or ISO on the third-stop scales.
//

import SwiftUI
import AVFoundation
import SwiftData

private typealias ToolKey = Constants.UserDefaultsKeys

struct LightMeterView: View {
    enum Source: String, CaseIterable, Identifiable {
        case camera, manual

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .camera: return "Camera"
            case .manual: return "By Hand"
            }
        }
    }

    enum Metering: String, CaseIterable, Identifiable {
        case wholeFrame, spot

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .wholeFrame: return "Whole Frame"
            case .spot: return "Spot"
            }
        }
    }

    @StateObject private var meter = LightMeterService()
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(ToolKey.toolValuesPrefix + "meter.source") private var source = Source.camera
    @AppStorage(ToolKey.toolValuesPrefix + "meter.metering") private var metering = Metering.wholeFrame
    @AppStorage(ToolKey.toolValuesPrefix + "meter.priority") private var priority = LightMeter.Priority.aperture
    @AppStorage(ToolKey.toolValuesPrefix + "meter.aperture") private var aperture = 8.0
    @AppStorage(ToolKey.toolValuesPrefix + "meter.shutter") private var shutter = 1.0 / 128
    @AppStorage(ToolKey.toolValuesPrefix + "meter.iso") private var iso = 100.0
    @AppStorage(ToolKey.toolValuesPrefix + "meter.film") private var filmStockID = ""
    @AppStorage(ToolKey.toolValuesPrefix + "meter.filterStops") private var filterStops = 0.0
    @AppStorage(ToolKey.toolValuesPrefix + "meter.manualEV") private var manualEV = 12.0
    @AppStorage(ToolKey.toolValuesPrefix + "nd.shutter") private var ndShutter = 1.0 / 128
    @AppStorage(ToolKey.lightMeterCalibration) private var calibration = 0.0
    @Query(sort: \FilmRoll.loadedDate, order: .reverse) private var rolls: [FilmRoll]
    /// A loaded roll's rated speed, kept through the film change it causes (which would otherwise
    /// set the box speed).
    @State private var rollISO: Double?

    /// The reading frozen by Hold.
    @State private var heldEV: Double?
    /// Where the spot is, as a fraction of the preview's width and height.
    @State private var spot = CGPoint(x: 0.5, y: 0.5)
    @State private var isVisible = false
    @State private var showingCalibration = false

    /// The live reading with the calibration, or the typed EV.
    private var liveEV: Double? {
        switch source {
        case .camera: return meter.sceneEV.map { $0 + calibration }
        case .manual: return manualEV
        }
    }

    private var ev: Double? { heldEV ?? liveEV }

    private var solution: LightMeter.Solution? {
        guard let ev else { return nil }
        return LightMeter.solve(ev100: ev, priority: priority, aperture: aperture, shutter: shutter, iso: iso,
                                filterStops: filterStops)
    }

    var body: some View {
        NavigationStack {
            Form {
                if source == .camera {
                    cameraSection
                }
                readingSection
                exposureSection
                filterSection
                if let solution, solution.inRange, solution.settings.shutter <= Self.longestScaleShutter {
                    Section {
                        Button {
                            ndShutter = solution.settings.shutter
                            navigation.open(.ndFilter)
                        } label: {
                            Label("Send to ND Filter", systemImage: "circle.lefthalf.filled")
                        }
                        .accessibilityIdentifier("meter.sendToND")
                    } footer: {
                        Text("Opens the ND filter calculator with \(ExposureScale.shutterLabel(solution.settings.shutter)) as the time metered without the filter.")
                    }
                }
                if source == .camera {
                    Section {
                        LabeledContent("Calibration", value: "\(LightMeter.signedEVLabel(calibration)) EV")
                        Button("Calibrate Against Another Meter…") { showingCalibration = true }
                            .disabled(meter.status != .running)
                    } footer: {
                        Text("Phone cameras don't all read alike. If yours disagrees with a meter you trust, calibrate it here or in Settings.")
                    }
                }
            }
            .navigationTitle("Light Meter")
            .onAppear {
                isVisible = true
                updateCamera()
            }
            .onDisappear {
                isVisible = false
                updateCamera()
            }
            .onChange(of: source) {
                heldEV = nil
                updateCamera()
            }
            .onChange(of: scenePhase) { updateCamera() }
            .onChange(of: metering) { applyMetering() }
            .onChange(of: meter.status) { applyMetering() }
            .onChange(of: filmStockID) { _, id in
                if let rollISO {
                    iso = rollISO
                    self.rollISO = nil
                } else if let stock = FilmStock(id: id) {
                    iso = Double(stock.iso)
                }
            }
            .sheet(isPresented: $showingCalibration) {
                MeterCalibrationView(meter: meter, calibration: $calibration)
            }
        }
    }

    /// The most filter compensation the stepper goes to: a stack of strong NDs.
    private static let maximumFilterStops = 20.0

    /// The longest time on the shutter scale (30 s, exactly 2⁵).
    private static let longestScaleShutter = ExposureScale.shutterValue(thirds: ExposureScale.shutterRange.lowerBound)

    // MARK: - Camera

    private var cameraSection: some View {
        Section {
            if case .unavailable(let message) = meter.status {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "camera.badge.ellipsis")
                        .font(.callout)
                    HStack(spacing: 20) {
                        Button("Try Again") { meter.start() }
                        Button("Enter EV by Hand") { source = .manual }
                            .accessibilityIdentifier("meter.useManual")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            } else {
                preview
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }
            Picker("Metering", selection: $metering) {
                ForEach(Metering.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(metering == .spot ? "Tap the preview to meter that spot."
                 : "The camera meters the whole frame. Meter something mid-toned, like grass or grey stone, or hold a reading from it.")
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                MeterPreview(isRunning: meter.status == .running)
                if meter.status == .starting {
                    ProgressView().tint(.white)
                }
                if metering == .spot {
                    Circle()
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .position(x: spot.x * proxy.size.width, y: spot.y * proxy.size.height)
                        .accessibilityHidden(true)
                }
                VStack {
                    HStack {
                        if heldEV != nil { badge("HOLD") }
                        Spacer()
                        if meter.isInterrupted { badge("Camera paused") }
                    }
                    Spacer()
                }
                .padding(10)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard metering == .spot, proxy.size.width > 0, proxy.size.height > 0 else { return }
                spot = CGPoint(x: location.x / proxy.size.width, y: location.y / proxy.size.height)
                applyMetering()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Camera preview")
        .accessibilityHint(metering == .spot ? "Tap to meter a spot" : "")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
    }

    /// Runs the camera only while the meter is on screen, reading from it, and the app is open.
    private func updateCamera() {
        if isVisible, source == .camera, scenePhase != .background {
            meter.start()
        } else {
            meter.stop()
        }
    }

    private func applyMetering() {
        guard meter.status == .running else { return }
        switch metering {
        case .wholeFrame:
            meter.meter(at: nil)
        case .spot:
            let layer = CaptureSessionCoordinator.shared.previewLayer
            let point = CGPoint(x: spot.x * layer.bounds.width, y: spot.y * layer.bounds.height)
            meter.meter(at: layer.captureDevicePointConverted(fromLayerPoint: point))
        }
    }

    // MARK: - Reading

    private var readingSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ev.map { "EV \(LightMeter.evLabel($0))" } ?? "EV —")
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityIdentifier("meter.ev")
                    Text(readingDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if source == .camera {
                    Button {
                        HapticFeedbackManager.shared.selection()
                        heldEV = heldEV == nil ? liveEV : nil
                    } label: {
                        Label(heldEV == nil ? "Hold" : "Release", systemImage: heldEV == nil ? "pause.circle" : "play.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(heldEV == nil && liveEV == nil)
                    .accessibilityIdentifier("meter.hold")
                }
            }
            if source == .manual {
                Stepper(onIncrement: { manualEV = Self.stepThird(manualEV, by: 1) },
                        onDecrement: { manualEV = Self.stepThird(manualEV, by: -1) }) {
                    Text("Scene brightness")
                }
                .accessibilityIdentifier("meter.manualEV")
            }
            Picker("Reading", selection: $source) {
                ForEach(Source.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("meter.source")
        } header: {
            Text("Reading")
        } footer: {
            if source == .manual {
                Text("EV at ISO 100, in third stops. The Sunny 16 rule gives about 15 in bright sun, 13 under overcast and 11 in open shade.")
            }
        }
    }

    private var readingDetail: String {
        switch source {
        case .manual:
            return "At ISO 100, typed"
        case .camera:
            var parts = ["At ISO 100"]
            if calibration != 0 { parts.append("calibrated \(LightMeter.signedEVLabel(calibration))") }
            if heldEV == nil, let exposure = meter.exposure {
                parts.append("camera at \(ExposureScale.apertureLabel(exposure.aperture)), \(ExposureScale.shutterLabel(exposure.shutter)), \(ExposureScale.isoLabel(exposure.iso))")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// One third of a stop up or down, landing on a third.
    private static func stepThird(_ value: Double, by steps: Double) -> Double {
        let next = ((value * 3).rounded() + steps) / 3
        return min(max(next, LightMeter.evRange.lowerBound), LightMeter.evRange.upperBound)
    }

    // MARK: - Exposure

    private var exposureSection: some View {
        Section {
            Picker("Priority", selection: $priority) {
                ForEach(LightMeter.Priority.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("meter.priority")
            if priority != .shutter {
                ScaleValuePicker(title: "Aperture", scale: ExposureScale.apertures(), value: $aperture)
            }
            if priority != .aperture {
                ScaleValuePicker(title: "Shutter", scale: ExposureScale.shutterSpeeds(), value: $shutter)
            }
            if priority != .iso {
                ScaleValuePicker(title: "ISO", scale: ExposureScale.isoSpeeds(), value: $iso)
                FilmStockRow(stockID: $filmStockID, title: "Film (sets the ISO)")
                let loaded = rolls.filter(\.isLoaded)
                if !loaded.isEmpty {
                    NavigationLink {
                        LoadedRollPicker(rolls: loaded) { use($0) }
                    } label: {
                        Label("Use a Loaded Roll", systemImage: "film")
                    }
                    .accessibilityIdentifier("meter.loadedRoll")
                }
            }
            if let solution {
                ToolResultRow(title: solvedTitle, value: solvedLabel(solution), detail: solvedDetail(solution))
                    .accessibilityIdentifier("meter.result")
                if let reciprocity = reciprocity(for: solution), reciprocity.basis != .noCorrection {
                    ReciprocityResultRows(result: reciprocity, stock: FilmStock(id: filmStockID))
                }
            } else {
                Text("Waiting for a reading…").foregroundStyle(.secondary)
            }
        } header: {
            Text("Exposure")
        } footer: {
            Text("Choose two settings and the meter works out the third, in third stops.")
        }
    }

    /// Meters for a loaded roll: its film (for reciprocity) and the speed it's rated at.
    private func use(_ roll: FilmRoll) {
        HapticFeedbackManager.shared.selection()
        guard let speed = roll.meteringISO else {
            filmStockID = roll.filmStockID
            return
        }
        if roll.filmStockID != filmStockID {
            rollISO = Double(speed)
            filmStockID = roll.filmStockID
        }
        iso = Double(speed)
    }

    private var solvedTitle: String {
        switch priority {
        case .aperture: return "Shutter"
        case .shutter: return "Aperture"
        case .iso: return "ISO"
        }
    }

    private func solvedLabel(_ solution: LightMeter.Solution) -> String {
        switch priority {
        case .aperture: return ExposureScale.shutterLabel(solution.settings.shutter)
        case .shutter: return ExposureScale.apertureLabel(solution.settings.aperture)
        case .iso: return ExposureScale.isoLabel(solution.settings.iso)
        }
    }

    private func solvedDetail(_ solution: LightMeter.Solution) -> String {
        let settings = solution.settings
        let all = "\(ExposureScale.apertureLabel(settings.aperture)) · \(ExposureScale.shutterLabel(settings.shutter)) · \(ExposureScale.isoLabel(settings.iso))"
        guard !solution.inRange else { return all }
        switch priority {
        case .aperture:
            return "Faster than 1/8000: close the aperture or lower the ISO."
        case .shutter:
            return solution.exact < 1 ? "Wider than f/1: use a slower shutter or a higher ISO."
                : "Past f/64: use a faster shutter, a lower ISO or an ND filter."
        case .iso:
            return "Outside ISO 6 to 102400: change the aperture or shutter."
        }
    }

    private func reciprocity(for solution: LightMeter.Solution) -> ReciprocityResult? {
        guard priority != .iso else { return nil }
        return FilmStock(id: filmStockID)?.reciprocity.correct(metered: solution.settings.shutter)
    }

    // MARK: - Filters

    private var filterSection: some View {
        Section {
            Stepper(onIncrement: { filterStops = min(((filterStops * 3).rounded() + 1) / 3, Self.maximumFilterStops) },
                    onDecrement: { filterStops = max(((filterStops * 3).rounded() - 1) / 3, 0) }) {
                LabeledContent("Filters", value: filterStops == 0 ? "None" : "\(ExposureScale.decimal(filterStops, places: 2)) stops")
            }
            .accessibilityIdentifier("meter.filters")
            GearFillMenu(title: "Use a Filter from Inventory", systemImage: "camera.filters", categories: [.filter],
                         include: { $0.filterStops > 0 }) { item in
                filterStops = min(item.filterStops, Self.maximumFilterStops)
            }
        } header: {
            Text("Filter Compensation")
        } footer: {
            Text("Filters in front of the lens that the meter doesn't see, such as a polariser or a colour filter: use the stops their maker gives.")
        }
    }
}

/// The rolls loaded in cameras now; picking one meters for it and goes back.
private struct LoadedRollPicker: View {
    let rolls: [FilmRoll]
    let onPick: (FilmRoll) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(rolls) { roll in
            Button {
                onPick(roll)
                dismiss()
            } label: {
                FilmRollRow(roll: roll)
            }
        }
        .navigationTitle("Loaded Rolls")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shows the camera's shared preview layer, black until the meter is running.
private struct MeterPreview: UIViewRepresentable {
    let isRunning: Bool

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.attach(CaptureSessionCoordinator.shared.previewLayer)
        view.setPreviewVisible(isRunning)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // The layer is shared with the barcode scanner, which may have taken it.
        uiView.attach(CaptureSessionCoordinator.shared.previewLayer)
        uiView.setPreviewVisible(isRunning)
    }
}

/// Works out the calibration from a meter you trust reading the same scene.
private struct MeterCalibrationView: View {
    @ObservedObject var meter: LightMeterService
    @Binding var calibration: Double
    @Environment(\.dismiss) private var dismiss

    @State private var aperture = 8.0
    @State private var shutter = 1.0 / 128
    @State private var iso = 100.0

    private var trusted: Double { ExposureSettings(aperture: aperture, shutter: shutter, iso: iso).ev100 }
    private var proposed: Double? {
        meter.sceneEV.flatMap { LightMeter.calibration(trusted: trusted, measured: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Meter an evenly lit, mid-toned surface with a meter or camera you trust, and point this phone at the same surface.")
                        .font(.callout)
                }
                Section("Your Meter Reads") {
                    ScaleValuePicker(title: "Aperture", scale: ExposureScale.apertures(), value: $aperture)
                    ScaleValuePicker(title: "Shutter", scale: ExposureScale.shutterSpeeds(), value: $shutter)
                    ScaleValuePicker(title: "ISO", scale: ExposureScale.isoSpeeds(), value: $iso)
                }
                Section("Calibration") {
                    LabeledContent("Your meter", value: "EV \(LightMeter.evLabel(trusted))")
                    LabeledContent("This phone", value: meter.sceneEV.map { "EV \(LightMeter.evLabel($0))" } ?? "Waiting…")
                    ToolResultRow(title: "Calibration", value: proposed.map { "\(LightMeter.signedEVLabel($0)) EV" } ?? "—")
                }
            }
            .navigationTitle("Calibrate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let proposed { calibration = proposed }
                        dismiss()
                    }
                    .disabled(proposed == nil)
                }
            }
        }
    }
}

#Preview {
    LightMeterView()
        .modelContainer(PreviewModelContainer.make())
        .environment(AppNavigation())
}
