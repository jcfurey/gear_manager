//
//  CalculatorToolViews.swift
//  ShutterManager
//
//  Astro exposure and star trails, time-lapse, flash and print size.
//

import SwiftUI

private typealias ToolKey = Constants.UserDefaultsKeys

// MARK: - Astro

struct AstroView: View {
    @AppStorage(ToolKey.toolValuesPrefix + "astro.format") private var formatID = SensorFormat.fullFrame.id
    @AppStorage(ToolKey.toolValuesPrefix + "astro.pixelsWide") private var pixelsWide = 6000
    @AppStorage(ToolKey.toolValuesPrefix + "astro.focal") private var focalLength = 20.0
    @AppStorage(ToolKey.toolValuesPrefix + "astro.aperture") private var aperture = 2.0
    @AppStorage(ToolKey.toolValuesPrefix + "astro.trailMinutes") private var trailMinutes = 60
    @AppStorage(ToolKey.toolValuesPrefix + "astro.frameSeconds") private var frameSeconds = 30.0
    @AppStorage(ToolKey.toolValuesPrefix + "astro.gapSeconds") private var gapSeconds = 1.0

    private var format: SensorFormat { FormatPickerRow.format(for: formatID) }
    private var pixelPitch: Double? {
        AstroExposure.pixelPitch(sensorWidth: format.width, sensorHeight: format.height,
                                 pixelsWide: pixelsWide, pixelsHigh: 0)
    }

    var body: some View {
        Form {
            Section {
                FormatPickerRow(formatID: $formatID)
                CountField(title: "Image width", value: $pixelsWide, unit: "px", maximum: 100_000)
                MeasurementField(title: "Focal length", value: $focalLength, unit: "mm", maximum: 5000)
                ScaleValuePicker(title: "Aperture", scale: ExposureScale.apertures(), value: $aperture)
                CameraAndLensFill(formatID: $formatID, focalLength: $focalLength, aperture: $aperture) { camera in
                    let longSide = max(camera.resolutionWidthPx, camera.resolutionHeightPx)
                    if longSide > 0 { pixelsWide = longSide }
                }
            } header: {
                Text("Camera and Lens")
            } footer: {
                if let pixelPitch {
                    Text("Pixel pitch \(ExposureScale.decimal(pixelPitch, places: 2)) µm.")
                }
            }

            Section {
                if let pitch = pixelPitch,
                   let npf = AstroExposure.npf(focalLength: focalLength, aperture: aperture, pixelPitchMicrons: pitch) {
                    ToolResultRow(title: "NPF rule", value: ExposureScale.durationLabel(npf),
                                  detail: "Set \(ExposureScale.shutterLabel(Self.settable(npf))) or shorter")
                }
                if let rule500 = AstroExposure.rule500(focalLength: focalLength, cropFactor: format.cropFactor) {
                    ToolResultRow(title: "500 rule", value: ExposureScale.durationLabel(rule500), emphasized: false)
                }
            } header: {
                Text("Longest Exposure Without Trails")
            } footer: {
                Text("For a fixed tripod. The NPF rule accounts for pixel size and is the safer choice on modern sensors; the 500 rule suits film and lower-resolution sensors.")
            }

            Section {
                CountField(title: "Total time", value: $trailMinutes, unit: "min", maximum: 24 * 60)
                MeasurementField(title: "Each frame", value: $frameSeconds, unit: "s", maximum: 3600)
                MeasurementField(title: "Gap between frames", value: $gapSeconds, unit: "s", maximum: 600)
                let total = Double(trailMinutes) * 60
                ToolResultRow(title: "Frames", value: "\(StarTrails.frames(totalSeconds: total, exposure: frameSeconds, gap: gapSeconds))")
                ToolResultRow(title: "Rotation", value: "\(ExposureScale.decimal(StarTrails.rotation(seconds: total), places: 1))°",
                              detail: "The sky turns about 15° an hour around the pole", emphasized: false)
            } header: {
                Text("Star Trails")
            } footer: {
                Text("Stack the frames for one long trail; keep the gap short so the trails don't break.")
            }
        }
        .navigationTitle(Tool.astro.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The longest marked shutter speed that doesn't exceed `limit`.
    static func settable(_ limit: Double) -> Double {
        ExposureScale.shutterSpeeds().filter { $0.value <= limit * 1.0001 }.map(\.value).max() ?? limit
    }
}

// MARK: - Time-lapse

struct TimeLapseView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case fromInterval = "From Interval", forClip = "For a Clip Length"
        var id: String { rawValue }
    }

    @AppStorage(ToolKey.toolValuesPrefix + "timelapse.mode") private var mode = Mode.fromInterval
    @AppStorage(ToolKey.toolValuesPrefix + "timelapse.eventHours") private var eventHours = 1
    @AppStorage(ToolKey.toolValuesPrefix + "timelapse.eventMinutes") private var eventMinutes = 0
    @AppStorage(ToolKey.toolValuesPrefix + "timelapse.interval") private var interval = 5.0
    @AppStorage(ToolKey.toolValuesPrefix + "timelapse.clipSeconds") private var clipSeconds = 20.0
    @AppStorage(ToolKey.toolValuesPrefix + "timelapse.fps") private var framesPerSecond = 24.0
    @AppStorage(ToolKey.toolValuesPrefix + "timelapse.fileMB") private var fileSizeMB = 25.0

    private var eventSeconds: Double { Double(eventHours * 3600 + eventMinutes * 60) }
    private var effectiveInterval: Double? {
        mode == .fromInterval ? interval
            : TimeLapsePlan.interval(eventDuration: eventSeconds, clipDuration: clipSeconds, framesPerSecond: framesPerSecond)
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                CountField(title: "Event hours", value: $eventHours, unit: "h", maximum: 240)
                CountField(title: "Event minutes", value: $eventMinutes, unit: "min", maximum: 59)
                if mode == .fromInterval {
                    MeasurementField(title: "Interval", value: $interval, unit: "s", maximum: 86_400)
                } else {
                    MeasurementField(title: "Clip length", value: $clipSeconds, unit: "s", maximum: 86_400)
                }
                Picker("Frame rate", selection: $framesPerSecond) {
                    ForEach([24.0, 25, 30, 50, 60], id: \.self) { Text("\(Int($0)) fps").tag($0) }
                }
                MeasurementField(title: "File size", value: $fileSizeMB, unit: "MB", maximum: 10_000)
            }

            if let interval = effectiveInterval,
               let plan = TimeLapsePlan(eventDuration: eventSeconds, interval: interval, framesPerSecond: framesPerSecond) {
                Section {
                    if mode == .forClip {
                        ToolResultRow(title: "Interval", value: ExposureScale.durationLabel(interval))
                    }
                    ToolResultRow(title: "Frames", value: "\(plan.frames)")
                    ToolResultRow(title: "Clip length", value: ExposureScale.durationLabel(plan.clipDuration))
                    ToolResultRow(title: "Speed-up", value: "\(ExposureScale.decimal(plan.speedUp, places: 0))×", emphasized: false)
                    ToolResultRow(title: "Card space", value: Self.storage(plan.storage(fileSize: fileSizeMB)), emphasized: false)
                } header: {
                    Text("Result")
                } footer: {
                    Text("Keep each exposure under \(ExposureScale.durationLabel(max(interval - 0.5, 0))) so the camera can write the file before the next frame.")
                }
            }
        }
        .navigationTitle(Tool.timeLapse.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func storage(_ megabytes: Double) -> String {
        megabytes >= 1000 ? "\(ExposureScale.decimal(megabytes / 1000, places: 1)) GB" : "\(Int(megabytes.rounded())) MB"
    }
}

// MARK: - Flash

struct FlashView: View {
    enum Solve: String, CaseIterable, Identifiable {
        case distance = "Distance", aperture = "Aperture"
        var id: String { rawValue }
    }

    @AppStorage(ToolKey.toolValuesPrefix + "flash.guideNumber") private var guideNumber = 40.0
    @AppStorage(ToolKey.toolValuesPrefix + "flash.iso") private var iso = 100.0
    @AppStorage(ToolKey.toolValuesPrefix + "flash.power") private var power = 1.0
    @AppStorage(ToolKey.toolValuesPrefix + "flash.solve") private var solve = Solve.distance
    @AppStorage(ToolKey.toolValuesPrefix + "flash.aperture") private var aperture = 8.0
    /// Millimetres.
    @AppStorage(ToolKey.toolValuesPrefix + "flash.distance") private var distance = 3000.0

    private var effectiveGN: Double { FlashExposure.guideNumber(guideNumber, atPower: power) }

    var body: some View {
        UnitsReader { units in
            Form {
                Section {
                    MeasurementField(title: "Guide number", value: $guideNumber, unit: "m", maximum: 1000)
                        .accessibilityIdentifier("flash.guideNumber")
                    GearFillMenu(title: "Use a Flash from Inventory", systemImage: "bolt", categories: [.lighting],
                                 include: { $0.guideNumber > 0 }) { item in
                        guideNumber = item.guideNumber
                    }
                    Picker("Power", selection: $power) {
                        ForEach(FlashExposure.powerLevels.indices, id: \.self) { index in
                            Text(FlashExposure.powerLevels[index].label).tag(FlashExposure.powerLevels[index].fraction)
                        }
                    }
                    ScaleValuePicker(title: "ISO", scale: ExposureScale.isoSpeeds(), value: $iso)
                } header: {
                    Text("Flash")
                } footer: {
                    Text("Guide numbers are in metres at ISO 100, as makers quote them.")
                }

                Section("Find") {
                    Picker("Find", selection: $solve) {
                        ForEach(Solve.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if solve == .distance {
                        ScaleValuePicker(title: "Aperture", scale: ExposureScale.apertures(), value: $aperture)
                        if let metres = FlashExposure.distance(guideNumber: effectiveGN, aperture: aperture, iso: iso) {
                            ToolResultRow(title: "Subject distance", value: units.format(millimetres: metres * 1000))
                        }
                    } else {
                        DistanceField(title: "Subject distance", millimetres: $distance, units: units)
                        if let fNumber = FlashExposure.aperture(guideNumber: effectiveGN, distance: distance / 1000, iso: iso) {
                            ToolResultRow(title: "Aperture", value: ExposureScale.apertureLabel(fNumber))
                        }
                    }
                }
            }
        }
        .navigationTitle(Tool.flash.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Print size

struct PrintSizeView: View {
    @AppStorage(ToolKey.toolValuesPrefix + "print.width") private var pixelsWide = 6000
    @AppStorage(ToolKey.toolValuesPrefix + "print.height") private var pixelsHigh = 4000
    @AppStorage(ToolKey.toolValuesPrefix + "print.dpi") private var dpi = 300.0

    var body: some View {
        UnitsReader { units in
            Form {
                Section {
                    CountField(title: "Width", value: $pixelsWide, unit: "px", maximum: 100_000)
                    CountField(title: "Height", value: $pixelsHigh, unit: "px", maximum: 100_000)
                    GearFillMenu(title: "Use a Camera from Inventory", systemImage: "camera",
                                 categories: [.cameraBody, .drone], include: { $0.resolutionWidthPx > 0 }) { item in
                        pixelsWide = item.resolutionWidthPx
                        pixelsHigh = item.resolutionHeightPx
                    }
                } header: {
                    Text("Image")
                } footer: {
                    let megapixels = Double(pixelsWide * pixelsHigh) / 1_000_000
                    Text("\(ExposureScale.decimal(megapixels, places: 1)) megapixels")
                }

                Section("At a Resolution") {
                    Picker("Resolution", selection: $dpi) {
                        ForEach([150.0, 200, 240, 300, 360], id: \.self) { Text("\(Int($0)) dpi").tag($0) }
                    }
                    if let width = PrintSize.inches(pixels: pixelsWide, dpi: dpi),
                       let height = PrintSize.inches(pixels: pixelsHigh, dpi: dpi) {
                        ToolResultRow(title: "Print size", value: Self.size(width, height, metric: units.metric))
                    }
                }

                Section {
                    ForEach(PrintSize.papers) { paper in
                        if let fill = PrintSize.fillDPI(pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, paper: paper) {
                            let quality = PrintSize.Quality(dpi: fill)
                            ToolResultRow(title: paper.name, value: "\(Int(fill.rounded())) dpi",
                                          detail: quality.displayName, emphasized: false)
                        }
                    }
                } header: {
                    Text("Paper Sizes")
                } footer: {
                    Text("The resolution when the image fills the paper, cropped to fit. 300 dpi holds up to close viewing; large prints seen from further away need less.")
                }
            }
        }
        .navigationTitle(Tool.printSize.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func size(_ width: Double, _ height: Double, metric: Bool) -> String {
        if metric {
            let cm = { ExposureScale.decimal($0 * PrintSize.millimetresPerInch / 10, places: 1) }
            return "\(cm(width)) × \(cm(height)) cm"
        }
        return "\(ExposureScale.decimal(width, places: 1)) × \(ExposureScale.decimal(height, places: 1)) in"
    }
}
