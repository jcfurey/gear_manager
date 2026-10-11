//
//  GearItemTests.swift
//  ShutterManagerTests
//
//  Defaults, derived values and the edit-copy contract of GearItem.
//

import Foundation
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct GearItemTests {
    @Test func newItemHasCloudKitSafeDefaults() {
        let item = GearItem()
        #expect(item.gearCategory == .other)
        #expect(item.mount.isEmpty)
        #expect(item.sensorFormatID.isEmpty)
        #expect(item.focalLengthMin == 0)
        #expect(item.ratedShutterLife == 0)
        #expect(item.reminderHour == 10)
        #expect(item.reminderMinute == 0)
        #expect(item.sensorFormat == nil)
        #expect(item.focalLengthText == nil)
        #expect(item.latestShutterReading == nil)
        #expect(!item.isOnLoan)
        #expect(!item.isSensorCleaningDue)
    }

    @Test func displayNameFallsBackToTheCategory() {
        #expect(GearItem(category: .lens).displayName == "Lens")
        #expect(GearItem(category: .lens, make: "Sigma").displayName == "Sigma")
        #expect(GearItem(category: .lens, make: "Sigma", model: "35mm F1.4 DG DN").displayName == "Sigma 35mm F1.4 DG DN")
        #expect(GearItem(category: .lens, make: "  ", model: "Art").displayName == "Art")
    }

    @Test func lensTextsDescribePrimesAndZooms() {
        let prime = GearItem(category: .lens)
        prime.focalLengthMin = 50
        prime.maxApertureWide = 1.8
        #expect(prime.isPrimeLens)
        #expect(prime.focalLengthText == "50 mm")
        #expect(prime.maxApertureText == "f/1.8")

        let zoom = GearItem(category: .lens)
        zoom.focalLengthMin = 18
        zoom.focalLengthMax = 55
        zoom.maxApertureWide = 3.5
        zoom.maxApertureTele = 5.6
        #expect(!zoom.isPrimeLens)
        #expect(zoom.focalLengthText == "18–55 mm")
        #expect(zoom.maxApertureText == "f/3.5–5.6")
        #expect(zoom.lensSummary == "18–55 mm f/3.5–5.6")
    }

    @Test func pixelPitchAndMegapixelsComeFromFormatAndResolution() {
        let body = GearItem(category: .cameraBody)
        body.sensorFormatID = SensorFormat.fullFrame.id
        body.resolutionWidthPx = 6000
        body.resolutionHeightPx = 4000
        #expect(body.megapixels == 24)
        #expect(abs((body.pixelPitchMicrons ?? 0) - 6.0) < 0.001)
    }

    @Test func shutterLifeUsesTheLatestReading() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = GearItem(category: .cameraBody)
        body.ratedShutterLife = 100_000
        context.insert(body)
        context.insert(ShutterCountReading(gearItem: body, date: Date(timeIntervalSince1970: 100), count: 50_000))
        context.insert(ShutterCountReading(gearItem: body, date: Date(timeIntervalSince1970: 200), count: 92_000))
        try context.save()
        #expect(body.latestShutterReading?.count == 92_000)
        #expect(abs((body.shutterLifeUsed ?? 0) - 0.92) < 0.0001)
        #expect(body.isNearShutterLife)

        // A reading after a shutter replacement is lower; the latest still wins.
        context.insert(ShutterCountReading(gearItem: body, date: Date(timeIntervalSince1970: 300), count: 100))
        try context.save()
        #expect(body.latestShutterReading?.count == 100)
        #expect(!body.isNearShutterLife)
    }

    @Test func sensorCleaningComesDueOnTheDay() {
        let body = GearItem(category: .cameraBody)
        #expect(body.nextSensorCleaningDate == nil)
        body.sensorCleaningIntervalDays = 30
        body.lastSensorCleaningDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        #expect(body.isSensorCleaningDue)
        body.lastSensorCleaningDate = Calendar.current.date(byAdding: .day, value: -29, to: Date())
        #expect(!body.isSensorCleaningDue)
        body.sensorCleaningIntervalDays = 0
        #expect(body.nextSensorCleaningDate == nil)
    }

    @Test func openLoanAndOverdue() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let item = GearItem(category: .lens)
        context.insert(item)
        let loan = GearLoan(gearItem: item, person: "Alex", dueDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        context.insert(loan)
        try context.save()
        #expect(item.isOnLoan)
        #expect(item.isLoanOverdue)
        #expect(loan.summary == "Lent to Alex")

        loan.returnedDate = Date()
        #expect(!item.isOnLoan)
        #expect(!loan.isOverdue)

        let rental = GearLoan(direction: .rentedIn, person: "")
        #expect(rental.summary == "Rented from someone")
    }

    @Test func dueTodayIsNotOverdue() {
        let loan = GearLoan(person: "Sam", dueDate: Date())
        #expect(!loan.isOverdue)
    }

    @Test func valueIsCurrentValueThenPurchasePrice() {
        #expect(GearItem(purchasePrice: 100, currentValue: 80).effectiveValue == 80)
        #expect(GearItem(purchasePrice: 100).effectiveValue == 100)
        #expect(GearItem().effectiveValue == nil)
        let items = [GearItem(purchasePrice: 100, currentValue: 80), GearItem(purchasePrice: 50), GearItem()]
        #expect(items.totalEffectiveValue == 130)
        let valuation = GearValuationService.collectionValue(of: items)
        #expect(valuation.itemsWithValue == 2)
        #expect(valuation.totalPurchasePrice == 150)
        #expect(valuation.totalValue == 130)
    }

    @Test func sortingByValueAndCategory() {
        let cheap = GearItem(category: .lens, make: "B", purchasePrice: 10)
        let dear = GearItem(category: .cameraBody, make: "A", purchasePrice: 1000)
        let none = GearItem(category: .bag, make: "C")
        #expect([cheap, none, dear].gearSorted(by: .valueHighToLow).map(\.make) == ["A", "B", "C"])
        #expect([cheap, none, dear].gearSorted(by: .category).map(\.make) == ["C", "A", "B"])
        #expect([cheap, none, dear].gearSorted(by: .name).map(\.make) == ["A", "B", "C"])
    }

    @Test func accessibilitySummaryStartsWithTheName() {
        let body = GearItem(category: .cameraBody, make: "Nikon", model: "Z8")
        body.mount = "Nikon Z"
        body.serviceNeeded = true
        #expect(body.accessibilitySummary == "Nikon Z8, Camera Body, Nikon Z, Needs service")
    }

    @Test func referenceLinksAreParsedAndDeduplicated() {
        let item = GearItem()
        item.referenceLinks = "example.com\n\nhttps://example.com\n  https://other.example/page  "
        #expect(item.referenceLinkURLs.map(\.absoluteString) == ["https://example.com", "https://other.example/page"])
    }

    // MARK: - Edit drafts

    @Test func detachedCopyCarriesEveryEditableFieldExactly() throws {
        let container = try TestSupport.makeContainer()
        let original = TestSupport.insertSampleBody(into: container.mainContext)
        original.currentValue = Decimal(string: "0.07")
        let copy = GearItem.detachedCopy(of: original)
        #expect(copy.id == original.id)
        #expect(copy.currentValue == Decimal(string: "0.07"), "Money must not drift through Double")
        #expect(copy.purchasePrice == original.purchasePrice)
        #expect(copy.make == original.make)
        #expect(copy.serialNumber == original.serialNumber)
        #expect(copy.mount == original.mount)
        #expect(copy.sensorFormatID == original.sensorFormatID)
        #expect(copy.resolutionWidthPx == original.resolutionWidthPx)
        #expect(copy.ratedShutterLife == original.ratedShutterLife)
        #expect(copy.lastSensorCleaningDate == original.lastSensorCleaningDate)
        #expect(copy.reminderHour == 9)
        #expect(copy.reminderMinute == 30)
        #expect(copy.referenceLinks == original.referenceLinks)
        #expect((copy.photos ?? []).isEmpty)
        #expect((copy.shutterCountReadings ?? []).isEmpty)
    }

    @Test func copyingEditsBackLeavesRelationshipsAlone() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let original = TestSupport.insertSampleBody(into: context)
        try context.save()
        let draft = GearItem.detachedCopy(of: original)
        draft.model = "Z8"
        draft.gearCategory = .drone
        original.copyEditableFields(from: draft)
        try context.save()
        #expect(original.model == "Z8")
        #expect(original.gearCategory == .drone)
        #expect(original.shutterCountReadings?.count == 2)
        #expect(original.loans?.count == 1)
    }
}
