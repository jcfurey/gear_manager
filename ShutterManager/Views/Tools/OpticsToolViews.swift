//
//  OpticsToolViews.swift
//  ShutterManager
//
//  Depth of field and field of view, filled from a body and lens in the inventory.
//

import SwiftUI

private typealias ToolKey = Constants.UserDefaultsKeys

/// Fills a format, focal length and aperture from inventory: a body sets the format, a lens its
/// focal length (the short end of a zoom) and widest aperture.
struct CameraAndLensFill: View {
    @Binding var formatID: String
    @Binding var focalLength: Double
    var aperture: Binding<Double>?
    var onBody: ((GearItem) -> Void)?

    var body: some View {
        GearFillMenu(title: "Use a Camera from Inventory", systemImage: "camera",
                     categories: [.cameraBody, .drone], include: { !$0.sensorFormatID.isEmpty }) { item in
            formatID = item.sensorFormatID
            onBody?(item)
        }
        GearFillMenu(title: "Use a Lens from Inventory", systemImage: "camera.aperture", categories: [.lens],
                     include: { $0.focalLengthMin > 0 || $0.focalLengthMax > 0 }) { item in
            focalLength = item.focalLengthMin > 0 ? item.focalLengthMin : item.focalLengthMax
            if let aperture, item.maxApertureWide > 0 {
                aperture.wrappedValue = item.maxApertureWide
            }
            if formatID.isEmpty, !item.sensorFormatID.isEmpty {
                formatID = item.sensorFormatID
            }
        }
    }
}

// MARK: - Depth of field

struct DepthOfFieldView: View {
    @AppStorage(ToolKey.toolValuesPrefix + "dof.format") private var formatID = SensorFormat.fullFrame.id
    @AppStorage(ToolKey.toolValuesPrefix + "dof.focal") private var focalLength = 50.0
    @AppStorage(ToolKey.toolValuesPrefix + "dof.aperture") private var aperture = 8.0
    /// Millimetres.
    @AppStorage(ToolKey.toolValuesPrefix + "dof.distance") private var distance = 5000.0
    @AppStorage(ToolKey.depthOfFieldStandard) private var standard = CircleOfConfusionStandard.standard

    private var format: SensorFormat { FormatPickerRow.format(for: formatID) }
    private var circleOfConfusion: Double { DepthOfField.circleOfConfusion(for: format, divisor: standard.divisor) }

    var body: some View {
        UnitsReader { units in
            Form {
                Section {
                    FormatPickerRow(formatID: $formatID)
                    MeasurementField(title: "Focal length", value: $focalLength, unit: "mm", maximum: 5000)
                        .accessibilityIdentifier("dof.focalLength")
                    ScaleValuePicker(title: "Aperture", scale: ExposureScale.apertures(), value: $aperture)
                    DistanceField(title: "Focus distance", millimetres: $distance, units: units)
                        .accessibilityIdentifier("dof.distance")
                    CameraAndLensFill(formatID: $formatID, focalLength: $focalLength, aperture: $aperture)
                }

                Section {
                    if let dof = DepthOfField(focalLength: focalLength, aperture: aperture, focusDistance: distance,
                                              circleOfConfusion: circleOfConfusion) {
                        DepthOfFieldBar(dof: dof)
                            .frame(height: 44)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        ToolResultRow(title: "Near limit", value: units.format(millimetres: dof.nearLimit))
                        ToolResultRow(title: "Far limit", value: units.format(millimetres: dof.farLimit))
                        ToolResultRow(title: "Depth of field", value: units.format(millimetres: dof.total),
                                      detail: dof.farLimit.isFinite
                                      ? "\(units.format(millimetres: dof.inFront)) in front · \(units.format(millimetres: dof.behind)) behind"
                                      : "To infinity")
                        ToolResultRow(title: "Hyperfocal distance", value: units.format(millimetres: dof.hyperfocal),
                                      detail: "Focus here: sharp from \(units.format(millimetres: dof.hyperfocalNearLimit)) to infinity",
                                      emphasized: false)
                    } else {
                        Text("Focus distance must be longer than the focal length.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Sharp Zone")
                }

                Section {
                    Picker("Sharpness standard", selection: $standard) {
                        ForEach(CircleOfConfusionStandard.allCases) { Text($0.displayName).tag($0) }
                    }
                } footer: {
                    Text("Circle of confusion \(ExposureScale.decimal(circleOfConfusion * 1000, places: 1)) µm for \(format.name). \(standard.detail). Also in Settings.")
                }
            }
        }
        .navigationTitle(Tool.depthOfField.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Where the sharp zone falls, on a scale from the camera to twice the far limit (or the
/// hyperfocal distance when the far limit is infinite).
private struct DepthOfFieldBar: View {
    let dof: DepthOfField

    var body: some View {
        GeometryReader { geometry in
            let end = dof.farLimit.isFinite ? dof.farLimit * 1.5 : max(dof.hyperfocal, dof.focusDistance) * 2
            let x = { (value: Double) -> CGFloat in CGFloat(min(value / end, 1)) * geometry.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 10)
                Capsule().fill(Color.accentColor.opacity(0.6))
                    .frame(width: max(x(dof.farLimit) - x(dof.nearLimit), 4), height: 10)
                    .offset(x: x(dof.nearLimit))
                Rectangle().fill(Color.primary).frame(width: 2, height: 22)
                    .offset(x: x(dof.focusDistance) - 1)
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Field of view

struct FieldOfViewView: View {
    @AppStorage(ToolKey.toolValuesPrefix + "fov.format") private var formatID = SensorFormat.fullFrame.id
    @AppStorage(ToolKey.toolValuesPrefix + "fov.focal") private var focalLength = 35.0
    @AppStorage(ToolKey.toolValuesPrefix + "fov.compareFormat") private var compareFormatID = SensorFormat.apsC.id
    /// Millimetres.
    @AppStorage(ToolKey.toolValuesPrefix + "fov.distance") private var distance = 10_000.0

    private var format: SensorFormat { FormatPickerRow.format(for: formatID) }
    private var compareFormat: SensorFormat { FormatPickerRow.format(for: compareFormatID) }

    var body: some View {
        UnitsReader { units in
            Form {
                Section {
                    FormatPickerRow(formatID: $formatID)
                    MeasurementField(title: "Focal length", value: $focalLength, unit: "mm", maximum: 5000)
                    CameraAndLensFill(formatID: $formatID, focalLength: $focalLength)
                }

                if let fov = FieldOfView(focalLength: focalLength, format: format) {
                    Section("Angle of View") {
                        ToolResultRow(title: "Horizontal", value: degrees(fov.horizontal))
                        ToolResultRow(title: "Vertical", value: degrees(fov.vertical), emphasized: false)
                        ToolResultRow(title: "Diagonal", value: degrees(fov.diagonal), emphasized: false)
                        ToolResultRow(title: "35mm equivalent",
                                      value: "\(ExposureScale.decimal(FieldOfView.equivalentFocalLength(focalLength, cropFactor: format.cropFactor), places: 0)) mm",
                                      detail: "Crop factor \(ExposureScale.decimal(format.cropFactor, places: 2))")
                    }

                    Section {
                        DistanceField(title: "Subject distance", millimetres: $distance, units: units)
                        if let frame = FieldOfView.frameSize(focalLength: focalLength, format: format, distance: distance) {
                            ToolResultRow(title: "Frame covers",
                                          value: "\(units.format(millimetres: frame.width)) × \(units.format(millimetres: frame.height))")
                        }
                    } header: {
                        Text("At a Distance")
                    } footer: {
                        Text("The scene the frame takes in, focused at that distance.")
                    }

                    Section {
                        FormatPickerRow(formatID: $compareFormatID, title: "On")
                        ToolResultRow(title: "Same view with",
                                      value: "\(ExposureScale.decimal(FieldOfView.matchingFocalLength(focalLength, from: format, to: compareFormat), places: 1)) mm")
                    } header: {
                        Text("Another Format")
                    }
                }
            }
        }
        .navigationTitle(Tool.fieldOfView.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func degrees(_ value: Double) -> String { "\(ExposureScale.decimal(value, places: 1))°" }
}
