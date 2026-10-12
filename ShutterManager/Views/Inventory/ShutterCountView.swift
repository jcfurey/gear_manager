//
//  ShutterCountView.swift
//  ShutterManager
//
//  A body's shutter-count history: chart, readings, and adding one by hand or from a photo.
//

import SwiftUI
import SwiftData
import Charts
import PhotosUI

struct ShutterCountView: View {
    @Environment(\.modelContext) private var context
    let item: GearItem

    @State private var showingAdd = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isReadingPhoto = false
    @State private var photoReading: PhotoReading?
    @State private var photoMessage: String?
    @State private var saveFailed = false

    /// A count found in a photo, waiting for the user to confirm it.
    struct PhotoReading: Identifiable {
        let id = UUID()
        let count: Int
        let date: Date
        let serialNumber: String?
    }

    private var readings: [ShutterCountReading] {
        (item.shutterCountReadings ?? []).sorted { ($0.date, $0.count) > ($1.date, $1.count) }
    }

    var body: some View {
        let readings = self.readings
        List {
            if readings.count >= 2 || (readings.count == 1 && item.ratedShutterLife > 0) {
                Section {
                    chart(readings)
                        .frame(height: 200)
                        .padding(.vertical, 8)
                }
            }

            Section {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Reading", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("addShutterReadingButton")
                PhotosPicker(selection: $pickedPhoto, matching: .images, preferredItemEncoding: .current) {
                    Label("Read from a Photo", systemImage: "photo.badge.magnifyingglass")
                }
                .disabled(isReadingPhoto)
                if isReadingPhoto { ProgressView("Reading photo…") }
                if let photoMessage {
                    Text(photoMessage).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Photos record a shutter count only on some cameras (Nikon's are read automatically). Others show it in a menu or a service report.")
            }

            if readings.isEmpty {
                Section {
                    ContentUnavailableView("No Readings", systemImage: "camera.shutter.button",
                        description: Text("Add the shutter count from time to time to see how fast the body is wearing."))
                }
            } else {
                Section("Readings") {
                    ForEach(readings) { reading in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reading.count.formatted()).font(.body.monospacedDigit())
                                Text(reading.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !reading.note.isEmpty {
                                    Text(reading.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if reading.source == .photo {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(reading.source.displayName)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in delete(offsets.map { readings[$0] }) }
                }
            }
        }
        .navigationTitle("Shutter Count")
        .navigationBarTitleDisplayMode(.inline)
        .persistenceErrorAlert(isPresented: $saveFailed)
        .sheet(isPresented: $showingAdd) {
            AddShutterReadingView(item: item, initialCount: readings.first?.count)
        }
        .onChange(of: pickedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await readCount(from: newItem) }
        }
        .alert("Shutter Count Found", isPresented: Binding(
            get: { photoReading != nil }, set: { if !$0 { photoReading = nil } }
        ), presenting: photoReading) { reading in
            Button("Add \(reading.count.formatted())") { add(reading) }
            Button("Cancel", role: .cancel) { }
        } message: { reading in
            Text(confirmationMessage(for: reading))
        }
    }

    // MARK: - Chart

    private func chart(_ readings: [ShutterCountReading]) -> some View {
        Chart {
            ForEach(readings) { reading in
                LineMark(x: .value("Date", reading.date), y: .value("Shutter count", reading.count))
                PointMark(x: .value("Date", reading.date), y: .value("Shutter count", reading.count))
                    .accessibilityHidden(true)   // the line already reads each reading
            }
            if item.ratedShutterLife > 0 {
                RuleMark(y: .value("Rated life", item.ratedShutterLife))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Rated \(item.ratedShutterLife.formatted())")
                            .font(.caption2).foregroundStyle(.orange)
                    }
            }
        }
        .chartYScale(domain: 0...max(item.ratedShutterLife, readings.map(\.count).max() ?? 0, 1))
        .accessibilityLabel("Shutter count over time")
    }

    // MARK: - Photo

    private func readCount(from photo: PhotosPickerItem) async {
        isReadingPhoto = true
        photoMessage = nil
        defer {
            isReadingPhoto = false
            pickedPhoto = nil
        }
        guard let data = try? await photo.loadTransferable(type: Data.self) else {
            photoMessage = "That photo couldn't be loaded."
            return
        }
        let metadata = await Task.detached(priority: .userInitiated) { PhotoMetadataReader.read(data) }.value
        guard let metadata, let count = metadata.shutterCount else {
            photoMessage = "That photo doesn't include a shutter count."
            return
        }
        photoReading = PhotoReading(count: count, date: metadata.dateTaken ?? Date(),
                                    serialNumber: metadata.bodySerialNumber)
    }

    private func confirmationMessage(for reading: PhotoReading) -> String {
        var message = "Taken \(reading.date.formatted(date: .abbreviated, time: .shortened))."
        if let photoSerial = reading.serialNumber, let serial = item.serialNumber?.nonEmptyOrNil,
           photoSerial.caseInsensitiveCompare(serial) != .orderedSame {
            message += " This photo is from serial number \(photoSerial), not \(serial)."
        }
        return message
    }

    private func add(_ reading: PhotoReading) {
        let relationships = GearRelationshipSnapshot(item)
        context.insert(ShutterCountReading(gearItem: item, date: reading.date, count: reading.count, source: .photo))
        item.markModified()
        if context.saveOrLog() {
            HapticFeedbackManager.shared.success()
        } else {
            relationships.restore()
            context.rollback()
            relationships.restore()
            saveFailed = true
        }
    }

    private func delete(_ readings: [ShutterCountReading]) {
        for reading in readings { context.delete(reading) }
        if !context.saveOrLog() {
            context.rollback()
            saveFailed = true
        }
    }
}

/// Sheet for typing in a shutter count.
struct AddShutterReadingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let item: GearItem
    let initialCount: Int?

    @State private var count = 0
    @State private var date = Date()
    @State private var note = ""
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CountField(title: "Shutter Count", value: $count)
                        .accessibilityIdentifier("shutterCountField")
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    if let initialCount, count > 0, count < initialCount {
                        Text("That's lower than the last reading (\(initialCount.formatted())). It's fine after a shutter replacement.")
                    }
                }
            }
            .navigationTitle("Add Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(count <= 0)
                        .accessibilityIdentifier("saveShutterReadingButton")
                }
            }
            .persistenceErrorAlert(isPresented: $saveFailed)
        }
    }

    private func save() {
        let relationships = GearRelationshipSnapshot(item)
        context.insert(ShutterCountReading(gearItem: item, date: date, count: count,
                                           note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        item.markModified()
        guard context.saveOrLog() else {
            relationships.restore()
            context.rollback()
            relationships.restore()
            saveFailed = true
            return
        }
        HapticFeedbackManager.shared.success()
        dismiss()
    }
}
