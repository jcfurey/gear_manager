//
//  CollectionStatsView.swift
//  ShutterManager
//
//  Collection overview: totals, value and count by category, gear by mount, and what needs
//  attention.
//

import SwiftUI
import SwiftData
import Charts

struct CollectionStatsView: View {
    @Query(sort: \GearItem.dateAdded, order: .reverse) private var items: [GearItem]

    var body: some View {
        let valuation = GearValuationService.collectionValue(of: items)
        List {
            if items.isEmpty {
                Section {
                    ContentUnavailableView("No Gear Yet", systemImage: "chart.pie",
                        description: Text("Stats appear once your inventory has some gear."))
                }
            } else {
                Section {
                    LabeledContent("Items", value: "\(valuation.totalItems)")
                    LabeledContent("Total Value", value: valuation.formattedTotalValue)
                    LabeledContent("Total Paid", value: valuation.formattedTotalPurchasePrice)
                } footer: {
                    Text(valueFootnote(valuation))
                }

                attentionSection

                Section("By Category") {
                    categoryChart
                        .frame(height: CGFloat(categoryRows.count) * 34 + 20)
                        .padding(.vertical, 6)
                }

                if !mountRows.isEmpty {
                    Section("By Mount") {
                        ForEach(mountRows) { row in
                            LabeledContent(row.mount, value: "\(row.count)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func valueFootnote(_ valuation: CollectionValuation) -> String {
        let missing = valuation.totalItems - valuation.itemsWithValue
        let base = "Value is each item's current value if you've entered one, otherwise what you paid."
        return missing > 0 ? base + " \(missing) item\(missing == 1 ? " has" : "s have") neither." : base
    }

    // MARK: - Needs attention

    @ViewBuilder
    private var attentionSection: some View {
        let flagged = items.filter { $0.isOnLoan || $0.serviceNeeded || $0.isSensorCleaningDue || $0.isNearShutterLife }
        if !flagged.isEmpty {
            Section("Needs Attention") {
                ForEach(flagged) { item in
                    NavigationLink {
                        GearDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                            Text(reasons(for: item).joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func reasons(for item: GearItem) -> [String] {
        var reasons: [String] = []
        if let loan = item.openLoan { reasons.append(loan.isOverdue ? "\(loan.summary), overdue" : loan.summary) }
        if item.serviceNeeded { reasons.append("Needs service") }
        if item.isSensorCleaningDue { reasons.append("Sensor cleaning due") }
        if item.isNearShutterLife { reasons.append("Shutter near rated life") }
        return reasons
    }

    // MARK: - Charts

    private struct CategoryRow: Identifiable {
        let category: GearCategory
        let count: Int
        let value: Double
        var id: String { category.rawValue }
    }

    private var categoryRows: [CategoryRow] {
        let grouped = Dictionary(grouping: items, by: \.gearCategory)
        return GearCategory.allCases.compactMap { category in
            guard let members = grouped[category], !members.isEmpty else { return nil }
            return CategoryRow(category: category, count: members.count,
                               value: members.totalEffectiveValue.doubleValue)
        }
    }

    private var categoryChart: some View {
        Chart(categoryRows) { row in
            BarMark(x: .value("Items", row.count), y: .value("Category", row.category.displayName))
                .foregroundStyle(AppColors.category(row.category))
                .annotation(position: .trailing) {
                    Text(row.value > 0 ? "\(row.count) · \(CurrencyFormatter.format(Decimal(roundTripping: row.value)))" : "\(row.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
        .chartXAxis(.hidden)
        .accessibilityLabel("Items by category")
    }

    private struct MountRow: Identifiable {
        let mount: String
        let count: Int
        var id: String { mount }
    }

    private var mountRows: [MountRow] {
        let mounted = items.filter { !$0.mount.trimmingCharacters(in: .whitespaces).isEmpty }
        // Group case-insensitively, showing the most common spelling.
        let grouped = Dictionary(grouping: mounted) { LensMount.normalized($0.mount) }
        return grouped.values.map { members in
            let spellings = Dictionary(grouping: members.map { $0.mount.trimmingCharacters(in: .whitespaces) }, by: { $0 })
            let name = spellings.max { $0.value.count < $1.value.count }?.key ?? members[0].mount
            return MountRow(mount: name, count: members.count)
        }
        .sorted { $0.count == $1.count ? $0.mount < $1.mount : $0.count > $1.count }
    }
}
