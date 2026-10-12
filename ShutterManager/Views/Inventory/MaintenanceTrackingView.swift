//
//  MaintenanceTrackingView.swift
//  ShutterManager
//
//  Logging and managing one item's maintenance records and reminders.

import SwiftUI
import SwiftData

/// Maintenance screen for one gear item: summary stats, active reminders, and a
/// category-filterable history, plus a sheet to log new records.
struct MaintenanceTrackingView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    
    let gearItem: GearItem
    
    @Query private var allRecords: [MaintenanceRecord]
    @Query private var allReminders: [MaintenanceReminder]
    
    @State private var showingAddRecord = false
    @State private var selectedCategory: MaintenanceCategory?
    @State private var saveFailed = false
    
    private var records: [MaintenanceRecord] {
        allRecords.filter { $0.gearItem?.id == gearItem.id }
    }
    
    private var reminders: [MaintenanceReminder] {
        allReminders.filter { $0.gearItem?.id == gearItem.id && $0.isActive }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let constants = ResponsiveConstants(geometry, dynamicTypeSize: dynamicTypeSize)
            // Filter the collection-wide queries ONCE per render. As computed properties read
            // inline, `records` re-scanned every maintenance record in the library (faulting each
            // one's gear relationship) about eight times per body evaluation — summary, empty
            // check, one per category chip, and the history list — and `reminders` three times.
            let records = self.records
            let reminders = self.reminders

            // No NavigationStack here: this screen is pushed from the gear detail view (a
            // NavigationLink), so it inherits that navigation context.
            List {
                // Summary Stats
                Section {
                    MaintenanceSummary(records: records, constants: constants)
                }

                // Upcoming/Overdue
                if !reminders.isEmpty {
                    Section("Reminders") {
                        ForEach(reminders.sorted { $0.dueDate < $1.dueDate }) { reminder in
                            ReminderRow(reminder: reminder, constants: constants)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        dismissReminder(reminder)
                                    } label: {
                                        Label("Dismiss", systemImage: "xmark.circle")
                                    }
                                    Button {
                                        completeReminder(reminder)
                                    } label: {
                                        Label("Done", systemImage: "checkmark.circle")
                                    }
                                    .tint(.green)
                                }
                        }
                    }
                }

                // Recent Maintenance
                if !records.isEmpty {
                    Section("Maintenance History") {
                        // Category filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: constants.itemSpacing / 2) {
                                FilterChip(
                                    label: "All",
                                    isSelected: selectedCategory == nil,
                                    constants: constants
                                ) {
                                    HapticFeedbackManager.shared.selection()
                                    selectedCategory = nil
                                }

                                ForEach(MaintenanceCategory.allCases, id: \.self) { category in
                                    if !records.records(for: category).isEmpty {
                                        FilterChip(
                                            label: category.rawValue,
                                            isSelected: selectedCategory == category,
                                            constants: constants
                                        ) {
                                            HapticFeedbackManager.shared.selection()
                                            selectedCategory = category
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, constants.padding / 2)
                        }
                        .listRowInsets(EdgeInsets())

                        ForEach(filteredRecords(records)) { record in
                            MaintenanceRecordRow(record: record, constants: constants)
                        }
                    }
                } else {
                    Section {
                        EmptyStateView.noMaintenanceRecords()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .persistenceErrorAlert(isPresented: $saveFailed)
            .navigationTitle("Maintenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticFeedbackManager.shared.buttonTap()
                        showingAddRecord = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add maintenance record")
                }
            }
            .sheet(isPresented: $showingAddRecord) {
                AddMaintenanceRecordView(gearItem: gearItem)
            }
        }
    }
    
    private func filteredRecords(_ records: [MaintenanceRecord]) -> [MaintenanceRecord] {
        let sorted = records.sorted { $0.date > $1.date }
        if let category = selectedCategory {
            return sorted.filter { $0.type.category == category }
        }
        return sorted
    }

    /// Mark a reminder as handled (swipe → Done) through `MaintenanceService.complete`. A
    /// sensor-cleaning reminder records a cleaning dated today — history, the item's
    /// last-cleaned date and the next cycle in one save — and reschedules the item's reminders,
    /// exactly like logging the cleaning by hand. Other recurring reminders roll forward
    /// (anchored to today when completed early); one-shot reminders deactivate. A failed save is
    /// undone and reported with the persistence alert.
    private func completeReminder(_ reminder: MaintenanceReminder) {
        HapticFeedbackManager.shared.buttonTap()
        do {
            if try MaintenanceService.complete(reminder, for: gearItem, context: modelContext) != nil {
                ToastNotificationManager.shared.success("Sensor cleaning recorded")
                Task { await NotificationManager.shared.updateReminders(for: gearItem) }
            }
        } catch {
            saveFailed = true
        }
    }

    /// Remove a reminder outright (swipe → Dismiss).
    private func dismissReminder(_ reminder: MaintenanceReminder) {
        HapticFeedbackManager.shared.buttonTap()
        modelContext.delete(reminder)
        if !modelContext.saveOrLog() { saveFailed = true }
    }
}

// MARK: - Supporting Views

struct MaintenanceSummary: View {
    let records: [MaintenanceRecord]
    let constants: ResponsiveConstants

    var body: some View {
        HStack(spacing: constants.itemSpacing) {
            SummaryBadge(
                label: "Total",
                value: "\(records.count)",
                color: .blue,
                constants: constants
            )
            
            SummaryBadge(
                // With cents, in the app currency, so the total matches the per-record rows — the
                // old inline 0-fraction-digit formatter dropped cents with half-even rounding, so a
                // 0.50 record read "0" and totals ending in .50 disagreed with the line items.
                label: "Cost",
                value: CurrencyFormatter.formatWithDecimals(records.totalCost),
                color: .green,
                constants: constants
            )
            
            SummaryBadge(
                label: "Recent",
                value: "\(records.recent(days: 30).count)",
                color: .purple,
                constants: constants
            )
        }
        .padding(.vertical, constants.itemSpacing / 2)
    }
}

struct SummaryBadge: View {
    let label: String
    let value: String
    let color: Color
    let constants: ResponsiveConstants
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(constants.bodyFont.weight(.bold))
                .foregroundColor(color)
            Text(label)
                .font(constants.footnoteFont)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, constants.itemSpacing / 2)
        .background(
            RoundedRectangle(cornerRadius: constants.cornerRadius)
                .fill(color.opacity(0.1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct ReminderRow: View {
    let reminder: MaintenanceReminder
    let constants: ResponsiveConstants
    
    var body: some View {
        HStack(spacing: constants.itemSpacing) {
            Image(systemName: reminder.type.icon)
                .foregroundColor(reminder.isOverdue ? .red : .orange)
                .font(.system(size: constants.iconSize))
                .frame(width: constants.iconSize)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.type.displayName)
                    .font(constants.bodyFont.weight(.medium))

                Text(dueDateText)
                    .font(constants.captionFont)
                    .foregroundColor(reminder.isOverdue ? .red : .secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, constants.itemSpacing / 4)
        .accessibilityElement(children: .combine)
    }
    
    private var dueDateText: String {
        let days = reminder.daysUntilDue
        if days < 0 {
            let overdue = abs(days)
            return "Overdue by \(overdue) \(overdue == 1 ? "day" : "days")"
        } else if days == 0 {
            return "Due today"
        } else {
            return "Due in \(days) \(days == 1 ? "day" : "days")"
        }
    }
}

struct MaintenanceRecordRow: View {
    let record: MaintenanceRecord
    let constants: ResponsiveConstants
    
    var body: some View {
        HStack(spacing: constants.itemSpacing) {
            Image(systemName: record.type.icon)
                .foregroundColor(categoryColor)
                .font(.system(size: constants.iconSize))
                .frame(width: constants.iconSize)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(record.type.displayName)
                    .font(constants.bodyFont.weight(.medium))

                HStack(spacing: constants.itemSpacing / 2) {
                    Text(record.date.formatted(date: .abbreviated, time: .omitted))
                        .font(constants.captionFont)
                        .foregroundColor(.secondary)

                    if let cost = record.cost {
                        Text("•")
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        Text(CurrencyFormatter.formatWithDecimals(cost))
                            .font(constants.captionFont)
                            .foregroundColor(.secondary)
                    }
                }

                if let notes = record.notes, !notes.isEmpty {
                    Text(notes)
                        .font(constants.captionFont)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, constants.itemSpacing / 4)
    }
    
    private var categoryColor: Color {
        switch record.type.category.color {
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "green": return .green
        default: return .gray
        }
    }
    
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let constants: ResponsiveConstants
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(constants.captionFont)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, constants.padding / 2)
                .padding(.vertical, constants.itemSpacing / 2)
                .background(
                    RoundedRectangle(cornerRadius: constants.cornerRadius / 2)
                        .fill(isSelected ? Color.blue : Color(.secondarySystemBackground))
                )
        }
        // Keep the tap target to the chip itself — a default-styled Button as List-row content
        // can be activated by taps elsewhere in the row (and sibling chips would fire together).
        .buttonStyle(.borderless)
        // Selection was a color-only cue; expose it so VoiceOver confirms which filter is applied.
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Add Maintenance Record

/// Form for logging a maintenance record, optionally creating a recurring
/// reminder based on the type's recommended interval.
struct AddMaintenanceRecordView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let gearItem: GearItem
    
    @State private var selectedType: MaintenanceType

    init(gearItem: GearItem) {
        self.gearItem = gearItem
        _selectedType = State(initialValue: gearItem.gearCategory.hasSensorCleaning ? .sensorCleaning : .cleaning)
    }
    @State private var date = Date()
    @State private var cost: String = ""
    @State private var notes: String = ""
    @State private var performedBy: String = ""
    @State private var setupReminder = false
    @State private var saveFailed = false
    
    var body: some View {
        GeometryReader { geometry in
            let constants = ResponsiveConstants(geometry, dynamicTypeSize: dynamicTypeSize)
            
            NavigationStack {
                Form {
                    Section("Maintenance Type") {
                        Picker("Type", selection: $selectedType) {
                            ForEach(MaintenanceType.allCases, id: \.self) { type in
                                Label(type.displayName, systemImage: type.icon).tag(type)
                            }
                        }
                    }
                    
                    Section {
                        DatePicker("Date", selection: $date, displayedComponents: [.date])
                        
                        HStack {
                            Text("Cost (Optional)")
                            Spacer()
                            TextField("Amount", text: $cost)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel("Cost")
                        }
                        
                        TextField("Performed By (Optional)", text: $performedBy)
                    } header: {
                        Text("Details")
                    } footer: {
                        if !costIsValid {
                            Text("Cost must be a valid, non-negative amount.")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Section("Notes (Optional)") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 100)
                            .accessibilityLabel("Notes")
                    }
                    
                    if let frequency = selectedType.recommendedFrequency {
                        Section {
                            Toggle("Set Reminder", isOn: $setupReminder)
                            
                            if setupReminder {
                                HStack {
                                    Text("Next Due")
                                    Spacer()
                                    Text(nextDueDate(frequency: frequency).formatted(date: .abbreviated, time: .omitted))
                                        .foregroundColor(.secondary)
                                }
                            }
                        } footer: {
                            Text("Recommended interval: every \(frequency) days")
                                .font(constants.captionFont)
                        }
                    }
                }
                .persistenceErrorAlert(isPresented: $saveFailed)
                .navigationTitle("Log Maintenance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            saveRecord()
                        }
                        .disabled(!costIsValid)
                    }
                }
            }
        }
    }
    
    private func nextDueDate(frequency: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: frequency, to: date) ?? date
    }
    
    /// An entered cost must parse to a non-negative amount, as in AddGearView. Unparseable or
    /// negative text used to be dropped silently at save — the record was logged with no cost
    /// and the maintenance total quietly understated — with nothing on screen saying why.
    private var costIsValid: Bool {
        guard !cost.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        guard let value = Decimal(localizedInput: cost) else { return false }
        return value >= 0
    }

    private func saveRecord() {
        guard costIsValid else { return }
        let costValue = Decimal(localizedInput: cost).flatMap { $0 >= 0 ? $0 : nil }
        do {
            try MaintenanceService.log(for: gearItem, type: selectedType, date: date, cost: costValue,
                notes: notes.isEmpty ? nil : notes, performedBy: performedBy.isEmpty ? nil : performedBy,
                reminderInterval: setupReminder ? selectedType.recommendedFrequency : nil, context: modelContext)
            Task { await NotificationManager.shared.updateReminders(for: gearItem) }
            dismiss()
        } catch {
            saveFailed = true
        }
    }

}

#Preview {
    let container = PreviewModelContainer.make()
    
    let sampleItem = GearItem(category: .cameraBody, make: "Nikon", model: "Z6 III")
    container.mainContext.insert(sampleItem)
    
    return NavigationStack {
        MaintenanceTrackingView(gearItem: sampleItem)
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
