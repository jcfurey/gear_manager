//
//  PhotoMetadataImportView.swift
//  ShutterManager
//
//  Review what a photo's metadata says, and fill a gear draft from it.
//

import SwiftUI

/// Shows what a photo's metadata found and fills the chosen details into `item` (an unsaved
/// draft). The user picks whether the photo describes the camera body or the lens, and which
/// found values to use; nothing is applied until they tap Use.
struct PhotoMetadataImportView: View {
    let metadata: CameraPhotoMetadata
    @Bindable var item: GearItem
    /// Called after the values are applied, with the shutter count if the user kept it, so the
    /// caller can record it as a reading.
    var onApply: (_ shutterCount: Int?) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    enum Target: String, CaseIterable, Identifiable {
        case camera = "Camera Body"
        case lens = "Lens"
        var id: String { rawValue }
    }

    @State private var target: Target
    @State private var excluded: Set<String> = []

    init(metadata: CameraPhotoMetadata, item: GearItem, onApply: @escaping (_ shutterCount: Int?) -> Void = { _ in }) {
        self.metadata = metadata
        self.item = item
        self.onApply = onApply
        // Start from what the item already is; otherwise from what the photo says most about.
        let initial: Target
        switch item.gearCategory {
        case .lens: initial = .lens
        case .cameraBody: initial = .camera
        default: initial = metadata.hasCameraDetails || !metadata.hasLensDetails ? .camera : .lens
        }
        _target = State(initialValue: initial)
    }

    /// One value the photo provided, with the label it's shown under.
    struct Finding: Identifiable {
        let id: String
        let label: String
        let value: String
        let apply: (GearItem) -> Void
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("This photo's", selection: $target) {
                        ForEach(Target.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Use the camera's details to describe a body, or the lens's details to describe a lens.")
                }

                if findings.isEmpty {
                    Section {
                        ContentUnavailableView("Nothing to Use", systemImage: "doc.text.magnifyingglass",
                            description: Text("The photo doesn't say anything about the \(target.rawValue.lowercased())."))
                    }
                } else {
                    Section {
                        ForEach(findings) { finding in
                            Toggle(isOn: Binding(
                                get: { !excluded.contains(finding.id) },
                                set: { if $0 { excluded.remove(finding.id) } else { excluded.insert(finding.id) } }
                            )) {
                                LabeledContent(finding.label, value: finding.value)
                            }
                        }
                    } header: {
                        Text("Found in the Photo")
                    } footer: {
                        if target == .camera && metadata.shutterCount == nil {
                            Text("This photo doesn't include a shutter count. Most cameras only show it in their own menus or a service report.")
                        }
                    }
                }
            }
            .navigationTitle("Fill from Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { apply() }
                        .disabled(findings.allSatisfy { excluded.contains($0.id) })
                }
            }
        }
    }

    private func apply() {
        if target == .camera, item.gearCategory != .cameraBody, item.gearCategory != .drone {
            item.gearCategory = .cameraBody
        } else if target == .lens {
            item.gearCategory = .lens
        }
        for finding in findings where !excluded.contains(finding.id) {
            finding.apply(item)
        }
        let keepsCount = target == .camera && !excluded.contains("shutterCount")
        onApply(keepsCount ? metadata.shutterCount : nil)
        HapticFeedbackManager.shared.success()
        dismiss()
    }

    /// The values the photo has for the chosen target.
    var findings: [Finding] {
        Self.findings(in: metadata, for: target)
    }

    static func findings(in metadata: CameraPhotoMetadata, for target: Target) -> [Finding] {
        var results: [Finding] = []
        func add(_ id: String, _ label: String, _ value: String?, _ apply: @escaping (GearItem) -> Void) {
            if let value { results.append(Finding(id: id, label: label, value: value, apply: apply)) }
        }
        switch target {
        case .camera:
            add("make", "Make", metadata.cameraMake) { $0.make = metadata.cameraMake }
            add("model", "Model", metadata.cameraModel) { $0.model = metadata.cameraModel }
            add("serial", "Serial Number", metadata.bodySerialNumber) { $0.serialNumber = metadata.bodySerialNumber }
            add("firmware", "Firmware", metadata.firmware) { $0.firmwareVersion = metadata.firmware ?? "" }
            if let width = metadata.pixelWidth, let height = metadata.pixelHeight {
                add("resolution", "Image Size", "\(width) × \(height) px") {
                    $0.resolutionWidthPx = width
                    $0.resolutionHeightPx = height
                }
            }
            if let count = metadata.shutterCount {
                // Recorded as a reading when the item is saved (see AddGearView), not a field.
                add("shutterCount", "Shutter Count", count.formatted()) { _ in }
            }
        case .lens:
            add("lensMake", "Make", metadata.lensMake) { $0.make = metadata.lensMake }
            add("lensModel", "Model", metadata.lensModel) { $0.model = metadata.lensModel }
            add("lensSerial", "Serial Number", metadata.lensSerialNumber) { $0.serialNumber = metadata.lensSerialNumber }
            if metadata.lensFocalLengthMin != nil || metadata.lensFocalLengthMax != nil {
                let text = GearItem.focalLengthText(min: metadata.lensFocalLengthMin ?? 0, max: metadata.lensFocalLengthMax ?? 0)
                add("focal", "Focal Length", text) {
                    $0.focalLengthMin = metadata.lensFocalLengthMin ?? 0
                    $0.focalLengthMax = metadata.lensFocalLengthMax ?? 0
                }
            }
            if metadata.lensMaxApertureWide != nil || metadata.lensMaxApertureTele != nil {
                let text = GearItem.apertureText(wide: metadata.lensMaxApertureWide ?? 0, tele: metadata.lensMaxApertureTele ?? 0)
                add("aperture", "Max Aperture", text) {
                    $0.maxApertureWide = metadata.lensMaxApertureWide ?? 0
                    $0.maxApertureTele = metadata.lensMaxApertureTele ?? 0
                }
            }
        }
        return results
    }
}
