//
//  InventoryView.swift
//  ShutterManager
//
//  Root gear inventory screen: searchable, sortable, filterable list/grid of gear with a
//  collection summary, navigation to detail and collection stats, and gear addition.
//

import SwiftUI
import SwiftData

/// Compact menu for choosing a `GearSortOption`, for gear pickers; the inventory screen has its
/// own combined sort+filter menu.
struct GearSortMenu: View {
    @Binding var selection: GearSortOption

    var body: some View {
        Menu {
            Picker("Sort", selection: $selection) {
                ForEach(GearSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Sort gear")
    }
}

/// Inventory screen. Grid on a regular-width canvas (iPad / wide windows), list on compact
/// phones, with search, sort, category filter, a collection summary, and confirm-on-delete.
struct InventoryView: View {
    @Environment(\.modelContext) private var context
    // Semantic size classes + Dynamic Type drive the responsive constants, so the layout adapts to
    // the actual window (multitasking-safe) and the text scales with the user's text-size setting.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Newest-first by default for a stable, deterministic base order (CloudKit-synced stores have
    /// no inherent ordering). User sorting is layered on top in `displayedItems`.
    @Query(sort: \GearItem.dateAdded, order: .reverse) private var items: [GearItem]

    @State private var showingAddGear = false
    @State private var showingCollectionStats = false
    @State private var searchText = ""
    @State private var sortOption: GearSortOption = .recentlyAdded
    @State private var selectedCategory: GearCategory?
    @State private var itemPendingDeletion: GearItem?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                content(ResponsiveConstants(
                    geometry,
                    dynamicTypeSize: dynamicTypeSize,
                    horizontalSizeClass: horizontalSizeClass,
                    verticalSizeClass: verticalSizeClass
                ))
            }
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search gear")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticFeedbackManager.shared.navigation()
                        showingCollectionStats = true
                    } label: {
                        Image(systemName: "chart.pie")
                    }
                    .accessibilityLabel("Collection stats")
                }

                // Sort and filter sit on the leading side so Add Gear is never pushed into an
                // overflow menu: on iPad the top tab bar leaves room for two trailing buttons,
                // and search takes one of them.
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sort by", selection: $sortOption) {
                            ForEach(GearSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        Picker("Category", selection: $selectedCategory) {
                            Text("All Categories").tag(GearCategory?.none)
                            ForEach(GearCategory.allCases) { category in
                                Label(category.displayName, systemImage: category.systemImage)
                                    .tag(GearCategory?.some(category))
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Sort and filter")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticFeedbackManager.shared.buttonTap()
                        showingAddGear = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add gear")
                    .accessibilityIdentifier("addGearButton")
                }
            }
            .navigationDestination(isPresented: $showingCollectionStats) {
                CollectionStatsView()
            }
            .sheet(isPresented: $showingAddGear) {
                AddGearView(isPresented: $showingAddGear)
            }
            .confirmationDialog(
                "Delete this item?",
                isPresented: deletionDialogBinding,
                presenting: itemPendingDeletion
            ) { item in
                Button("Delete \(item.displayName)", role: .destructive) {
                    delete(item)
                }
                Button("Cancel", role: .cancel) { }
            } message: { item in
                Text("This permanently removes \(item.displayName) from your inventory.")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ constants: ResponsiveConstants) -> some View {
        if items.isEmpty {
            EmptyStateView.noGearItems {
                HapticFeedbackManager.shared.buttonTap()
                showingAddGear = true
            }
        } else {
            // One filter+search+sort pass per render — as a computed property, displayedItems
            // was independently recomputed by the summary header, the empty check, the value
            // total, and the grid/list ForEach (4× per keystroke while searching).
            let displayed = displayedItems
            VStack(spacing: 0) {
                summaryHeader(constants, displayed: displayed)
                if displayed.isEmpty {
                    emptyFilterState
                } else if constants.isRegularWidth {
                    gridLayout(constants, items: displayed)
                } else {
                    listLayout(constants, items: displayed)
                }
            }
        }
    }

    /// Compact summary of the currently shown items: count and total value (each item's
    /// `effectiveValue`, the figure Collection Stats totals). Reflects the active search/filter.
    private func summaryHeader(_ constants: ResponsiveConstants, displayed: [GearItem]) -> some View {
        HStack(spacing: constants.itemSpacing) {
            StatCard(
                title: "Items",
                value: "\(displayed.count)",
                subtitle: isFiltering ? "shown" : "in collection",
                color: .accentColor,
                constants: constants
            )
            StatCard(
                title: "Value",
                value: CurrencyFormatter.format(displayed.totalEffectiveValue),
                subtitle: isFiltering ? "filtered total" : "collection total",
                color: AppColors.goodText,
                constants: constants
            )
        }
        .padding(.horizontal, constants.padding)
        .padding(.top, constants.itemSpacing)
        .padding(.bottom, constants.itemSpacing / 2)
    }

    /// Shown when a search or filter excludes every item — wires up the (previously unused)
    /// no-search-results state, with a filter-specific variant when there's no search term.
    @ViewBuilder
    private var emptyFilterState: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyStateView.noSearchResults(searchTerm: searchText)
        } else {
            EmptyStateView.generic(
                icon: "line.3.horizontal.decrease.circle",
                title: "No Matches",
                description: "No gear matches the current filter."
            )
        }
    }

    private func gridLayout(_ constants: ResponsiveConstants, items: [GearItem]) -> some View {
        ScrollView {
            LazyVGrid(
                // Top-aligned, so cards of different heights in a row share their top edge.
                columns: [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: constants.itemSpacing, alignment: .top)],
                spacing: constants.sectionSpacing
            ) {
                ForEach(items) { item in
                    NavigationLink {
                        GearDetailView(item: item)
                    } label: {
                        GearItemCard(item: item, constants: constants)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { deleteButton(for: item) }
                }
            }
            .padding(constants.padding)
        }
        .background(AppColors.background)
    }

    private func listLayout(_ constants: ResponsiveConstants, items: [GearItem]) -> some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    GearDetailView(item: item)
                } label: {
                    GearItemListRow(item: item, constants: constants)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        itemPendingDeletion = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu { deleteButton(for: item) }
            }
        }
    }

    private func deleteButton(for item: GearItem) -> some View {
        Button(role: .destructive) {
            itemPendingDeletion = item
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Derived data

    /// Items after the active category filter, search, and sort are applied. Sorting happens in
    /// memory (collections are small); `recentlyAdded` keeps the `@Query`'s newest-first order.
    private var displayedItems: [GearItem] {
        var result = items

        if let selectedCategory {
            result = result.filter { $0.gearCategory == selectedCategory }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.displayName.lowercased().contains(query)
                    || item.gearCategory.displayName.lowercased().contains(query)
                    || item.mount.lowercased().contains(query)
                    || (item.lensSummary?.lowercased().contains(query) ?? false)
                    || (item.serialNumber?.lowercased().contains(query) ?? false)
                    || (item.notes?.lowercased().contains(query) ?? false)
            }
        }

        return result.gearSorted(by: sortOption)
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCategory != nil
    }

    // MARK: - Delete

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { itemPendingDeletion != nil },
            set: { if !$0 { itemPendingDeletion = nil } }
        )
    }

    /// Single delete path for both the list swipe action and the grid context menu: cancels the
    /// item's reminders, removes it, and confirms via a toast.
    private func delete(_ item: GearItem) {
        HapticFeedbackManager.shared.delete()
        NotificationManager.shared.cancelReminders(for: item)
        withAnimation { context.delete(item) }
        guard context.saveOrLog() else { return }
        ToastNotificationManager.shared.gearDeleted()
    }
}

// MARK: - Subviews

/// Small inline status icons for a gear item: on loan, needs service, sensor cleaning due,
/// shutter near its rated life.
struct GearStatusBadges: View {
    let item: GearItem
    let constants: ResponsiveConstants

    var body: some View {
        if item.isOnLoan {
            badge("person.crop.circle.badge.clock", item.isLoanOverdue ? .red : .blue,
                  item.isLoanOverdue ? "Loan overdue" : "On loan")
        }
        if item.serviceNeeded {
            badge("wrench.and.screwdriver.fill", .orange, "Needs service")
        }
        if item.isSensorCleaningDue {
            badge("sparkles", .orange, "Sensor cleaning due")
        }
        if item.isNearShutterLife {
            badge("exclamationmark.triangle.fill", .orange, "Shutter near rated life")
        }
    }

    private func badge(_ symbol: String, _ color: Color, _ label: String) -> some View {
        Image(systemName: symbol)
            .font(constants.captionFont)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }
}

/// Grid card for a gear item: category chip + status badges + value (`effectiveValue`, the figure
/// the summary totals and the value sort orders by), then the name and a notes preview.
struct GearItemCard: View {
    let item: GearItem
    let constants: ResponsiveConstants

    var body: some View {
        VStack(alignment: .leading, spacing: constants.itemSpacing / 2) {
            chipAndBadges

            Text(item.displayName)
                .font(constants.subtitleFont.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .padding(.top, 4)

            // The value sits at the bottom right of every card, so cards line up across the grid
            // and the chip never has to share its line.
            HStack(alignment: .firstTextBaseline, spacing: constants.itemSpacing / 2) {
                if let subtitle = item.listSubtitle {
                    Text(subtitle)
                        .font(constants.captionFont)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                valueText
            }
            .padding(.top, 4)
        }
        .padding(constants.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Match the summary StatCards above (and the app-standard card surface); these gear
            // cards previously used secondarySystemGroupedBackground, a faintly different tone.
            RoundedRectangle(cornerRadius: constants.cornerRadius)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilitySummary)
    }

    private var chipAndBadges: some View {
        HStack(spacing: constants.itemSpacing / 2) {
            categoryChip
            GearStatusBadges(item: item, constants: constants)
        }
    }

    private var valueText: Text? {
        CurrencyFormatter.formatOptional(item.effectiveValue).map {
            Text($0)
                .font(constants.bodyFont.weight(.bold))
                .foregroundColor(.primary)
        }
    }

    private var categoryChip: some View {
        Label(item.gearCategory.displayName, systemImage: item.gearCategory.systemImage)
            .font(constants.captionFont.weight(.medium))
            .foregroundStyle(AppColors.category(item.gearCategory))
            .padding(.horizontal, constants.itemSpacing * 0.75)
            .padding(.vertical, constants.itemSpacing * 0.3)
            .background(Capsule().fill(AppColors.category(item.gearCategory).opacity(0.15)))
    }
}

/// Compact list row: name + status badges, a category-colored subtitle, and the value
/// (`effectiveValue`, as on the grid card).
struct GearItemListRow: View {
    let item: GearItem
    let constants: ResponsiveConstants

    var body: some View {
        HStack(spacing: constants.itemSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(constants.bodyFont.weight(.semibold))
                        .foregroundColor(.primary)
                        // Wraps at accessibility text sizes rather than shrinking out of sight.
                        .lineLimit(constants.dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .minimumScaleFactor(0.8)
                    GearStatusBadges(item: item, constants: constants)
                }
                Text(item.listSubtitle ?? item.gearCategory.displayName)
                    .font(constants.captionFont.weight(.medium))
                    .foregroundStyle(AppColors.category(item.gearCategory))
            }

            Spacer(minLength: 0)

            if let value = CurrencyFormatter.formatOptional(item.effectiveValue) {
                Text(value)
                    .font(constants.captionFont)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilitySummary)
    }
}

// MARK: - Subtitle

extension GearItem {
    /// The one line under an item's name in lists: what distinguishes it in its category.
    var listSubtitle: String? {
        switch gearCategory {
        case .lens: return [lensSummary, mount.nonEmptyOrNil].compactMap { $0 }.joined(separator: " · ").nonEmptyOrNil
        case .cameraBody, .drone:
            return [sensorFormat?.name, mount.nonEmptyOrNil].compactMap { $0 }.joined(separator: " · ").nonEmptyOrNil
        case .memoryCard:
            let capacity = capacityGB > 0 ? "\(GearItem.trimmed(capacityGB)) GB" : nil
            return [capacity, cardType.nonEmptyOrNil].compactMap { $0 }.joined(separator: " · ").nonEmptyOrNil
        case .filter:
            let size = filterThread > 0 ? "\(GearItem.trimmed(filterThread)) mm" : nil
            let stops = filterStops > 0 ? "\(GearItem.trimmed(filterStops)) stops" : nil
            return [size, stops].compactMap { $0 }.joined(separator: " · ").nonEmptyOrNil
        default:
            return notes?.nonEmptyOrNil
        }
    }

    /// What VoiceOver reads for a row or card: the name first, then the details and anything
    /// needing attention, in the same order on iPhone (list) and iPad (grid).
    var accessibilitySummary: String {
        var parts = [displayName, gearCategory.displayName]
        if let subtitle = listSubtitle { parts.append(subtitle) }
        if let value = CurrencyFormatter.formatOptional(effectiveValue) { parts.append(value) }
        if isOnLoan { parts.append(isLoanOverdue ? "Loan overdue" : "On loan") }
        if serviceNeeded { parts.append("Needs service") }
        if isSensorCleaningDue { parts.append("Sensor cleaning due") }
        if isNearShutterLife { parts.append("Shutter near rated life") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - SwiftUI Preview

#Preview {
    let container = PreviewModelContainer.make()

    let body = GearItem(category: .cameraBody, make: "Nikon", model: "Z6 III", currentValue: 2199)
    body.sensorFormatID = SensorFormat.fullFrame.id
    body.mount = "Nikon Z"
    body.serviceNeeded = true
    container.mainContext.insert(body)
    let lens = GearItem(category: .lens, make: "Nikon", model: "Z 24-70mm f/2.8 S", currentValue: 1999)
    lens.focalLengthMin = 24
    lens.focalLengthMax = 70
    lens.maxApertureWide = 2.8
    lens.mount = "Nikon Z"
    container.mainContext.insert(lens)
    container.mainContext.insert(GearItem(category: .support, make: "Peak Design", model: "Travel Tripod", currentValue: 379))

    return InventoryView()
        .modelContainer(container)
}
