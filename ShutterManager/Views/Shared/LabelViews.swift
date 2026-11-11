//
//  LabelViews.swift
//  ShutterManager
//
//  QR labels for kits and gear: choosing what to label and printing the sheet, and what a scanned
//  label opens.
//

import SwiftUI
import SwiftData

// MARK: - Printing

/// Chooses kits and gear to label, makes the sheet of labels, and scans a label already printed.
struct LabelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Kit.name) private var kits: [Kit]
    @Query(sort: \GearItem.dateAdded, order: .reverse) private var gear: [GearItem]

    @AppStorage(Constants.UserDefaultsKeys.labelContactLine) private var contactLine = ""
    @State private var kitIDs: Set<UUID>
    @State private var gearIDs: Set<UUID>
    @State private var size = LabelSheet.Size.large
    @State private var isPreparing = false
    @State private var sheetURL: URL?
    @State private var errorMessage: String?
    @State private var showingScanner = false
    @State private var scanned: LabelLink?

    /// Opens with these already chosen, such as the item whose screen the sheet came from.
    init(kits: Set<UUID> = [], gear: Set<UUID> = []) {
        _kitIDs = State(initialValue: kits)
        _gearIDs = State(initialValue: gear)
    }

    /// Kits first, then gear, each by name.
    private var labels: [GearLabel] {
        kits.filter { kitIDs.contains($0.id) }.map { GearLabel(kit: $0) }
            + gear.filter { gearIDs.contains($0.id) }.gearSorted(by: .name).map { GearLabel(item: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan a Label", systemImage: "qrcode.viewfinder")
                    }
                    .accessibilityIdentifier("scanLabelButton")
                } footer: {
                    Text("Scanning a label opens its kit or item. The iPhone's Camera opens them too.")
                }

                Section {
                    if kits.isEmpty {
                        Text("No kits yet. Make one in the Shoots tab to label a bag by what goes in it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(kits) { kit in
                        Button {
                            HapticFeedbackManager.shared.selection()
                            if kitIDs.contains(kit.id) { kitIDs.remove(kit.id) } else { kitIDs.insert(kit.id) }
                        } label: {
                            HStack {
                                Label {
                                    Text(kit.displayName).foregroundStyle(Color.primary)
                                } icon: {
                                    Image(systemName: kit.symbol)
                                }
                                Spacer()
                                if kitIDs.contains(kit.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityAddTraits(kitIDs.contains(kit.id) ? .isSelected : [])
                        .accessibilityIdentifier("labelKitRow")
                    }
                } header: {
                    Text("Kits")
                } footer: {
                    Text("A kit's label lists what goes in the bag, and scanning it opens a checklist.")
                }

                Section("Gear") {
                    NavigationLink {
                        GearSelectionView(selection: $gearIDs, title: "Gear to Label")
                    } label: {
                        LabeledContent("Chosen Gear", value: gearIDs.isEmpty ? "None" : "\(gearIDs.count)")
                    }
                    .accessibilityIdentifier("labelChooseGearLink")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Size")
                            .accessibilityHidden(true)
                        Picker("Size", selection: $size) {
                            ForEach(LabelSheet.Size.allCases) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Label size")
                    }
                    TextField("Contact Line", text: $contactLine)
                        .accessibilityIdentifier("labelContactField")
                } header: {
                    Text("Labels")
                } footer: {
                    Text("\(size.detail) The contact line is optional and printed on every label, such as \"If found: 555-0100\". The code holds only an ID that means nothing outside your library.")
                }

                Section {
                    Button(action: prepare) {
                        HStack {
                            if isPreparing {
                                ProgressView()
                                Text("Preparing…")
                            } else {
                                Image(systemName: "qrcode")
                                    .accessibilityHidden(true)
                                Text(labels.count == 1 ? "Create 1 Label" : "Create \(labels.count) Labels")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparing || labels.isEmpty)
                    .accessibilityIdentifier("createLabelsButton")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(AppColors.badText)
                    } else if labels.isEmpty {
                        Text("Choose a kit or some gear to label.")
                    } else {
                        Text("Print on sticker paper, or on plain paper to tape inside a lid, and cut along the dashed lines.")
                    }
                }
            }
            .navigationTitle("QR Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $sheetURL) { url in
                PDFPreviewView(url: url, title: "Labels")
            }
            .navigationDestination(item: $scanned) { link in
                LabelDestinationView(link: link)
            }
            .fullScreenCover(isPresented: $showingScanner) {
                LabelScannerView { link in
                    scanned = link
                }
            }
        }
    }

    private func prepare() {
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        let sheet = LabelSheet(labels: labels, size: size, contactLine: contactLine)
        Task {
            do {
                sheetURL = try await LabelSheetRenderer.writeFile(for: sheet)
            } catch {
                errorMessage = "Couldn't create the labels: \(error.localizedDescription)"
            }
            isPreparing = false
        }
    }
}

// MARK: - Opening a label

/// What a label opens: the kit's checklist or the item, or why neither. Goes inside a
/// navigation stack.
struct LabelDestinationView: View {
    let link: LabelLink

    @Query private var kits: [Kit]
    @Query private var gear: [GearItem]

    var body: some View {
        switch link {
        case .kit(let id):
            if let kit = kits.first(where: { $0.id == id }) {
                KitChecklistView(kit: kit)
            } else {
                missing("This kit isn't in your library.")
            }
        case .gear(let id):
            if let item = gear.first(where: { $0.id == id }) {
                GearDetailView(item: item)
            } else {
                missing("This item isn't in your library.")
            }
        }
    }

    private func missing(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Not Found", systemImage: "qrcode")
        } description: {
            Text("\(message) It may have been deleted, or the label may come from someone else's library.")
        }
        .navigationTitle("Label")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("labelNotFound")
    }
}

/// A kit's gear as a checklist for packing or checking the bag. The ticks last only while the
/// screen is open: this is a check of the bag in front of you, not a record.
struct KitChecklistView: View {
    let kit: Kit

    @State private var checked: Set<UUID> = []

    var body: some View {
        let gear = kit.orderedGear
        List {
            if !kit.notes.isEmpty {
                Section {
                    Text(kit.notes)
                }
            }
            Section {
                if gear.isEmpty {
                    Text("This kit has no gear yet. Add some from Shoots, then Kits.")
                        .foregroundStyle(.secondary)
                }
                ForEach(gear) { item in
                    let isChecked = checked.contains(item.id)
                    Button {
                        HapticFeedbackManager.shared.selection()
                        if isChecked { checked.remove(item.id) } else { checked.insert(item.id) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isChecked ? Color.green : Color.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName).foregroundStyle(Color.primary)
                                if let subtitle = item.listSubtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(Color.secondary)
                                }
                                ForEach(item.attentionReasons, id: \.self) { reason in
                                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.warningText)
                                }
                            }
                        }
                    }
                    .accessibilityAddTraits(isChecked ? .isSelected : [])
                    .accessibilityIdentifier("kitChecklistRow")
                }
            } header: {
                Text(gear.isEmpty ? "Gear" : "Gear · \(checked.intersection(gear.map(\.id)).count) of \(gear.count)")
            } footer: {
                if !gear.isEmpty {
                    Text("Tick each item as you find it in the bag. The ticks clear when you leave.")
                }
            }
        }
        .navigationTitle(kit.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Scanning

/// The camera, looking for one of the app's labels.
struct LabelScannerView: View {
    /// Called with the label once the scanner has closed itself.
    let onLabel: (LabelLink) -> Void

    @StateObject private var scanner = BarcodeScannerService()
    @Environment(\.dismiss) private var dismiss
    /// Set when a code was read that isn't a label.
    @State private var notALabel = false

    var body: some View {
        ZStack {
            CameraPreview(scannerService: scanner, isSessionReady: scanner.isSessionReady)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Scan a Label")
                        .font(.title2.weight(.semibold))
                    Text("Point the camera at a label's code.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.7))

                Spacer()

                if notALabel {
                    message("That code isn't one of your labels.")
                } else if let error = scanner.scanError {
                    message(error)
                } else if !scanner.isSessionReady && scanner.isScanning {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Starting the camera")
                }

                HStack(spacing: 24) {
                    Button {
                        dismiss()
                    } label: {
                        pill("Cancel")
                    }
                    .accessibilityIdentifier("cancelLabelScanButton")
                    if notALabel {
                        Button {
                            notALabel = false
                            scanner.resetScanner()
                            scanner.startScanning()
                        } label: {
                            pill("Scan Again")
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear { scanner.startScanning() }
        .onDisappear { scanner.stopScanning() }
        .onChange(of: scanner.scannedCode) { _, code in
            guard let code else { return }
            if let link = LabelLink(text: code) {
                onLabel(link)
                dismiss()
            } else {
                notALabel = true
            }
        }
    }

    /// White on a dark pill, readable over whatever the camera sees.
    private func pill(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.black.opacity(0.7), in: Capsule())
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding()
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
    }
}

#Preview {
    LabelsView()
        .modelContainer(PreviewModelContainer.make())
}
