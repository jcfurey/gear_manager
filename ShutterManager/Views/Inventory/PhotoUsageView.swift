//
//  PhotoUsageView.swift
//  ShutterManager
//
//  Usage from Photos: choose a batch of photos, see the shots each body and lens took, and save
//  what they show (shutter counts, missing gear, the gear used on a shoot).
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct PhotoUsageView: View {
    /// The shoot these photos are from: the gear used is added to it. Nil offers to log a new
    /// shoot instead.
    var shoot: Shoot?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var items: [GearItem]

    @State private var importer = PhotoUsageImporter()
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var choosingFiles = false
    /// Whether the file picker is choosing a folder, or image files.
    @State private var choosesFolder = false
    @State private var pickerMessage: String?

    @State private var summary: PhotoUsageSummary?
    @State private var assignments: [String: PhotoUsageAssignment] = [:]
    @State private var recordsShutterCounts = true
    @State private var usesShoot = false
    @State private var shootTitle = ""
    @State private var saveFailed = false

    private let matches = PhotoUsageMatchStore()

    var body: some View {
        NavigationStack {
            Group {
                switch importer.state {
                case .idle:
                    sourceList
                case .reading(let done, let total):
                    readingView(done: done, total: total)
                case .finished(let batch):
                    if let summary {
                        resultList(summary, batch: batch)
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Usage from Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if let summary {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(summary) }
                            .disabled(recorder(for: summary).preview(items: items).isEmpty)
                            .accessibilityIdentifier("savePhotoUsageButton")
                    }
                }
            }
            .persistenceErrorAlert(isPresented: $saveFailed)
        }
        .onChange(of: pickedPhotos) { _, photos in
            guard !photos.isEmpty else { return }
            pickerMessage = nil
            importer.read(photos: photos)
            pickedPhotos = []
        }
        .onChange(of: importer.state) { _, state in
            if case .finished(let batch) = state {
                summarize(batch)
            } else {
                summary = nil
            }
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: choosesFolder ? [.folder] : [.image],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                pickerMessage = nil
                importer.read(files: urls)
            case .failure(let error):
                pickerMessage = "Couldn't open that: \(error.localizedDescription)"
            }
        }
        .onDisappear {
            // Stop a read that's still going. A finished one is left as it is, so the sheet
            // doesn't flip back to its first screen while it closes.
            if case .reading = importer.state { importer.cancel() }
        }
    }

    // MARK: - Choosing photos

    private var sourceList: some View {
        List {
            Section {
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: Constants.PhotoUsage.maximumPhotos,
                             matching: .images, preferredItemEncoding: .current) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("photoUsagePhotosButton")
                Button {
                    choosesFolder = false
                    choosingFiles = true
                } label: {
                    Label("Choose Files", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("photoUsageFilesButton")
                Button {
                    choosesFolder = true
                    choosingFiles = true
                } label: {
                    Label("Choose a Folder", systemImage: "folder")
                }
                .accessibilityIdentifier("photoUsageFolderButton")
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uiTestPhotoUsageSample") {
                    Button("Use Sample Photos") { importer.finish(with: .uiTestSample) }
                        .accessibilityIdentifier("photoUsageSampleButton")
                }
                #endif
            } header: {
                Text("Photos to Count")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(shoot == nil
                         ? "Choose a card's worth of photos, or a whole folder, to see how many shots each body and lens took."
                         : "Choose this shoot's photos to see how many shots each body and lens took, and add that gear to the shoot.")
                    Text("Each photo's camera and lens details are read on this device. The photos aren't copied or kept. A RAW file and a JPEG with the same name count as one shot.")
                    if let pickerMessage {
                        Text(pickerMessage).foregroundStyle(AppColors.badText)
                    }
                }
            }
        }
    }

    private func readingView(done: Int, total: Int) -> some View {
        VStack(spacing: 20) {
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total)) {
                    Text("Reading photos")
                } currentValueLabel: {
                    Text("\(done.formatted()) of \(total.formatted())")
                }
            } else {
                ProgressView("Finding photos…")
            }
            Button("Stop") { importer.cancel() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stopPhotoUsageButton")
        }
        .padding(32)
        .frame(maxWidth: 480)
    }

    // MARK: - Results

    private func resultList(_ summary: PhotoUsageSummary, batch: PhotoUsageImporter.Batch) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.photos(summary.photoCount)).font(.headline)
                    if let dates = Self.dateRange(summary.firstDate, summary.lastDate) {
                        Text(dates).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("photoUsageTotal")
                ForEach(Self.notes(for: summary, batch: batch), id: \.self) { note in
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if summary.photoCount == 0 {
                Section {
                    ContentUnavailableView("No Photos Read", systemImage: "photo.badge.exclamationmark",
                        description: Text("Nothing in what you chose could be read as a photo."))
                }
            }
            groupSection("Cameras", summary.cameras)
            groupSection("Lenses", summary.lenses)

            if summary.cameras.contains(where: { $0.shutterCount != nil }) {
                Section {
                    Toggle("Record Shutter Counts", isOn: $recordsShutterCounts)
                        .accessibilityIdentifier("photoUsageShutterToggle")
                } footer: {
                    Text("Adds a reading to each matched body, dated by the photo it came from. A count the body already has is skipped.")
                }
            }
            shootSection(summary)

            Section {
                Button("Choose Other Photos") { importer.cancel() }
                    .accessibilityIdentifier("photoUsageRestartButton")
            } footer: {
                let parts = recorder(for: summary).preview(items: items).parts
                if parts.isEmpty {
                    Text("Nothing to save. Match a body or lens to an item, or add it to your inventory.")
                } else {
                    Text("Saving will \(ListFormatter.localizedString(byJoining: parts)).")
                }
            }
        }
    }

    @ViewBuilder
    private func groupSection(_ title: String, _ groups: [PhotoUsageGroup]) -> some View {
        if !groups.isEmpty {
            Section(title) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.displayName)
                        Text(Self.detail(for: group)).font(.caption).foregroundStyle(.secondary)
                        if let count = group.shutterCount {
                            Text("Shutter count \(count.formatted())").font(.caption).foregroundStyle(.secondary)
                        }
                        if case .ambiguous = group.match, assignments[group.key] == nil {
                            Text("More than one item fits. Choose which one.")
                                .font(.caption).foregroundStyle(AppColors.warningText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("photoUsageGroup")
                    Picker("Item", selection: assignment(for: group)) {
                        Text("None").tag(PhotoUsageAssignment.leftOut)
                        Text("Add to Inventory").tag(PhotoUsageAssignment.new)
                        ForEach(choices(for: group)) { item in
                            Text(item.displayName).tag(PhotoUsageAssignment.item(item.id))
                        }
                    }
                    .accessibilityLabel("Inventory item for \(group.displayName)")
                    .accessibilityIdentifier("photoUsageItemPicker")
                }
            }
        }
    }

    @ViewBuilder
    private func shootSection(_ summary: PhotoUsageSummary) -> some View {
        if let shoot {
            Section {
                Toggle("Add the Gear to This Shoot", isOn: $usesShoot)
                    .accessibilityIdentifier("photoUsageShootToggle")
            } footer: {
                Text("Matched and added items that aren't on \(shoot.displayTitle) yet are put on it.")
            }
        } else if summary.firstDate != nil {
            Section {
                Toggle("Log a Shoot", isOn: $usesShoot)
                    .accessibilityIdentifier("photoUsageShootToggle")
                if usesShoot {
                    TextField("Title", text: $shootTitle)
                        .accessibilityIdentifier("photoUsageShootTitleField")
                }
            } footer: {
                Text("Adds a shoot over the photos' dates with the matched gear on it. An item's use is counted from the shoots it went on.")
            }
        }
    }

    // MARK: - Matching

    /// The inventory items a group could be, by name.
    private func choices(for group: PhotoUsageGroup) -> [GearItem] {
        let pool = Set(PhotoUsageMatcher.pool(for: group.kind, in: candidates).map(\.id))
        return items.filter { pool.contains($0.id) }.gearSorted(by: .name)
    }

    private var candidates: [PhotoUsageCandidate] {
        items.map {
            PhotoUsageCandidate(id: $0.id, make: $0.make ?? "", model: $0.model ?? "",
                                serialNumber: $0.serialNumber ?? "", category: $0.gearCategory)
        }
    }

    private func assignment(for group: PhotoUsageGroup) -> Binding<PhotoUsageAssignment> {
        Binding(
            get: { assignments[group.key] ?? .leftOut },
            set: { choice in
                assignments[group.key] = choice
                // A chosen item is remembered for the next batch; taking it back forgets it.
                if case .item(let id) = choice {
                    matches.remember(id, for: group.key)
                } else {
                    matches.remember(nil, for: group.key)
                }
            })
    }

    private func summarize(_ batch: PhotoUsageImporter.Batch) {
        let result = PhotoUsageSummary(samples: batch.samples, candidates: candidates, remembered: matches.load())
        assignments = PhotoUsageRecorder.initialAssignments(for: result)
        recordsShutterCounts = true
        usesShoot = shoot != nil
        shootTitle = result.firstDate.map { "Photos from \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        summary = result
    }

    private func recorder(for summary: PhotoUsageSummary) -> PhotoUsageRecorder {
        var choice = PhotoUsageRecorder.ShootChoice.noShoot
        if usesShoot {
            if let shoot {
                choice = .existing(shoot)
            } else {
                choice = .new(title: shootTitle)
            }
        }
        return PhotoUsageRecorder(summary: summary, assignments: assignments,
                                  recordsShutterCounts: recordsShutterCounts, shoot: choice)
    }

    private func save(_ summary: PhotoUsageSummary) {
        guard recorder(for: summary).save(in: context, items: items) != nil else {
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        ToastNotificationManager.shared.success("Usage Saved")
        dismiss()
    }

    // MARK: - Text

    static func photos(_ count: Int) -> String {
        count == 1 ? "1 photo" : "\(count.formatted()) photos"
    }

    /// "May 3, 2026" or "May 3 – 5, 2026"; nil when no photo is dated.
    static func dateRange(_ first: Date?, _ last: Date?) -> String? {
        guard let first else { return nil }
        let end = max(last ?? first, first)
        if Calendar.current.isDate(first, inSameDayAs: end) {
            return first.formatted(date: .abbreviated, time: .omitted)
        }
        return (first..<end).formatted(date: .abbreviated, time: .omitted)
    }

    /// "356 photos · May 3 – 5, 2026 · Serial number 3000123".
    static func detail(for group: PhotoUsageGroup) -> String {
        var parts = [photos(group.photoCount)]
        if let dates = dateRange(group.firstDate, group.lastDate) { parts.append(dates) }
        if let serial = group.serialNumber { parts.append("Serial number \(serial)") }
        return parts.joined(separator: " · ")
    }

    /// What the batch left out or couldn't tell, one line each.
    static func notes(for summary: PhotoUsageSummary, batch: PhotoUsageImporter.Batch) -> [String] {
        var notes: [String] = []
        if batch.wasCutShort {
            notes.append("Only the first \(Constants.PhotoUsage.maximumPhotos.formatted()) photos were read.")
        }
        if batch.unreadableCount > 0 {
            notes.append("\(photos(batch.unreadableCount)) couldn't be read. A photo kept in iCloud has to be downloaded first.")
        }
        if summary.unnamedCameraCount > 0, summary.photoCount > 0 {
            notes.append(summary.unnamedCameraCount == 1
                         ? "1 photo doesn't say which camera took it."
                         : "\(summary.unnamedCameraCount.formatted()) photos don't say which camera took them.")
        }
        if summary.unnamedLensCount > 0, summary.photoCount > 0 {
            notes.append(summary.unnamedLensCount == 1
                         ? "1 photo doesn't name a lens. Manual and adapted lenses aren't recorded."
                         : "\(summary.unnamedLensCount.formatted()) photos don't name a lens. Manual and adapted lenses aren't recorded.")
        }
        return notes
    }
}

#Preview {
    PhotoUsageView()
        .modelContainer(PreviewModelContainer.make())
}
