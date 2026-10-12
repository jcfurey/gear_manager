//
//  GearEditorSections.swift
//  ShutterManager
//
//  The gear form, shared by Add Gear and the detail screen's editor.
//

import SwiftUI

/// The editable sections of a gear item, shown for its category. Both the add form and the
/// detail editor bind this to an unmanaged draft (`GearItem.detachedCopy`), so nothing reaches
/// the library until Save or Done.
struct GearEditorSections: View {
    @Bindable var item: GearItem

    private var category: GearCategory { item.gearCategory }

    var body: some View {
        Group {
            basicSection
            if hasDetails { detailsSection }
            valueSection
            serviceSection
            if category.hasSensorCleaning { sensorCleaningSection }
            notesSection
        }
    }

    // MARK: - Basic

    private var basicSection: some View {
        Section {
            Picker("Category", selection: $item.gearCategory) {
                ForEach(GearCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.systemImage).tag(category)
                }
            }
            .accessibilityIdentifier("gearCategoryPicker")
            TextField("Make", text: optionalText(\.make))
                .accessibilityIdentifier("gearMakeField")
            TextField("Model", text: optionalText(\.model))
                .accessibilityIdentifier("gearModelField")
            TextField("Serial Number", text: optionalText(\.serialNumber))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            CountField(title: "Year Made", value: Binding(
                get: { item.manufacturingYear ?? 0 },
                set: { item.manufacturingYear = $0 > 0 ? $0 : nil }
            ), maximum: 9999)
        } header: {
            Text("Basic Info")
        } footer: {
            Text(category.examples)
        }
    }

    // MARK: - Category details

    private var hasDetails: Bool {
        category.hasMount || category.hasSensorFormat || category.hasFirmware || category.hasChargeCycles
            || [.filter, .memoryCard].contains(category)
    }

    private var detailsSection: some View {
        Section(category == .lens ? "Lens" : "Details") {
            if category.hasMount {
                MountField(mount: $item.mount)
            }
            if category.hasSensorFormat || category == .lens {
                NavigationLink {
                    SensorFormatSelectionView(formatID: $item.sensorFormatID)
                } label: {
                    LabeledContent(category == .lens ? "Made For" : "Format",
                                   value: item.sensorFormat?.name ?? "Not set")
                }
            }
            if category.hasSensorFormat {
                CountField(title: "Image Width", value: $item.resolutionWidthPx, unit: "px", maximum: 1_000_000)
                CountField(title: "Image Height", value: $item.resolutionHeightPx, unit: "px", maximum: 1_000_000)
            }
            if category == .lens {
                MeasurementField(title: "Focal Length", value: $item.focalLengthMin, unit: "mm")
                MeasurementField(title: "Zoom To", value: $item.focalLengthMax, unit: "mm")
                MeasurementField(title: "Max Aperture f/", value: $item.maxApertureWide)
                MeasurementField(title: "At Long End f/", value: $item.maxApertureTele)
                MeasurementField(title: "Minimum Focus", value: $item.minFocusDistance, unit: "m")
            }
            if category == .lens || category == .filter {
                MeasurementField(title: category == .filter ? "Size" : "Filter Thread",
                                 value: $item.filterThread, unit: "mm")
            }
            if category == .filter {
                MeasurementField(title: "ND Strength", value: $item.filterStops, unit: "stops")
            }
            if category == .lighting {
                MeasurementField(title: "Guide Number", value: $item.guideNumber, unit: "m, ISO 100")
            }
            if category.hasShutter {
                CountField(title: "Rated Shutter Life", value: $item.ratedShutterLife)
            }
            if category.hasChargeCycles {
                CountField(title: "Charge Cycles", value: $item.chargeCycles)
                CountField(title: "Rated Cycles", value: $item.ratedChargeCycles)
            }
            if category == .memoryCard {
                MeasurementField(title: "Capacity", value: $item.capacityGB, unit: "GB")
                TextField("Card Type (SD, CFexpress B…)", text: $item.cardType)
                TextField("Speed Rating (V90, UHS-II…)", text: $item.speedRating)
            }
            if category.hasFirmware {
                TextField("Firmware Version", text: $item.firmwareVersion)
                    .autocorrectionDisabled()
            }
        }
    }

    // MARK: - Value

    private var valueSection: some View {
        Section("Value") {
            MoneyField(title: "Purchase Price", value: $item.purchasePrice)
            MoneyField(title: "Current Value", value: $item.currentValue)
            // Explicit opt-in: a DatePicker can't show "no date", so bound straight to
            // `purchaseDate ?? Date()` it would display today for an item with no date.
            Toggle("Purchase Date", isOn: Binding(
                get: { item.purchaseDate != nil },
                set: { item.purchaseDate = $0 ? (item.purchaseDate ?? Date()) : nil }
            ))
            if item.purchaseDate != nil {
                DatePicker("Purchased", selection: Binding(
                    get: { item.purchaseDate ?? Date() },
                    set: { item.purchaseDate = $0 }
                ), displayedComponents: .date)
            }
        }
    }

    // MARK: - Service

    private var serviceSection: some View {
        Section("Service") {
            Toggle("Needs Service", isOn: $item.serviceNeeded)
            TextField("Service Notes", text: optionalText(\.serviceNotes), axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private var sensorCleaningSection: some View {
        Section {
            Picker("Remind Every", selection: $item.sensorCleaningIntervalDays) {
                ForEach(Constants.Maintenance.sensorCleaningIntervalOptions) { option in
                    Text(option.label).tag(option.days)
                }
                if !Constants.Maintenance.sensorCleaningIntervalOptions.contains(where: { $0.days == item.sensorCleaningIntervalDays }) {
                    Text("\(item.sensorCleaningIntervalDays) days").tag(item.sensorCleaningIntervalDays)
                }
            }
            if item.sensorCleaningIntervalDays > 0 {
                // Explicit opt-in, so the countdown never starts from a date that was only shown.
                Toggle("Set Last Cleaned", isOn: Binding(
                    get: { item.lastSensorCleaningDate != nil },
                    set: { item.lastSensorCleaningDate = $0 ? (item.lastSensorCleaningDate ?? Date()) : nil }
                ))
                if item.lastSensorCleaningDate != nil {
                    DatePicker("Last Cleaned", selection: Binding(
                        get: { item.lastSensorCleaningDate ?? Date() },
                        set: { item.lastSensorCleaningDate = $0 }
                    ), displayedComponents: .date)
                }
                ReminderTimePicker(item: item)
            }
        } header: {
            Text("Sensor Cleaning")
        } footer: {
            if item.sensorCleaningIntervalDays > 0 && item.lastSensorCleaningDate == nil {
                Text("Set a last-cleaned date to start the reminder countdown.")
            }
        }
    }

    // MARK: - Notes and links

    private var notesSection: some View {
        Section("Notes and Links") {
            TextField("Notes", text: optionalText(\.notes), axis: .vertical)
                .lineLimit(3...8)
            TextField("Links: manuals, reviews (one per line)", text: $item.referenceLinks, axis: .vertical)
                .lineLimit(2...6)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
    }

    /// Binds an optional text field so an empty field stores nil.
    private func optionalText(_ keyPath: ReferenceWritableKeyPath<GearItem, String?>) -> Binding<String> {
        Binding(
            get: { item[keyPath: keyPath] ?? "" },
            set: { item[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

/// The time of day an item's reminders fire, bound to its hour and minute.
struct ReminderTimePicker: View {
    @Bindable var item: GearItem

    var body: some View {
        DatePicker("Reminder Time", selection: Binding(
            get: {
                Calendar.current.date(bySettingHour: item.reminderHour, minute: item.reminderMinute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                item.reminderHour = components.hour ?? Constants.Maintenance.defaultReminderHour
                item.reminderMinute = components.minute ?? 0
            }
        ), displayedComponents: .hourAndMinute)
    }
}

// MARK: - Mount

/// A lens-mount text field with a menu of common mounts.
struct MountField: View {
    @Binding var mount: String

    var body: some View {
        HStack {
            TextField("Mount", text: $mount)
                .autocorrectionDisabled()
            Menu {
                ForEach(LensMount.groups) { group in
                    Section(group.title) {
                        ForEach(group.mounts, id: \.self) { name in
                            Button(name) { mount = name }
                        }
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    // A full-size touch target, not just the glyph.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Choose a mount")
        }
    }
}

// MARK: - Sensor format

/// Picks a built-in sensor or film format, or defines a custom size.
struct SensorFormatSelectionView: View {
    @Binding var formatID: String
    @Environment(\.dismiss) private var dismiss

    @State private var customName = ""
    @State private var customWidth: Double = 0
    @State private var customHeight: Double = 0

    var body: some View {
        List {
            Section {
                row(title: "Not set", detail: nil, id: "")
            }
            section("Digital", kind: .digital)
            section("Film", kind: .film)
            section("Instant", kind: .instant)
            if let current = SensorFormat(id: formatID), current.isCustom {
                Section("Custom") {
                    row(title: current.name, detail: current.sizeText, id: current.id)
                }
            }
            Section {
                TextField("Name (optional)", text: $customName)
                MeasurementField(title: "Width", value: $customWidth, unit: "mm")
                MeasurementField(title: "Height", value: $customHeight, unit: "mm")
                Button("Use Custom Size") {
                    if let format = SensorFormat.custom(name: customName, width: customWidth, height: customHeight) {
                        formatID = format.id
                        dismiss()
                    }
                }
                .disabled(SensorFormat.custom(name: customName, width: customWidth, height: customHeight) == nil)
            } header: {
                Text("Custom Size")
            } footer: {
                Text("The image area in millimetres, for a sensor or film format not listed.")
            }
        }
        .navigationTitle("Format")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, kind: SensorFormat.Kind) -> some View {
        Section(title) {
            ForEach(SensorFormat.builtIns.filter { $0.kind == kind }) { format in
                row(title: format.name, detail: cropText(format), id: format.id)
            }
        }
    }

    private func cropText(_ format: SensorFormat) -> String {
        "\(format.sizeText) · \(format.cropFactor.formatted(.number.precision(.fractionLength(2))))×"
    }

    private func row(title: String, detail: String?, id: String) -> some View {
        Button {
            formatID = id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.primary)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                if formatID == id {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .accessibilityAddTraits(formatID == id ? .isSelected : [])
    }
}
