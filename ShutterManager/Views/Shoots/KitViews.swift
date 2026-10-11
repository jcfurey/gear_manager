//
//  KitViews.swift
//  ShutterManager
//
//  Saved kits: named sets of gear to add to a shoot in one go.
//

import SwiftUI
import SwiftData

struct KitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Kit.name) private var kits: [Kit]

    @State private var addingKit = false
    @State private var editingKit: Kit?
    @State private var saveFailed = false

    var body: some View {
        List {
            if kits.isEmpty {
                ContentUnavailableView {
                    Label("No Kits", systemImage: "bag")
                } description: {
                    Text("Save the gear you take for each kind of shoot, like \"Wedding\" or \"Astro\", and add it to a shoot in one go.")
                } actions: {
                    Button("New Kit") { addingKit = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            ForEach(kits) { kit in
                Button {
                    editingKit = kit
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kit.symbol)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kit.displayName).foregroundStyle(.primary)
                            let count = kit.gear?.count ?? 0
                            Text(count == 1 ? "1 item" : "\(count) items").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        context.delete(kit)
                        if !context.saveOrLog() {
                            context.rollback()
                            saveFailed = true
                        }
                    }
                }
            }
        }
        .navigationTitle("Kits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addingKit = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New kit")
                .accessibilityIdentifier("addKitButton")
            }
        }
        .sheet(isPresented: $addingKit) {
            KitEditorView(kit: nil)
        }
        .sheet(item: $editingKit) { kit in
            KitEditorView(kit: kit)
        }
        .persistenceErrorAlert(isPresented: $saveFailed)
    }
}

/// Adding or editing a kit: its name, symbol, notes and gear.
struct KitEditorView: View {
    let kit: Kit?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \GearItem.dateAdded, order: .reverse) private var gear: [GearItem]

    @State private var draft: KitDraft
    @State private var saveFailed = false

    init(kit: Kit?) {
        self.kit = kit
        _draft = State(initialValue: kit.map(KitDraft.init(kit:)) ?? KitDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("kitNameField")
                    Picker("Symbol", selection: $draft.symbol) {
                        ForEach(Kit.symbols, id: \.self) { symbol in
                            Image(systemName: symbol).tag(symbol)
                        }
                    }
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    let chosen = gear.filter { draft.gearIDs.contains($0.id) }.gearSorted(by: .category)
                    ForEach(chosen) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                            if let subtitle = item.listSubtitle {
                                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { draft.gearIDs.remove(item.id) }
                        }
                    }
                    NavigationLink {
                        GearSelectionView(selection: $draft.gearIDs, title: "Gear in This Kit")
                    } label: {
                        Label(chosen.isEmpty ? "Choose Gear" : "Change Gear", systemImage: "checklist")
                    }
                    .accessibilityIdentifier("kitChooseGearButton")
                } header: {
                    Text("Gear")
                }
            }
            .navigationTitle(kit == nil ? "New Kit" : "Edit Kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(kit == nil ? "Add" : "Save", action: save)
                        .disabled(!draft.canSave)
                        .accessibilityIdentifier("saveKitButton")
                }
            }
            .persistenceErrorAlert(isPresented: $saveFailed)
        }
    }

    private func save() {
        let target: Kit
        if let kit {
            target = kit
        } else {
            target = Kit()
            context.insert(target)
        }
        draft.apply(to: target, gear: gear)
        guard context.saveOrLog() else {
            context.rollback()
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        dismiss()
    }
}
