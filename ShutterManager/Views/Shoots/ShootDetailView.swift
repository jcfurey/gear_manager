//
//  ShootDetailView.swift
//  ShutterManager
//
//  One shoot: when and where with that day's light, the packing check, the shot list and the
//  film used. Ticks and additions save as you go; the shoot's own fields use the editor.
//

import SwiftUI
import SwiftData

struct ShootDetailView: View {
    let shoot: Shoot

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GearItem.dateAdded, order: .reverse) private var allGear: [GearItem]
    @Query(sort: \Kit.name) private var kits: [Kit]
    @Query(sort: \ShotListTemplate.name) private var templates: [ShotListTemplate]
    @Query(sort: \FilmRoll.loadedDate, order: .reverse) private var rolls: [FilmRoll]

    @State private var editing = false
    @State private var choosingGear = false
    @State private var gearSelection: Set<UUID> = []
    @State private var newShot = ""
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var addingRoll = false
    @State private var editingRoll: FilmRoll?
    @State private var confirmingDelete = false
    @State private var saveFailed = false
    @State private var light: SkyDay?

    var body: some View {
        Form {
            summarySection
            if let place = shoot.place {
                lightSection(place)
            }
            gearSection
            shotListSection
            filmSection
            Section {
                Button("Delete Shoot", role: .destructive) { confirmingDelete = true }
                    .accessibilityIdentifier("deleteShootButton")
            }
        }
        .navigationTitle(shoot.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
                    .accessibilityIdentifier("editShootButton")
            }
        }
        .sheet(isPresented: $editing) {
            ShootEditorView(shoot: shoot)
        }
        .sheet(isPresented: $choosingGear) {
            NavigationStack {
                GearSelectionView(selection: $gearSelection, title: "Gear for This Shoot")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { choosingGear = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { applyGearSelection() }
                                .accessibilityIdentifier("doneChoosingGearButton")
                        }
                    }
            }
        }
        .sheet(isPresented: $addingRoll) {
            FilmRollEditorView(roll: nil, camera: nil, shoot: shoot)
        }
        .sheet(item: $editingRoll) { roll in
            FilmRollEditorView(roll: roll)
        }
        .alert("Save as Template", isPresented: $savingTemplate) {
            TextField("Name", text: $templateName)
            Button("Save") { saveTemplate() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The shots are copied into a new template. Ticks aren't.")
        }
        .confirmationDialog("Delete \(shoot.displayTitle)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteShoot() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Its shot list goes too. Its gear and film rolls stay.")
        }
        .persistenceErrorAlert(isPresented: $saveFailed)
        .task(id: LightKey(place: shoot.place, start: shoot.startDate)) { await loadLight() }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            // An HStack, not a Label: a Label as a row's value leaves a tall gap under it on iOS 26.
            LabeledContent("Type") {
                HStack(spacing: 6) {
                    Image(systemName: shoot.type.systemImage)
                        .accessibilityHidden(true)
                    Text(shoot.type.displayName)
                }
            }
            LabeledContent("When", value: ShootFormat.when(shoot))
            if let place = shoot.place {
                LabeledContent("Where") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(place.name.isEmpty ? place.coordinateText : place.name)
                        if !place.name.isEmpty {
                            Text(place.coordinateText).font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            if !shoot.client.isEmpty {
                LabeledContent("Client", value: shoot.client)
            }
            if !shoot.notes.isEmpty {
                Text(shoot.notes)
            }
        }
    }

    // MARK: - Light

    private struct LightKey: Hashable {
        let place: PlaceValue?
        let start: Date
    }

    private func loadLight() async {
        guard let place = shoot.place else {
            light = nil
            return
        }
        let start = shoot.startDate
        let day = await Task.detached(priority: .userInitiated) {
            SkyDay(date: start, observer: place.coordinate, timeZone: place.timeZone)
        }.value
        guard !Task.isCancelled else { return }
        light = day
    }

    @ViewBuilder
    private func lightSection(_ place: PlaceValue) -> some View {
        let zone = place.timeZone
        let time = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
        Section {
            if let light, light.observer == place.coordinate {
                if let sunrise = light.sunrise {
                    LabeledContent("Sunrise", value: sunrise.formatted(time))
                }
                if let sunset = light.sunset {
                    LabeledContent("Sunset", value: sunset.formatted(time))
                }
                ForEach(light.goldenHours, id: \.start) { window in
                    LabeledContent("Golden hour", value: "\(window.start.formatted(time)) – \(window.end.formatted(time))")
                }
                ForEach(light.blueHours, id: \.start) { window in
                    LabeledContent("Blue hour", value: "\(window.start.formatted(time)) – \(window.end.formatted(time))")
                }
                switch light.sunVisibility {
                case .alwaysUp: Text("The sun doesn't set that day.").foregroundStyle(Color.secondary)
                case .alwaysDown: Text("The sun doesn't rise that day.").foregroundStyle(Color.secondary)
                case .risesOrSets: EmptyView()
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            LabeledContent("Golden-hour heads-up",
                           value: shoot.goldenHourAlertMinutes > 0 ? "\(shoot.goldenHourAlertMinutes) min before" : "Off")
        } header: {
            Text("Light")
        } footer: {
            Text("On the day the shoot starts, in the place's time zone.")
        }
    }

    // MARK: - Gear

    private var gearSection: some View {
        Section {
            let gear = shoot.orderedGear
            if gear.isEmpty {
                Text("No gear yet. Choose items or add a kit.").foregroundStyle(Color.secondary)
            }
            ForEach(gear) { item in
                packRow(item)
                    .swipeActions {
                        Button("Remove", role: .destructive) { remove(item) }
                    }
            }
            Button {
                gearSelection = Set((shoot.gear ?? []).map(\.id))
                choosingGear = true
            } label: {
                Label("Choose Gear", systemImage: "checklist")
            }
            .accessibilityIdentifier("chooseGearButton")
            if !kits.isEmpty {
                Menu {
                    ForEach(kits) { kit in
                        Button {
                            let added = shoot.add(kit)
                            commit()
                            if added == 0 { HapticFeedbackManager.shared.selection() }
                        } label: {
                            Label(kit.displayName, systemImage: kit.symbol)
                        }
                    }
                } label: {
                    Label("Add a Kit", systemImage: "bag.badge.plus")
                }
                .accessibilityIdentifier("addKitMenu")
            }
        } header: {
            let progress = shoot.packingProgress
            Text(progress.total > 0 ? "Packing · \(progress.packed) of \(progress.total)" : "Packing")
        } footer: {
            Text("Tick items off as you pack. Items lent out, needing service or due back are flagged.")
        }
    }

    private func packRow(_ item: GearItem) -> some View {
        let packed = shoot.isPacked(item)
        let issues = item.packingIssues(for: shoot)
        return Button {
            HapticFeedbackManager.shared.selection()
            shoot.setPacked(!packed, for: item)
            commit()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: packed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(packed ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName).foregroundStyle(Color.primary)
                    if let subtitle = item.listSubtitle {
                        Text(subtitle).font(.caption).foregroundStyle(Color.secondary)
                    }
                    ForEach(issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .accessibilityIdentifier("packRow")
        .accessibilityAddTraits(packed ? .isSelected : [])
    }

    // MARK: - Shot list

    private var shotListSection: some View {
        Section {
            ForEach(shoot.orderedShotList) { item in
                Button {
                    HapticFeedbackManager.shared.selection()
                    item.isDone.toggle()
                    commit()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                                .strikethrough(item.isDone)
                            if !item.notes.isEmpty {
                                Text(item.notes).font(.caption).foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("shotRow")
                .accessibilityAddTraits(item.isDone ? .isSelected : [])
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        context.delete(item)
                        commit()
                    }
                }
            }
            HStack {
                TextField("Add a shot", text: $newShot)
                    .submitLabel(.done)
                    .onSubmit(addShot)
                    .accessibilityIdentifier("newShotField")
                Button(action: addShot) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newShot.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add shot")
                .accessibilityIdentifier("addShotButton")
            }
            Menu {
                Section("Starters") {
                    ForEach(ShotListStarter.allCases) { starter in
                        Button {
                            shoot.appendShots(starter.entries, in: context)
                            commit()
                        } label: {
                            Label(starter.displayName, systemImage: starter.systemImage)
                        }
                    }
                }
                if !templates.isEmpty {
                    Section("My Templates") {
                        ForEach(templates) { template in
                            Button(template.displayName) {
                                shoot.appendShots(template.entries, in: context)
                                commit()
                            }
                        }
                    }
                }
            } label: {
                Label("Add from a Template", systemImage: "text.badge.plus")
            }
            .accessibilityIdentifier("addShotsMenu")
            if !(shoot.shotList ?? []).isEmpty {
                Button {
                    templateName = shoot.displayTitle
                    savingTemplate = true
                } label: {
                    Label("Save as Template", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("saveTemplateButton")
            }
        } header: {
            let progress = shoot.shotListProgress
            Text(progress.total > 0 ? "Shot List · \(progress.done) of \(progress.total)" : "Shot List")
        }
    }

    private func addShot() {
        let title = newShot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        shoot.appendShots([ShotListEntry(title: title)], in: context)
        newShot = ""
        commit()
    }

    private func saveTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        shoot.saveShotList(asTemplateNamed: name.isEmpty ? shoot.displayTitle : name, in: context)
        commit()
        ToastNotificationManager.shared.success("Template saved")
    }

    // MARK: - Film

    private var filmSection: some View {
        Section {
            let used = (shoot.filmRolls ?? []).sorted { $0.loadedDate > $1.loadedDate }
            ForEach(used) { roll in
                Button {
                    editingRoll = roll
                } label: {
                    FilmRollRow(roll: roll)
                }
                .swipeActions {
                    Button("Unlink") {
                        roll.shoot = nil
                        commit()
                    }
                }
            }
            let loaded = rolls.filter { $0.isLoaded && $0.shoot?.id != shoot.id }
            Menu {
                ForEach(loaded) { roll in
                    Button {
                        roll.shoot = shoot
                        commit()
                    } label: {
                        Text(roll.camera.map { "\(roll.displayName) in \($0.displayName)" } ?? roll.displayName)
                    }
                }
                Button {
                    addingRoll = true
                } label: {
                    Label("New Roll…", systemImage: "plus")
                }
            } label: {
                Label("Add a Roll", systemImage: "film")
            }
            .accessibilityIdentifier("addRollMenu")
        } header: {
            Text("Film")
        } footer: {
            Text("Rolls shot on this shoot. A loaded roll can be added from the camera it's in.")
        }
    }

    // MARK: - Saving

    private func commit() {
        shoot.markModified()
        guard context.saveOrLog() else {
            context.rollback()
            saveFailed = true
            return
        }
    }

    private func remove(_ item: GearItem) {
        shoot.gear = (shoot.gear ?? []).filter { $0.id != item.id }
        shoot.setPacked(false, for: item)
        commit()
    }

    private func applyGearSelection() {
        shoot.gear = allGear.filter { gearSelection.contains($0.id) }
        shoot.packedIDs = shoot.packedIDs.intersection(gearSelection)
        commit()
        choosingGear = false
    }

    private func deleteShoot() {
        // Pop first, then delete on the next runloop so this view isn't showing a deleted model.
        dismiss()
        DispatchQueue.main.async {
            context.delete(shoot)
            if context.saveOrLog() {
                Task { await ShootAlertScheduler.refresh(in: context) }
            }
        }
    }
}
