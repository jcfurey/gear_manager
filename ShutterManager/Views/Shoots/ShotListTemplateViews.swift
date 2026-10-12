//
//  ShotListTemplateViews.swift
//  ShutterManager
//
//  Shot-list templates: the built-in starters to look through, and your own to edit.
//

import SwiftUI
import SwiftData

struct ShotListTemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShotListTemplate.name) private var templates: [ShotListTemplate]

    @State private var addingTemplate = false
    @State private var editingTemplate: ShotListTemplate?
    @State private var saveFailed = false

    var body: some View {
        List {
            Section {
                if templates.isEmpty {
                    Text("Make your own here, or save any shoot's list from the shoot.")
                        .foregroundStyle(Color.secondary)
                }
                ForEach(templates) { template in
                    Button {
                        editingTemplate = template
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.displayName).foregroundStyle(Color.primary)
                            let count = template.items?.count ?? 0
                            Text(count == 1 ? "1 shot" : "\(count) shots").font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            context.delete(template)
                            if !context.saveOrLog() {
                                context.rollback()
                                saveFailed = true
                            }
                        }
                    }
                }
            } header: {
                Text("My Templates")
            }

            Section {
                ForEach(ShotListStarter.allCases) { starter in
                    NavigationLink {
                        StarterPreview(starter: starter)
                    } label: {
                        Label(starter.displayName, systemImage: starter.systemImage)
                    }
                }
            } header: {
                Text("Starters")
            } footer: {
                Text("Starters come with the app. Add one to a shoot from its shot list, then make it your own.")
            }
        }
        .navigationTitle("Shot-List Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addingTemplate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New template")
                .accessibilityIdentifier("addTemplateButton")
            }
        }
        .sheet(isPresented: $addingTemplate) {
            ShotListTemplateEditorView(template: nil)
        }
        .sheet(item: $editingTemplate) { template in
            ShotListTemplateEditorView(template: template)
        }
        .persistenceErrorAlert(isPresented: $saveFailed)
    }
}

/// A built-in starter's shots, read-only, with a way to copy it into your own templates.
private struct StarterPreview: View {
    let starter: ShotListStarter

    @Environment(\.modelContext) private var context
    @State private var saveFailed = false
    @State private var saved = false

    var body: some View {
        List {
            Section {
                ForEach(Array(starter.entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                        if !entry.notes.isEmpty {
                            Text(entry.notes).font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            Section {
                Button(saved ? "Copied to My Templates" : "Copy to My Templates", action: copy)
                    .disabled(saved)
            } footer: {
                Text("A copy you can rename and change.")
            }
        }
        .navigationTitle(starter.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .persistenceErrorAlert(isPresented: $saveFailed)
    }

    private func copy() {
        let template = ShotListTemplate(name: starter.displayName)
        context.insert(template)
        for (order, entry) in starter.entries.enumerated() {
            context.insert(ShotListTemplateItem(template: template, title: entry.title, notes: entry.notes, order: order))
        }
        guard context.saveOrLog() else {
            context.rollback()
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        saved = true
    }
}

/// Adding or editing a saved template: its name, notes and shots.
struct ShotListTemplateEditorView: View {
    let template: ShotListTemplate?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: ShotListTemplateDraft
    @State private var saveFailed = false

    init(template: ShotListTemplate?) {
        self.template = template
        _draft = State(initialValue: template.map(ShotListTemplateDraft.init(template:)) ?? ShotListTemplateDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("templateNameField")
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    ForEach($draft.items) { $item in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Shot", text: $item.title)
                            TextField("Notes", text: $item.notes)
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                    .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        draft.items.append(ShotListTemplateDraft.Item())
                    } label: {
                        Label("Add a Shot", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addTemplateShotButton")
                } header: {
                    Text("Shots")
                } footer: {
                    Text("Blank shots are left out when you save. Changes here don't touch shoots already made from this template.")
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(template == nil ? "Add" : "Save", action: save)
                        .disabled(!draft.canSave)
                        .accessibilityIdentifier("saveTemplateEditorButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .persistenceErrorAlert(isPresented: $saveFailed)
        }
    }

    private func save() {
        let target: ShotListTemplate
        if let template {
            target = template
        } else {
            target = ShotListTemplate()
            context.insert(target)
        }
        draft.apply(to: target, in: context)
        guard context.saveOrLog() else {
            context.rollback()
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        dismiss()
    }
}
