//
//  ToolComponents.swift
//  ShutterManager
//
//  Building blocks the calculators share: scale pickers, result rows, filling values from the
//  inventory, and choosing a format or film stock.
//

import SwiftUI
import SwiftData

/// Picks a value on a standard scale (apertures, shutter speeds, ISO). The binding holds the
/// exact value; a value off the scale shows as the nearest mark.
struct ScaleValuePicker: View {
    let title: String
    let scale: [ScaleValue]
    @Binding var value: Double

    var body: some View {
        Picker(title, selection: Binding(
            get: { ExposureScale.nearest(to: value, in: scale)?.thirds ?? 0 },
            set: { thirds in
                if let mark = scale.first(where: { $0.thirds == thirds }) { value = mark.value }
            }
        )) {
            ForEach(scale) { mark in
                Text(mark.label).tag(mark.thirds)
            }
        }
    }
}

/// A calculated value, emphasized, with an optional line of detail.
struct ToolResultRow: View {
    let title: String
    let value: String
    var detail: String?
    var emphasized = true

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(emphasized ? .title3.weight(.semibold) : .body)
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Color.secondary)
                }
            }
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A menu of inventory items in some categories; picking one fills the calculator. Hidden when
/// the inventory has none.
struct GearFillMenu: View {
    let title: String
    let systemImage: String
    let categories: Set<GearCategory>
    var include: (GearItem) -> Bool = { _ in true }
    let onSelect: (GearItem) -> Void

    @Query(sort: \GearItem.dateAdded, order: .reverse) private var items: [GearItem]

    var body: some View {
        let matching = items.filter { categories.contains($0.gearCategory) && include($0) }
        if !matching.isEmpty {
            Menu {
                ForEach(matching) { item in
                    Button {
                        HapticFeedbackManager.shared.selection()
                        onSelect(item)
                    } label: {
                        if let detail = item.listSubtitle {
                            Text(item.displayName)
                            Text(detail)
                        } else {
                            Text(item.displayName)
                        }
                    }
                }
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

/// A row that opens the format list, for tools that need a sensor or film size.
struct FormatPickerRow: View {
    @Binding var formatID: String
    var title = "Format"

    var body: some View {
        NavigationLink {
            SensorFormatSelectionView(formatID: $formatID)
        } label: {
            LabeledContent(title, value: SensorFormat(id: formatID)?.name ?? SensorFormat.fullFrame.name)
        }
    }

    /// The chosen format, full frame when none is set.
    static func format(for id: String) -> SensorFormat {
        SensorFormat(id: id) ?? .fullFrame
    }
}

/// Typed distances in the user's units (metres or feet), stored in millimetres.
struct DistanceField: View {
    let title: String
    /// Millimetres.
    @Binding var millimetres: Double
    let units: MeasurementUnits

    var body: some View {
        MeasurementField(title: title, value: Binding(
            get: { units.displayDistance(millimetres: millimetres) },
            set: { millimetres = units.millimetres(fromDisplay: $0) }
        ), unit: units.distanceUnit)
    }
}

/// The user's units, from Settings.
struct UnitsReader<Content: View>: View {
    @AppStorage(Constants.UserDefaultsKeys.measurementUnits) private var preference = UnitPreference.automatic.rawValue
    @ViewBuilder let content: (MeasurementUnits) -> Content

    var body: some View {
        content(MeasurementUnits(preference: preference))
    }
}

/// Picks a film stock: the catalog grouped by maker, or a custom stock.
struct FilmStockPicker: View {
    @Binding var stockID: String
    var allowsNone = true
    @Environment(\.dismiss) private var dismiss

    @State private var customName = ""
    @State private var customISO = 400
    @State private var customProcess = FilmStock.Process.blackAndWhite
    @State private var customExponent: Double = 0

    var body: some View {
        List {
            if allowsNone {
                Section {
                    row(title: "None", detail: nil, id: "")
                }
            }
            if let current = FilmStock(id: stockID), current.isCustom {
                Section("Custom") {
                    row(title: current.displayName, detail: detail(for: current), id: current.id)
                }
            }
            ForEach(FilmStock.makers, id: \.self) { maker in
                Section(maker) {
                    ForEach(FilmStock.builtIns.filter { $0.maker == maker }) { stock in
                        row(title: stock.name, detail: detail(for: stock), id: stock.id)
                    }
                }
            }
            Section {
                TextField("Name", text: $customName)
                CountField(title: "ISO", value: $customISO, maximum: 100_000)
                Picker("Process", selection: $customProcess) {
                    ForEach(FilmStock.Process.allCases) { Text($0.displayName).tag($0) }
                }
                MeasurementField(title: "Reciprocity exponent (optional)", value: $customExponent, maximum: 3)
                Button("Use This Film") {
                    if let stock = customStock {
                        stockID = stock.id
                        dismiss()
                    }
                }
                .disabled(customStock == nil)
            } header: {
                Text("Another Film")
            } footer: {
                Text("If the maker gives a reciprocity exponent p (corrected time = metered time^p, as Ilford does), enter it to get corrections.")
            }
        }
        .navigationTitle("Film")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var customStock: FilmStock? {
        guard !customName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return FilmStock.custom(name: customName, iso: customISO, process: customProcess,
                                exponent: customExponent > 0 ? customExponent : nil)
    }

    private func detail(for stock: FilmStock) -> String {
        "ISO \(stock.iso) · \(stock.process.shortName)"
    }

    private func row(title: String, detail: String?, id: String) -> some View {
        Button {
            stockID = id
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
                if id == stockID {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .accessibilityAddTraits(id == stockID ? .isSelected : [])
    }
}

/// A row that opens `FilmStockPicker`.
struct FilmStockRow: View {
    @Binding var stockID: String
    var title = "Film"
    var allowsNone = true

    var body: some View {
        NavigationLink {
            FilmStockPicker(stockID: $stockID, allowsNone: allowsNone)
        } label: {
            LabeledContent(title, value: FilmStock(id: stockID)?.displayName ?? "None")
        }
    }
}

/// Formats seconds as a countdown: "4:05", "1:02:09".
enum CountdownText {
    static func format(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// "4 minutes, 5 seconds": how VoiceOver should read a countdown, rather than as a clock time.
    static func spoken(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        return Duration.seconds(total).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
