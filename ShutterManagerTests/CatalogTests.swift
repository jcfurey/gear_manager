//
//  CatalogTests.swift
//  ShutterManagerTests
//
//  Stored catalog IDs never change, and the catalogs compute what the tools rely on.
//

import Foundation
import Testing
@testable import ShutterManager

struct CatalogTests {
    // MARK: - Stable IDs
    // These lists are frozen: the IDs are stored in libraries, synced and exported. Adding an
    // entry is fine (add it here too); renaming or removing one breaks existing libraries.

    @Test func gearCategoryIDsAreStable() {
        let frozen = ["cameraBody", "lens", "lighting", "support", "filter", "drone", "audio", "power",
                      "memoryCard", "bag", "accessory", "other"]
        let current = Set(GearCategory.allCases.map(\.rawValue))
        for id in frozen {
            #expect(current.contains(id), "Stored category ID \(id) was renamed or removed")
        }
    }

    @Test func maintenanceTypeIDsAreStable() {
        let frozen = ["sensorCleaning", "cleaning", "firmwareUpdate", "calibration", "cla",
                      "shutterReplacement", "repair", "inspection", "other"]
        let current = Set(MaintenanceType.allCases.map(\.rawValue))
        for id in frozen {
            #expect(current.contains(id), "Stored maintenance type \(id) was renamed or removed")
        }
    }

    @Test func sensorFormatIDsAreStable() {
        let frozen = ["fullFrame", "apsH", "apsC", "apsCCanon", "microFourThirds", "oneInch", "type1over1.3",
                      "type1over2.3", "mediumFormat44x33", "mediumFormat54x40", "film35mm", "filmHalfFrame",
                      "film645", "film6x6", "film6x7", "film6x9", "sheet4x5", "sheet8x10", "instaxMini",
                      "instaxSquare", "instaxWide", "polaroid"]
        for id in frozen {
            #expect(SensorFormat(id: id) != nil, "Stored sensor format \(id) was renamed or removed")
        }
        #expect(Set(SensorFormat.builtIns.map(\.id)).count == SensorFormat.builtIns.count, "Duplicate format ID")
    }

    @Test func otherRawValuesAreStable() {
        #expect(ShutterCountSource.manual.rawValue == "manual")
        #expect(ShutterCountSource.photo.rawValue == "photo")
        #expect(LoanDirection.lentOut.rawValue == "lentOut")
        #expect(LoanDirection.rentedIn.rawValue == "rentedIn")
    }

    // MARK: - Unknown IDs from newer versions

    @Test func unknownStoredIDsReadAsOther() {
        #expect(GearCategory(storedID: "hologramProjector") == .other)
        #expect(MaintenanceType(storedID: "laserAlignment") == .other)
        #expect(GearCategory(storedID: "lens") == .lens)
    }

    @Test func unknownCategoryIsKeptWhenOtherFieldsChange() {
        let item = GearItem()
        item.category = "hologramProjector"
        item.make = "Edited"
        #expect(item.gearCategory == .other)
        #expect(item.category == "hologramProjector")
    }

    // MARK: - Sensor formats

    @Test func cropFactorsMatchTheFormats() {
        #expect(abs(SensorFormat.fullFrame.cropFactor - 1.0) < 0.001)
        #expect(abs(SensorFormat.apsC.cropFactor - 1.53) < 0.02)
        #expect(abs(SensorFormat.apsCCanon.cropFactor - 1.61) < 0.02)
        #expect(abs(SensorFormat.microFourThirds.cropFactor - 2.0) < 0.02)
        #expect(SensorFormat.mediumFormat44x33.cropFactor < 1)
    }

    @Test func customFormatRoundTripsThroughItsID() throws {
        let custom = try #require(SensorFormat.custom(name: "XPan", width: 65, height: 24, kind: .film))
        #expect(custom.isCustom)
        let decoded = try #require(SensorFormat(id: custom.id))
        #expect(decoded.name == "XPan")
        #expect(decoded.width == 65)
        #expect(decoded.height == 24)
        #expect(decoded.kind == .film)
        #expect(decoded.id == custom.id)
    }

    @Test func customFormatNamesMayContainColons() throws {
        let custom = try #require(SensorFormat.custom(name: "Odd: 4:3", width: 17, height: 13))
        #expect(SensorFormat(id: custom.id)?.name == "Odd: 4:3")
    }

    @Test func customFormatPutsTheLongSideFirst() throws {
        let custom = try #require(SensorFormat.custom(name: "", width: 24, height: 36))
        #expect(custom.width == 36)
        #expect(custom.height == 24)
        #expect(custom.name == "36 × 24 mm")
    }

    @Test func invalidCustomFormatsAreRejected() {
        #expect(SensorFormat.custom(name: "Zero", width: 0, height: 24) == nil)
        #expect(SensorFormat.custom(name: "Huge", width: 5000, height: 24) == nil)
        #expect(SensorFormat.custom(name: "NaN", width: .nan, height: 24) == nil)
        #expect(SensorFormat(id: "custom:garbage") == nil)
        #expect(SensorFormat(id: "") == nil)
    }

    // MARK: - Mounts

    @Test func mountsMatchIgnoringCaseAndSpaces() {
        #expect(LensMount.matches("Sony E", " sony e "))
        #expect(!LensMount.matches("Sony E", "Sony A"))
        #expect(!LensMount.matches("", ""))
        #expect(Set(LensMount.all).count == LensMount.all.count, "Duplicate mount name")
    }
}
