//
//  ShootEditorView.swift
//  ShutterManager
//
//  Adding a shoot or editing its own fields: title, type, when, where, client, notes and the
//  golden-hour heads-up.
//

import SwiftUI
import SwiftData

struct ShootEditorView: View {
    /// The shoot to edit, or nil to add one.
    let shoot: Shoot?
    /// Called with a newly added shoot, after the sheet closes.
    var onCreate: ((Shoot) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ShotListTemplate.name) private var templates: [ShotListTemplate]

    @State private var draft: ShootDraft
    /// For a new shoot: "", "starter:<id>" or "template:<uuid>".
    @State private var startingList = ""
    @State private var saveFailed = false

    init(shoot: Shoot?, onCreate: ((Shoot) -> Void)? = nil) {
        self.shoot = shoot
        self.onCreate = onCreate
        _draft = State(initialValue: shoot.map(ShootDraft.init(shoot:)) ?? ShootDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                        .accessibilityIdentifier("shootTitleField")
                    Picker("Type", selection: $draft.type) {
                        ForEach(ShootType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }
                    TextField("Client", text: $draft.client)
                }

                Section {
                    DatePicker("Starts", selection: Binding(get: { draft.startDate }, set: { draft.setStart($0) }))
                    DatePicker("Ends", selection: $draft.endDate, in: draft.startDate...)
                } header: {
                    Text("When")
                } footer: {
                    if let place = draft.place, place.timeZone != .current {
                        Text("Times are in the place's time zone, \(place.timeZone.identifier).")
                    }
                }
                .environment(\.timeZone, draft.place?.timeZone ?? .current)

                Section {
                    PlaceRow(place: $draft.place)
                } header: {
                    Text("Where")
                } footer: {
                    Text("With a place, the shoot shows that day's sun times and can send a golden-hour heads-up.")
                }

                Section {
                    Picker("Golden-hour heads-up", selection: $draft.goldenHourAlertMinutes) {
                        Text("Off").tag(0)
                        ForEach(Constants.Shoots.goldenHourAlertChoices, id: \.self) { minutes in
                            Text(minutes >= 60 ? "\(minutes / 60) h before" : "\(minutes) min before").tag(minutes)
                        }
                    }
                    .disabled(draft.place == nil)
                } footer: {
                    Text(draft.place == nil ? "Choose a place to get a heads-up before golden hour."
                         : "A notification before the golden hour during the shoot, or the next one after it starts.")
                }

                if shoot == nil {
                    Section {
                        Picker("Start From", selection: $startingList) {
                            Text("Empty").tag("")
                            ForEach(ShotListStarter.allCases) { starter in
                                Text(starter.displayName).tag("starter:\(starter.rawValue)")
                            }
                            ForEach(templates) { template in
                                Text(template.displayName).tag("template:\(template.id.uuidString)")
                            }
                        }
                    } header: {
                        Text("Shot List")
                    } footer: {
                        Text("A template's shots are copied in, so changing the template later doesn't change this shoot.")
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(shoot == nil ? "New Shoot" : "Edit Shoot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(shoot == nil ? "Add" : "Save", action: save)
                        .accessibilityIdentifier("saveShootButton")
                }
            }
            .persistenceErrorAlert(isPresented: $saveFailed)
        }
    }

    private var startingEntries: [ShotListEntry] {
        if startingList.hasPrefix("starter:"),
           let starter = ShotListStarter(rawValue: String(startingList.dropFirst("starter:".count))) {
            return starter.entries
        }
        if startingList.hasPrefix("template:") {
            let id = String(startingList.dropFirst("template:".count))
            return templates.first { $0.id.uuidString == id }?.entries ?? []
        }
        return []
    }

    private func save() {
        let target: Shoot
        if let shoot {
            target = shoot
        } else {
            target = Shoot()
            context.insert(target)
            target.appendShots(startingEntries, in: context)
        }
        draft.apply(to: target)
        guard context.saveOrLog() else {
            context.rollback()
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        let wantsAlert = draft.goldenHourAlertMinutes > 0 && draft.place != nil
        Task { await ShootAlertScheduler.refresh(in: context, askingPermission: wantsAlert) }
        dismiss()
        if shoot == nil { onCreate?(target) }
    }
}
