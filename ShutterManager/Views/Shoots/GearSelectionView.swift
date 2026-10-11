//
//  GearSelectionView.swift
//  ShutterManager
//
//  Picking several items from the inventory, for a shoot or a kit.
//

import SwiftUI
import SwiftData

/// The inventory grouped by category, with a checkmark on each chosen item. Changes go straight to
/// `selection`; the presenter decides when to save.
struct GearSelectionView: View {
    @Binding var selection: Set<UUID>
    var title = "Choose Gear"

    @Query(sort: \GearItem.dateAdded, order: .reverse) private var items: [GearItem]
    @State private var searchText = ""

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = items.filter {
            query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                || ($0.listSubtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
        let categories = GearCategory.allCases.filter { category in matching.contains { $0.gearCategory == category } }
        List {
            if items.isEmpty {
                ContentUnavailableView("No Gear Yet", systemImage: "camera",
                                       description: Text("Add gear in the Inventory tab first."))
            }
            ForEach(categories) { category in
                Section(category.displayName) {
                    ForEach(matching.filter { $0.gearCategory == category }.gearSorted(by: .name)) { item in
                        Button {
                            HapticFeedbackManager.shared.selection()
                            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName).foregroundStyle(.primary)
                                    if let subtitle = item.listSubtitle {
                                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selection.contains(item.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .accessibilityAddTraits(selection.contains(item.id) ? .isSelected : [])
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search gear")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
