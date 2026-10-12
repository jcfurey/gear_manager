//
//  GearRelationshipSnapshot.swift
//  ShutterManager
//

import SwiftData

/// Restores inverse relationships as well as the store after a failed child insertion.
/// SwiftData rollback can leave newly inserted children in an already-observed gear array.
@MainActor
struct GearRelationshipSnapshot {
    private let item: GearItem
    private let photos: [GearPhoto]?
    private let maintenanceRecords: [MaintenanceRecord]?
    private let maintenanceReminders: [MaintenanceReminder]?
    private let shutterCountReadings: [ShutterCountReading]?
    private let loans: [GearLoan]?

    init(_ item: GearItem) {
        self.item = item
        photos = item.photos
        maintenanceRecords = item.maintenanceRecords
        maintenanceReminders = item.maintenanceReminders
        shutterCountReadings = item.shutterCountReadings
        loans = item.loans
    }

    /// Before rollback this detaches newly inserted children while they are still valid models;
    /// after rollback it restores any observable arrays that retained their previous mutation.
    func restore() {
        item.photos = photos
        item.maintenanceRecords = maintenanceRecords
        item.maintenanceReminders = maintenanceReminders
        item.shutterCountReadings = shutterCountReadings
        item.loans = loans
    }
}
