//
//  ShootsView.swift
//  ShutterManager
//
//  The Shoots tab: the shoot log, upcoming and past, with links to film rolls, kits and
//  shot-list templates.
//

import SwiftUI
import SwiftData

struct ShootsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shoot.startDate) private var shoots: [Shoot]
    @Query private var rolls: [FilmRoll]
    @Query private var kits: [Kit]
    @Query private var templates: [ShotListTemplate]

    @State private var showingNewShoot = false
    /// A shoot just added, opened once its sheet has gone.
    @State private var createdShoot: Shoot?
    @State private var openedShoot: Shoot?
    @State private var shootPendingDeletion: Shoot?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FilmRollsView()
                    } label: {
                        LabeledContent {
                            Text(loadedRollsText)
                        } label: {
                            Label("Film Rolls", systemImage: "film")
                        }
                    }
                    .accessibilityIdentifier("filmRollsLink")
                    NavigationLink {
                        KitsView()
                    } label: {
                        LabeledContent {
                            Text(kits.isEmpty ? "" : "\(kits.count)")
                        } label: {
                            Label("Kits", systemImage: "bag")
                        }
                    }
                    .accessibilityIdentifier("kitsLink")
                    NavigationLink {
                        ShotListTemplatesView()
                    } label: {
                        LabeledContent {
                            Text(templates.isEmpty ? "" : "\(templates.count)")
                        } label: {
                            Label("Shot-List Templates", systemImage: "checklist")
                        }
                    }
                    .accessibilityIdentifier("templatesLink")
                }

                let matching = filtered
                let now = Date()
                let upcoming = matching.filter { $0.isUpcoming(at: now) }
                let past = matching.filter { !$0.isUpcoming(at: now) }.reversed()
                if shoots.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Shoots Yet", systemImage: "calendar")
                        } description: {
                            Text("Plan a shoot: when and where, the gear to pack, and the shots to get.")
                        } actions: {
                            Button("New Shoot") { showingNewShoot = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else if matching.isEmpty {
                    Section {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { row($0) }
                    }
                }
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(Array(past)) { row($0) }
                    }
                }
            }
            .navigationTitle("Shoots")
            .searchable(text: $searchText, prompt: "Search shoots")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticFeedbackManager.shared.buttonTap()
                        showingNewShoot = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New shoot")
                    .accessibilityIdentifier("addShootButton")
                }
            }
            .sheet(isPresented: $showingNewShoot, onDismiss: {
                // Pushing while the sheet is still closing is unreliable, so wait for it.
                if let createdShoot { openedShoot = createdShoot }
                createdShoot = nil
            }) {
                ShootEditorView(shoot: nil) { created in createdShoot = created }
            }
            .navigationDestination(item: $openedShoot) { shoot in
                ShootDetailView(shoot: shoot)
            }
            .confirmationDialog("Delete this shoot?", isPresented: deletionBinding, titleVisibility: .visible,
                                presenting: shootPendingDeletion) { shoot in
                Button("Delete \(shoot.displayTitle)", role: .destructive) { delete(shoot) }
                Button("Cancel", role: .cancel) { }
            } message: { _ in
                Text("Its shot list goes too. Its gear and film rolls stay.")
            }
        }
    }

    private func row(_ shoot: Shoot) -> some View {
        NavigationLink {
            ShootDetailView(shoot: shoot)
        } label: {
            ShootRow(shoot: shoot)
        }
        .swipeActions {
            Button("Delete", role: .destructive) { shootPendingDeletion = shoot }
        }
    }

    private var filtered: [Shoot] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return shoots }
        return shoots.filter {
            [$0.displayTitle, $0.client, $0.placeName, $0.type.displayName, $0.notes]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var loadedRollsText: String {
        let loaded = rolls.filter(\.isLoaded).count
        return loaded > 0 ? "\(loaded) loaded" : ""
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { shootPendingDeletion != nil }, set: { if !$0 { shootPendingDeletion = nil } })
    }

    private func delete(_ shoot: Shoot) {
        context.delete(shoot)
        if context.saveOrLog() {
            Task { await ShootAlertScheduler.refresh(in: context) }
        } else {
            context.rollback()
        }
    }
}

/// A shoot in the list: title, when (in the place's time zone), where, and how ready it is.
struct ShootRow: View {
    let shoot: Shoot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: shoot.type.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(shoot.displayTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(ShootFormat.when(shoot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String? {
        var parts: [String] = []
        if let place = shoot.place, !place.name.isEmpty { parts.append(place.name) }
        let gear = shoot.gear?.count ?? 0
        if gear > 0 { parts.append(gear == 1 ? "1 item" : "\(gear) items") }
        let shots = shoot.shotListProgress
        if shots.total > 0 { parts.append("\(shots.done)/\(shots.total) shots") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// How shoots show their dates: in the place's own time zone.
enum ShootFormat {
    /// "Sat 21 Jun, 7:00 – 10:00 PM", or with both dates when it runs over a day.
    static func when(_ shoot: Shoot) -> String {
        let zone = shoot.timeZone
        var calendar = Calendar.current
        calendar.timeZone = zone
        let day = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone).weekday(.abbreviated)
        let time = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
        let start = shoot.startDate, end = shoot.interval.end
        let zoneNote = zone == .current ? "" : " (\(zone.abbreviation(for: start) ?? zone.identifier))"
        if calendar.isDate(start, inSameDayAs: end) {
            return "\(start.formatted(day)), \(start.formatted(time)) – \(end.formatted(time))\(zoneNote)"
        }
        return "\(start.formatted(day)), \(start.formatted(time)) – \(end.formatted(day)), \(end.formatted(time))\(zoneNote)"
    }
}
