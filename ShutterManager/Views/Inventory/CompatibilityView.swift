//
//  CompatibilityView.swift
//  ShutterManager
//
//  A body's lenses, or a lens's bodies, from the inventory: what fits, what needs an adapter,
//  and what doesn't go.
//

import SwiftUI
import SwiftData

/// For a camera body, the inventory's lenses grouped by how they go on it; for a lens, the
/// bodies. Adapters in the inventory (a mount written "Canon EF → Canon RF") count.
struct CompatibilityView: View {
    let item: GearItem
    @Query private var items: [GearItem]

    var body: some View {
        let subject = item.mountedGear
        let list = CompatibilityList(subject: subject, inventory: items.map(\.mountedGear))
        List {
            Section {
                LabeledContent("Mount", value: item.mount)
                if let flange = LensMount.flangeDistance(of: item.mount) {
                    LabeledContent("Flange Distance", value: LensBodyFit.millimetres(flange))
                }
                if let format = item.sensorFormat {
                    LabeledContent(list.role == .lens ? "Made For" : "Format", value: format.name)
                }
            }

            if list.isEmpty {
                Section {
                    ContentUnavailableView(list.role == .lens ? "No Bodies to Compare" : "No Lenses to Compare",
                        systemImage: list.role == .lens ? "camera" : "camera.aperture",
                        description: Text(list.role == .lens
                            ? "Camera bodies with a mount set appear here."
                            : "Lenses with a mount set appear here."))
                }
            }
            ForEach(list.sections) { section in
                Section(section.group.title) {
                    ForEach(section.entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.gear.name)
                            Text(Self.detail(for: entry.gear)).font(.caption).foregroundStyle(.secondary)
                            if !entry.fit.explanation.isEmpty {
                                Text(entry.fit.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("compatibilityRow")
                    }
                }
            }

            Section {
            } footer: {
                Text("Worked out from each mount's flange distance and the makers' own adapters, some of which are no longer sold new. The app can't know every adapter that's made, or how well autofocus works through one. To list an adapter you own, add it as a lens and choose Adapter in its mount's menu.")
            }
        }
        .navigationTitle(list.role == .lens ? "Bodies It Fits" : "Lenses That Fit")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Nikon F · APS-C"
    static func detail(for gear: MountedGear) -> String {
        [gear.mount.trimmingCharacters(in: .whitespaces), gear.format?.name ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Chooses the two mounts an adapter joins, and writes them to `mount` as "Lens → Body".
struct AdapterMountView: View {
    @Binding var mount: String
    @Environment(\.dismiss) private var dismiss
    @State private var lensMount = ""
    @State private var bodyMount = ""

    /// The mounts to choose from: the catalog's, and any other name the adapter already uses.
    private func choices(including current: String) -> [String] {
        let catalog = LensMount.all.filter { !LensMount.isFixedLens($0) }
        return current.isEmpty || catalog.contains(current) ? catalog : [current] + catalog
    }

    private var isComplete: Bool {
        !lensMount.isEmpty && !bodyMount.isEmpty && !LensMount.matches(lensMount, bodyMount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Takes Lenses For", selection: $lensMount) {
                        Text("Choose").tag("")
                        ForEach(choices(including: lensMount), id: \.self) { Text($0).tag($0) }
                    }
                    .accessibilityIdentifier("adapterLensMountPicker")
                    Picker("Goes on Bodies With", selection: $bodyMount) {
                        Text("Choose").tag("")
                        ForEach(choices(including: bodyMount), id: \.self) { Text($0).tag($0) }
                    }
                    .accessibilityIdentifier("adapterBodyMountPicker")
                } footer: {
                    Text(isComplete
                         ? "Its mount will read \"\(LensMount.adapterName(lens: lensMount, body: bodyMount))\". Lenses and bodies it joins are then listed as fitting with it."
                         : "An adapter is listed by the two mounts it joins. For a mount that isn't here, type both into the mount field with an arrow between them: Lens -> Body.")
                }
            }
            .navigationTitle("Adapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        mount = LensMount.adapterName(lens: lensMount, body: bodyMount)
                        dismiss()
                    }
                    .disabled(!isComplete)
                    .accessibilityIdentifier("doneAdapterMountButton")
                }
            }
            .onAppear {
                if let existing = LensMount.adapterMounts(in: mount) {
                    lensMount = existing.lens
                    bodyMount = existing.body
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CompatibilityView(item: GearItem(category: .cameraBody, make: "Nikon", model: "Z6 III"))
    }
    .modelContainer(PreviewModelContainer.make())
}
