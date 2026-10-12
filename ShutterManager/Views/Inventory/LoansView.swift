//
//  LoansView.swift
//  ShutterManager
//
//  Lending an item out or recording a rental, returning it, and the loan history.
//

import SwiftUI
import SwiftData

struct LoansView: View {
    @Environment(\.modelContext) private var context
    let item: GearItem

    @State private var showingNewLoan = false
    @State private var saveFailed = false

    private var history: [GearLoan] {
        (item.loans ?? []).filter { !$0.isOpen }.sorted { ($0.returnedDate ?? $0.outDate) > ($1.returnedDate ?? $1.outDate) }
    }

    var body: some View {
        List {
            if let loan = item.openLoan {
                Section("Current Loan") {
                    LabeledContent("Status", value: loan.summary)
                    if !loan.contact.isEmpty {
                        LabeledContent("Contact", value: loan.contact)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Since", value: loan.outDate.formatted(date: .abbreviated, time: .omitted))
                    if let due = loan.dueDate {
                        LabeledContent("Due Back") {
                            Text("\(due.formatted(date: .abbreviated, time: .omitted))\(loan.isOverdue ? " · overdue" : "")")
                                .foregroundStyle(loan.isOverdue ? .red : .primary)
                        }
                    }
                    if !loan.notes.isEmpty {
                        Text(loan.notes)
                    }
                    Button {
                        markReturned(loan)
                    } label: {
                        Label("Mark Returned", systemImage: "checkmark.circle")
                    }
                    .accessibilityIdentifier("markReturnedButton")
                }
            } else {
                Section {
                    Button {
                        showingNewLoan = true
                    } label: {
                        Label("Lend or Record a Rental", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("newLoanButton")
                } footer: {
                    Text("Track gear you've lent to someone, or gear you've rented, with an optional due date and reminder.")
                }
            }

            if !history.isEmpty {
                Section("History") {
                    ForEach(history) { loan in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loan.summary)
                            Text(dateRange(loan))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in
                        let loans = history
                        delete(offsets.map { loans[$0] })
                    }
                }
            }
        }
        .navigationTitle("Loans")
        .navigationBarTitleDisplayMode(.inline)
        .persistenceErrorAlert(isPresented: $saveFailed)
        .sheet(isPresented: $showingNewLoan) {
            NewLoanView(item: item)
        }
    }

    private func dateRange(_ loan: GearLoan) -> String {
        let out = loan.outDate.formatted(date: .abbreviated, time: .omitted)
        guard let returned = loan.returnedDate else { return out }
        return "\(out) – \(returned.formatted(date: .abbreviated, time: .omitted))"
    }

    private func markReturned(_ loan: GearLoan) {
        loan.returnedDate = Date()
        item.markModified()
        guard context.saveOrLog() else {
            context.rollback()
            loan.returnedDate = nil
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        ToastNotificationManager.shared.success("Marked returned")
        Task { await NotificationManager.shared.updateReminders(for: item) }
    }

    private func delete(_ loans: [GearLoan]) {
        for loan in loans { context.delete(loan) }
        if !context.saveOrLog() {
            context.rollback()
            saveFailed = true
        }
    }
}

/// Sheet for starting a loan or rental.
struct NewLoanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let item: GearItem

    @State private var direction: LoanDirection = .lentOut
    @State private var person = ""
    @State private var contact = ""
    @State private var outDate = Date()
    @State private var hasDueDate = true
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var notes = ""
    /// The item's reminder time, written to the item only on Save.
    @State private var reminderTime: Date
    @State private var saveFailed = false
    @ObservedObject private var notifications = NotificationManager.shared

    init(item: GearItem) {
        self.item = item
        _reminderTime = State(initialValue: Calendar.current.date(
            bySettingHour: item.reminderHour, minute: item.reminderMinute, second: 0, of: Date()) ?? Date())
    }

    private var trimmedPerson: String { person.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $direction) {
                        ForEach(LoanDirection.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(direction == .lentOut ? "Lent to" : "Rented from", text: $person)
                        .textContentType(direction == .lentOut ? .name : .organizationName)
                        .accessibilityIdentifier("loanPersonField")
                    TextField("Contact (optional)", text: $contact)
                }
                Section {
                    DatePicker(direction == .lentOut ? "Lent On" : "Rented On", selection: $outDate, displayedComponents: .date)
                    Toggle("Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due Back", selection: $dueDate, in: outDate..., displayedComponents: .date)
                        DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    if hasDueDate && !notifications.gearRemindersEnabled {
                        Text("Turn on Gear Reminders in Settings to be reminded on the due date.")
                    }
                }
                Section("Notes") {
                    TextField("Condition, accessories included…", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(direction == .lentOut ? "Lend Out" : "Record a Rental")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedPerson.isEmpty)
                        .accessibilityIdentifier("saveLoanButton")
                }
            }
            .persistenceErrorAlert(isPresented: $saveFailed)
        }
    }

    private func save() {
        let relationships = GearRelationshipSnapshot(item)
        let loan = GearLoan(gearItem: item, direction: direction, person: trimmedPerson,
                            contact: contact.trimmingCharacters(in: .whitespacesAndNewlines), outDate: outDate,
                            dueDate: hasDueDate ? dueDate : nil,
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(loan)
        let previousTime = (item.reminderHour, item.reminderMinute)
        if hasDueDate {
            let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            item.reminderHour = components.hour ?? Constants.Maintenance.defaultReminderHour
            item.reminderMinute = components.minute ?? 0
        }
        item.markModified()
        guard context.saveOrLog() else {
            (item.reminderHour, item.reminderMinute) = previousTime
            relationships.restore()
            context.rollback()
            relationships.restore()
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        Task { await NotificationManager.shared.updateReminders(for: item) }
        dismiss()
    }
}
