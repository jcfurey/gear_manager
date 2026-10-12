//
//  FilmRollViews.swift
//  ShutterManager
//
//  The film roll log: rolls by where they are (loaded, shot, at the lab, developed, scanned), and
//  the roll editor.
//

import SwiftUI
import SwiftData

struct FilmRollsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FilmRoll.loadedDate, order: .reverse) private var rolls: [FilmRoll]

    @State private var addingRoll = false
    @State private var editingRoll: FilmRoll?
    @State private var saveFailed = false

    var body: some View {
        List {
            if rolls.isEmpty {
                ContentUnavailableView {
                    Label("No Film Rolls", systemImage: "film")
                } description: {
                    Text("Log each roll as you load it, then follow it to the lab and back.")
                } actions: {
                    Button("Load a Roll") { addingRoll = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            ForEach(FilmRollStatus.allCases) { status in
                let matching = rolls.filter { $0.status == status }
                if !matching.isEmpty {
                    Section(status.displayName) {
                        ForEach(matching) { roll in
                            Button {
                                editingRoll = roll
                            } label: {
                                FilmRollRow(roll: roll)
                            }
                            .swipeActions(edge: .leading) {
                                if let next = roll.status.next {
                                    Button(next.displayName) {
                                        roll.setStatus(next)
                                        save()
                                    }
                                    .tint(.accentColor)
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    context.delete(roll)
                                    save()
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Film Rolls")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addingRoll = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Load a roll")
                .accessibilityIdentifier("addRollButton")
            }
        }
        .sheet(isPresented: $addingRoll) {
            FilmRollEditorView(roll: nil)
        }
        .sheet(item: $editingRoll) { roll in
            FilmRollEditorView(roll: roll)
        }
        .persistenceErrorAlert(isPresented: $saveFailed)
    }

    private func save() {
        guard context.saveOrLog() else {
            context.rollback()
            saveFailed = true
            return
        }
    }
}

/// A roll: its stock, where it is, and its camera and speed.
struct FilmRollRow: View {
    let roll: FilmRoll

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: roll.status.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(roll.displayName).foregroundStyle(Color.primary)
                Text(detail).font(.caption).foregroundStyle(Color.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(roll.status.displayName).font(.caption).foregroundStyle(Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let format = roll.format { parts.append(format.name) }
        if let iso = roll.meteringISO { parts.append(roll.ratedISO > 0 ? "rated ISO \(iso)" : "ISO \(iso)") }
        if let push = roll.pushPullText { parts.append(push) }
        if let camera = roll.camera { parts.append(roll.isLoaded ? "in \(camera.displayName)" : camera.displayName) }
        if roll.frameCount > 0 { parts.append("\(roll.framesShot)/\(roll.frameCount) frames") }
        parts.append("loaded \(roll.loadedDate.formatted(date: .abbreviated, time: .omitted))")
        return parts.joined(separator: " · ")
    }
}

/// Adding or editing a roll.
struct FilmRollEditorView: View {
    let roll: FilmRoll?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \GearItem.dateAdded, order: .reverse) private var gear: [GearItem]
    @Query(sort: \Shoot.startDate, order: .reverse) private var shoots: [Shoot]

    @State private var draft: FilmRollDraft
    @State private var saveFailed = false
    @State private var confirmingDelete = false

    /// `camera` and `shoot` prefill a new roll.
    init(roll: FilmRoll?, camera: GearItem? = nil, shoot: Shoot? = nil) {
        self.roll = roll
        _draft = State(initialValue: roll.map(FilmRollDraft.init(roll:)) ?? FilmRollDraft(camera: camera, shoot: shoot))
    }

    private static let filmFormats = SensorFormat.builtIns.filter { $0.kind != .digital }
    private static let pushPullSteps: [Double] = [-3, -2, -1, -2.0 / 3, -1.0 / 3, 0, 1.0 / 3, 2.0 / 3, 1, 2, 3]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FilmStockRow(stockID: $draft.filmStockID, allowsNone: false)
                        .accessibilityIdentifier("rollStockRow")
                    Picker("Format", selection: Binding(get: { draft.formatID }, set: { draft.setFormat($0) })) {
                        Text("Not set").tag("")
                        ForEach(Self.filmFormats) { format in
                            Text(format.name).tag(format.id)
                        }
                    }
                    Picker("Camera", selection: $draft.cameraID) {
                        Text("None").tag(UUID?.none)
                        ForEach(cameras) { camera in
                            Text(camera.displayName).tag(UUID?.some(camera.id))
                        }
                    }
                } header: {
                    Text("Film")
                }

                Section {
                    Picker("Rated at", selection: $draft.ratedISO) {
                        Text(boxSpeedLabel).tag(0)
                        ForEach(isoChoices, id: \.self) { iso in
                            Text("ISO \(iso)").tag(iso)
                        }
                    }
                    Picker("Development", selection: $draft.pushPullStops) {
                        ForEach(Self.pushPullSteps, id: \.self) { stops in
                            Text(pushPullLabel(stops)).tag(stops)
                        }
                    }
                } header: {
                    Text("Speed")
                } footer: {
                    if let suggestion = suggestedPushPull {
                        Text(suggestion)
                    }
                }

                Section {
                    Picker("Status", selection: $draft.status) {
                        ForEach(FilmRollStatus.allCases) { status in
                            Label(status.displayName, systemImage: status.systemImage).tag(status)
                        }
                    }
                    .accessibilityIdentifier("rollStatusPicker")
                    CountField(title: "Frames shot", value: $draft.framesShot, maximum: 10_000)
                    CountField(title: "Frames on the roll", value: $draft.frameCount, maximum: 10_000)
                    DatePicker("Loaded", selection: $draft.loadedDate, displayedComponents: .date)
                    if draft.status != .loaded {
                        DatePicker("Finished", selection: Binding(get: { draft.finishedDate ?? Date() },
                                                                  set: { draft.finishedDate = $0 }),
                                   displayedComponents: .date)
                    }
                    TextField("Lab", text: $draft.lab)
                } header: {
                    Text("Progress")
                }

                Section {
                    Picker("Shoot", selection: $draft.shootID) {
                        Text("None").tag(UUID?.none)
                        ForEach(shoots.prefix(50)) { shoot in
                            Text(shoot.displayTitle).tag(UUID?.some(shoot.id))
                        }
                    }
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if roll != nil {
                    Section {
                        Button("Delete Roll", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(roll == nil ? "Load a Roll" : "Film Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(roll == nil ? "Add" : "Save", action: save)
                        .disabled(!draft.canSave)
                        .accessibilityIdentifier("saveRollButton")
                }
            }
            .confirmationDialog("Delete this roll?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteRoll() }
                Button("Cancel", role: .cancel) { }
            }
            .persistenceErrorAlert(isPresented: $saveFailed)
        }
    }

    /// Camera bodies, film ones first.
    private var cameras: [GearItem] {
        gear.filter { $0.gearCategory == .cameraBody }
            .sorted { ($0.sensorFormat?.kind == .digital ? 1 : 0, $0.displayName) < ($1.sensorFormat?.kind == .digital ? 1 : 0, $1.displayName) }
    }

    private var boxSpeed: Int? { FilmStock(id: draft.filmStockID)?.iso }

    private var boxSpeedLabel: String { boxSpeed.map { "Box speed (ISO \($0))" } ?? "Box speed" }

    /// Whole-number ISO marks from 6 to 102400, plus the current rating if it's off the scale.
    private var isoChoices: [Int] {
        var choices = ExposureScale.isoSpeeds().compactMap { Int($0.label.replacingOccurrences(of: "ISO ", with: "")) }
        if draft.ratedISO > 0, !choices.contains(draft.ratedISO) { choices.append(draft.ratedISO) }
        return choices.sorted()
    }

    private func pushPullLabel(_ stops: Double) -> String {
        if abs(stops) < 0.01 { return "Normal" }
        let amount = abs(stops)
        let text: String
        switch amount {
        case 1.0 / 3: text = "⅓"
        case 2.0 / 3: text = "⅔"
        default: text = ExposureScale.decimal(amount, places: 0)
        }
        return stops > 0 ? "Push +\(text)" : "Pull −\(text)"
    }

    private var suggestedPushPull: String? {
        guard draft.ratedISO > 0, let box = boxSpeed, box > 0, box != draft.ratedISO else { return nil }
        let stops = log2(Double(draft.ratedISO) / Double(box))
        let rounded = (stops * 3).rounded() / 3
        guard abs(rounded - draft.pushPullStops) > 0.01 else { return nil }
        return "Rated \(ExposureScale.decimal(abs(stops), places: 1)) stops \(stops > 0 ? "over" : "under") box speed: usually developed as \(pushPullLabel(rounded).lowercased())."
    }

    private func save() {
        let target: FilmRoll
        if let roll {
            target = roll
        } else {
            target = FilmRoll()
            context.insert(target)
        }
        draft.apply(to: target, camera: gear.first { $0.id == draft.cameraID },
                    shoot: shoots.first { $0.id == draft.shootID })
        guard context.saveOrLog() else {
            context.rollback()
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        dismiss()
    }

    private func deleteRoll() {
        guard let roll else { return }
        dismiss()
        DispatchQueue.main.async {
            context.delete(roll)
            _ = context.saveOrLog()
        }
    }
}
