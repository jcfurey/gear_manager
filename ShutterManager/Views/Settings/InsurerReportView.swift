//
//  InsurerReportView.swift
//  ShutterManager
//
//  Makes a report for the user's insurer: choose what goes in, see the PDF, share or print it.
//

import SwiftUI
import SwiftData

struct InsurerReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GearItem.dateAdded, order: .reverse) private var gear: [GearItem]

    @AppStorage(Constants.UserDefaultsKeys.reportOwnerName) private var ownerName = ""
    @State private var reference = ""
    @State private var photos = InsurerReport.PhotoChoice.cover
    @State private var includesAllGear = true
    @State private var chosenIDs: Set<UUID> = []
    @State private var isPreparing = false
    @State private var reportURL: URL?
    @State private var errorMessage: String?

    /// The gear the report will list.
    private var items: [GearItem] {
        includesAllGear ? gear : gear.filter { chosenIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your Name", text: $ownerName)
                        .textContentType(.name)
                        .accessibilityIdentifier("reportOwnerField")
                    TextField("Reference", text: $reference)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("reportReferenceField")
                } header: {
                    Text("From You")
                } footer: {
                    Text("Both are optional. The reference is whatever your insurer files this under, such as a policy or claim number.")
                }

                Section {
                    Toggle("All Gear", isOn: $includesAllGear)
                        .accessibilityIdentifier("reportAllGearToggle")
                    if !includesAllGear {
                        NavigationLink {
                            GearSelectionView(selection: $chosenIDs, title: "Gear in the Report")
                        } label: {
                            LabeledContent("Chosen Gear", value: "\(items.count) of \(gear.count)")
                        }
                        .accessibilityIdentifier("reportChooseGearLink")
                    }
                    // A segmented picker shows no label of its own.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photos")
                            .accessibilityHidden(true)
                        Picker("Photos", selection: $photos) {
                            ForEach(InsurerReport.PhotoChoice.allCases) { choice in
                                Text(choice.displayName).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Photos")
                        .accessibilityIdentifier("reportPhotosPicker")
                    }
                } header: {
                    Text("Include")
                } footer: {
                    Text(photosFootnote)
                }

                Section {
                    LabeledContent("Items", value: "\(items.count)")
                    LabeledContent("Total Value", value: CurrencyFormatter.format(items.totalEffectiveValue))
                } footer: {
                    Text("Each item is listed with its serial number, when you bought it, what you paid and its current value, as you entered them. The report isn't a valuation.")
                }

                Section {
                    Button(action: prepare) {
                        HStack {
                            if isPreparing {
                                ProgressView()
                                Text("Preparing…")
                            } else {
                                Image(systemName: "doc.richtext")
                                    .accessibilityHidden(true)
                                Text("Create Report")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparing || items.isEmpty)
                    .accessibilityIdentifier("createReportButton")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(AppColors.badText)
                    } else if items.isEmpty {
                        Text(gear.isEmpty ? "Add gear in the Inventory tab first." : "Choose at least one item.")
                    }
                }
            }
            .navigationTitle("Report for Your Insurer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $reportURL) { url in
                PDFPreviewView(url: url, title: "Report")
            }
        }
    }

    private var photosFootnote: String {
        switch photos {
        case .none: return "No photos. The smallest file."
        case .cover: return "Each item's cover photo beside its details."
        case .all: return "Every photo of each item, with its caption. Photos of serial plates and receipts help here."
        }
    }

    private func prepare() {
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        let options = InsurerReport.Options(ownerName: ownerName, reference: reference, photos: photos)
        let items = self.items
        Task {
            let report = await InsurerReport.make(items: items, options: options)
            do {
                reportURL = try await InsurerReportRenderer.writeFile(for: report)
            } catch {
                errorMessage = "Couldn't create the report: \(error.localizedDescription)"
            }
            isPreparing = false
        }
    }
}

#Preview {
    InsurerReportView()
        .modelContainer(PreviewModelContainer.make())
}
