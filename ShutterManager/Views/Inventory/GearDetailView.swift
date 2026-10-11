//
//  GearDetailView.swift
//  ShutterManager
//
//  One gear item: its details, status, shutter count, loans, value, and links to photos and
//  maintenance, with an Edit/Done/Cancel flow.
//

import SwiftUI
import SwiftData
import UIKit

/// Reads the persistent item; edits use a detached draft applied only on Done.
struct GearDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: GearItem

    @State private var draft: GearItem?
    @State private var saveFailed = false
    @State private var showingDeleteConfirm = false
    /// Downsampled hero image, loaded once per hero-photo change rather than decoded in `body`.
    @State private var heroImage: UIImage?

    private var isEditing: Bool { draft != nil }
    private var category: GearCategory { item.gearCategory }

    var body: some View {
        Form {
            if let draft {
                GearEditorSections(item: draft)
            } else {
                readSections
            }
        }
        .persistenceErrorAlert(isPresented: $saveFailed)
        .navigationTitle(draft?.displayName ?? item.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelEditing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitEditing() }
                        .accessibilityIdentifier("doneEditingButton")
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") { beginEditing() }
                        .accessibilityIdentifier("editGearButton")
                }
            }
        }
        .confirmationDialog("Delete \(item.displayName)?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteItem() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes \(item.displayName), its photos and its history.")
        }
        // Keyed on scalar photo fields only, so it re-runs when the hero photo changes without
        // `body` ever faulting the image blob.
        .task(id: heroPhotoID) { await loadHeroImage() }
    }

    // MARK: - Read mode

    @ViewBuilder
    private var readSections: some View {
        // Grouped so the Form stays within the ViewBuilder's 10-child limit; a Group is
        // transparent in a Form, so each Section still renders on its own.
        Group {
            if let heroImage {
                Section {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel("Photo of \(item.displayName)")
                }
            }
            statusSection
            detailsSection
        }
        Group {
            if category.hasShutter { shutterSection }
            loansSection
            if category.hasSensorCleaning && (item.sensorCleaningIntervalDays > 0 || item.lastSensorCleaningDate != nil) {
                sensorCleaningSection
            }
            valueSection
        }
        Group {
            notesSection
            marketplaceSection
            managementSection
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Item", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Anything needing attention, at the top.
    @ViewBuilder
    private var statusSection: some View {
        let loan = item.openLoan
        if loan != nil || item.serviceNeeded || item.isSensorCleaningDue || item.isNearShutterLife {
            Section {
                if let loan {
                    statusRow(loan.isOverdue ? "\(loan.summary) · overdue" : loan.summary,
                              icon: loan.direction == .lentOut ? "person.crop.circle.badge.clock" : "building.2",
                              color: loan.isOverdue ? .red : .blue)
                }
                if item.serviceNeeded {
                    statusRow("Needs service", icon: "wrench.and.screwdriver.fill", color: .orange)
                }
                if item.isSensorCleaningDue {
                    statusRow("Sensor cleaning due", icon: "sparkles", color: .orange)
                }
                if item.isNearShutterLife, let used = item.shutterLifeUsed {
                    statusRow("Shutter at \(used.formatted(.percent.precision(.fractionLength(0)))) of its rated life",
                              icon: "exclamationmark.triangle.fill", color: used >= 1 ? .red : .orange)
                }
            }
        }
    }

    private func statusRow(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Category") {
                Label(category.displayName, systemImage: category.systemImage)
            }
            LabeledContent("Make", value: item.make.displayValue)
            LabeledContent("Model", value: item.model.displayValue)
            if let serial = item.serialNumber?.nonEmptyOrNil {
                LabeledContent("Serial Number", value: serial)
                    .textSelection(.enabled)
            }
            if let year = item.manufacturingYear {
                LabeledContent("Year Made", value: String(year))
            }
            specRow("Mount", item.mount)
            if let format = item.sensorFormat {
                LabeledContent(category == .lens ? "Made For" : "Format", value: format.name)
            }
            if let megapixels = item.megapixels {
                LabeledContent("Resolution",
                               value: "\(item.resolutionWidthPx) × \(item.resolutionHeightPx) · \(megapixels.formatted(.number.precision(.fractionLength(1)))) MP")
            }
            specRow("Focal Length", item.focalLengthText ?? "")
            specRow("Max Aperture", item.maxApertureText ?? "")
            if item.minFocusDistance > 0 {
                LabeledContent("Minimum Focus", value: "\(GearItem.trimmed(item.minFocusDistance)) m")
            }
            if item.filterThread > 0 {
                LabeledContent(category == .filter ? "Size" : "Filter Thread", value: "\(GearItem.trimmed(item.filterThread)) mm")
            }
            if item.filterStops > 0 {
                LabeledContent("ND Strength", value: "\(GearItem.trimmed(item.filterStops)) stops")
            }
            if item.guideNumber > 0 {
                LabeledContent("Guide Number", value: "\(GearItem.trimmed(item.guideNumber)) (m, ISO 100)")
            }
            if category.hasChargeCycles && (item.chargeCycles > 0 || item.ratedChargeCycles > 0) {
                LabeledContent("Charge Cycles", value: item.ratedChargeCycles > 0
                               ? "\(item.chargeCycles.formatted()) of \(item.ratedChargeCycles.formatted())"
                               : item.chargeCycles.formatted())
            }
            if item.capacityGB > 0 {
                LabeledContent("Capacity", value: "\(GearItem.trimmed(item.capacityGB)) GB")
            }
            specRow("Card Type", item.cardType)
            specRow("Speed Rating", item.speedRating)
            specRow("Firmware", item.firmwareVersion)
            if let upc = item.upcCode?.nonEmptyOrNil {
                LabeledContent("UPC", value: upc)
                    .textSelection(.enabled)
            }
        }
    }

    private var shutterSection: some View {
        Section("Shutter") {
            if let latest = item.latestShutterReading {
                LabeledContent("Shutter Count") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(latest.count.formatted())
                        Text(latest.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                    }
                }
            }
            if item.ratedShutterLife > 0 {
                LabeledContent("Rated Life", value: item.ratedShutterLife.formatted())
            }
            if let used = item.shutterLifeUsed {
                ProgressView(value: min(used, 1)) {
                    Text("\(used.formatted(.percent.precision(.fractionLength(0)))) of rated life used")
                        .font(.caption)
                }
                .tint(used >= 1 ? .red : (item.isNearShutterLife ? .orange : .accentColor))
            }
            NavigationLink {
                ShutterCountView(item: item)
            } label: {
                Label(item.latestShutterReading == nil ? "Add Shutter Count" : "Shutter Count History",
                      systemImage: "chart.xyaxis.line")
            }
            .accessibilityIdentifier("shutterCountLink")
        }
    }

    private var loansSection: some View {
        Section("Loans") {
            if let loan = item.openLoan {
                LabeledContent(loan.summary) {
                    if let due = loan.dueDate {
                        Text("Due \(due.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(loan.isOverdue ? .red : .secondary)
                    }
                }
            }
            NavigationLink {
                LoansView(item: item)
            } label: {
                Label(item.isOnLoan ? "Manage Loan" : "Lend or Record a Rental",
                      systemImage: "arrow.left.arrow.right")
            }
            .accessibilityIdentifier("loansLink")
        }
    }

    private var sensorCleaningSection: some View {
        Section("Sensor Cleaning") {
            LabeledContent("Remind Every", value: Constants.Maintenance.sensorCleaningIntervalOptions
                .first { $0.days == item.sensorCleaningIntervalDays }?.label ?? "\(item.sensorCleaningIntervalDays) days")
            if let last = item.lastSensorCleaningDate {
                LabeledContent("Last Cleaned", value: last.formatted(date: .abbreviated, time: .omitted))
            }
            if let next = item.nextSensorCleaningDate {
                LabeledContent("Next Cleaning") {
                    Text(next.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(item.isSensorCleaningDue ? .orange : .primary)
                }
            }
            // Records the cleaning (history, last-cleaned date and the reminder cycle) in one save.
            Button {
                do {
                    try MaintenanceService.log(for: item, type: .sensorCleaning, date: Date(), context: context)
                    HapticFeedbackManager.shared.success()
                    ToastNotificationManager.shared.success("Sensor cleaning recorded")
                    Task { await NotificationManager.shared.updateReminders(for: item) }
                } catch {
                    saveFailed = true
                }
            } label: {
                Label("Mark Sensor Cleaned Today", systemImage: "sparkles")
            }
        }
    }

    private var valueSection: some View {
        Section("Value") {
            LabeledContent("Purchase Price", value: CurrencyFormatter.format(item.purchasePrice))
            LabeledContent("Current Value", value: CurrencyFormatter.format(item.currentValue))
            if let delta = valueDelta {
                LabeledContent("Change") {
                    Text(delta.text).foregroundStyle(delta.color)
                }
            }
            if let purchased = item.purchaseDate {
                LabeledContent("Purchased", value: purchased.formatted(date: .abbreviated, time: .omitted))
            }
            LabeledContent("Added", value: item.dateAdded.formatted(date: .abbreviated, time: .omitted))
            if item.dateModified.timeIntervalSince(item.dateAdded) > 60 {
                LabeledContent("Updated", value: item.dateModified.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if item.notes?.nonEmptyOrNil != nil || item.serviceNotes?.nonEmptyOrNil != nil || !item.referenceLinkURLs.isEmpty {
            Section("Notes and Links") {
                if let notes = item.notes?.nonEmptyOrNil {
                    Text(notes)
                }
                if let serviceNotes = item.serviceNotes?.nonEmptyOrNil {
                    LabeledContent("Service", value: serviceNotes)
                }
                ForEach(item.referenceLinkURLs, id: \.self) { url in
                    Link(destination: url) {
                        Label(url.host() ?? url.absoluteString, systemImage: "link")
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// Search links into retailers and marketplaces; needs a make or model to search for.
    @ViewBuilder
    private var marketplaceSection: some View {
        let query = item.marketplaceSearchQuery
        if !query.isEmpty {
            Section {
                ForEach(Marketplace.allCases) { market in
                    if let url = market.searchURL(query: query) {
                        Link(destination: url) {
                            Label("Search \(market.displayName)", systemImage: market.systemImage)
                        }
                    }
                }
            } header: {
                Text("Find on the Market")
            } footer: {
                Text("Opens a search for “\(query)”. \(Constants.App.name) isn't affiliated with these sites.")
            }
        }
    }

    private var managementSection: some View {
        Section {
            NavigationLink {
                PhotoGalleryView(gearItem: item)
            } label: {
                LabeledContent {
                    if item.totalPhotoCount > 0 { Text("\(item.totalPhotoCount)") }
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
            }
            NavigationLink {
                MaintenanceTrackingView(gearItem: item)
            } label: {
                LabeledContent {
                    if let count = item.maintenanceRecords?.count, count > 0 { Text("\(count)") }
                } label: {
                    Label("Maintenance", systemImage: "wrench.and.screwdriver")
                }
            }
        }
    }

    @ViewBuilder
    private func specRow(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }

    /// Change from purchase price to current value, with a direction color.
    private var valueDelta: (text: String, color: Color)? {
        guard let purchase = item.purchasePrice, purchase > 0, let current = item.currentValue else { return nil }
        let delta = current - purchase
        if delta == 0 { return ("No change", .secondary) }
        let percent = NSDecimalNumber(decimal: delta).doubleValue / NSDecimalNumber(decimal: purchase).doubleValue
        let text = "\(delta > 0 ? "▲" : "▼") \(CurrencyFormatter.format(abs(delta))) (\(abs(percent).formatted(.percent.precision(.fractionLength(0)))))"
        return (text, delta > 0 ? .green : .red)
    }

    // MARK: - Hero photo

    private var heroPhotoID: UUID? {
        let photos = item.photos ?? []
        return (photos.first(where: \.isPrimary) ?? photos.min(by: { $0.order < $1.order }))?.id
    }

    /// Downsampled off the main thread; 1400px covers the 220pt banner at 3x.
    private func loadHeroImage() async {
        guard let data = item.primaryPhotoData else {
            heroImage = nil
            return
        }
        heroImage = await ThumbnailCache.downsample(data, pixelSize: 1400)
    }

    // MARK: - Edit lifecycle

    private func beginEditing() {
        guard context.saveOrLog() else { saveFailed = true; return }
        withAnimation { draft = GearItem.detachedCopy(of: item) }
    }

    private func commitEditing() {
        guard let draft else { return }
        let previous = GearItem.detachedCopy(of: item)
        item.copyEditableFields(from: draft)
        if !item.gearCategory.hasSensorCleaning {
            item.sensorCleaningIntervalDays = 0
        }
        item.markModified()
        guard context.saveOrLog() else {
            context.rollback()
            item.copyEditableFields(from: previous)
            item.dateModified = previous.dateModified
            saveFailed = true
            return
        }
        Task { await NotificationManager.shared.updateReminders(for: item) }
        withAnimation { self.draft = nil }
    }

    private func cancelEditing() {
        withAnimation { draft = nil }
    }

    private func deleteItem() {
        NotificationManager.shared.cancelReminders(for: item)
        // Pop first, then delete on the next runloop so this view isn't rendering a deleted model.
        dismiss()
        DispatchQueue.main.async {
            context.delete(item)
            if context.saveOrLog() {
                ToastNotificationManager.shared.gearDeleted()
            }
        }
    }
}
