//
//  PlatformTests.swift
//  ShutterManagerTests
//
//  The schema builds, photos lose their location, and marketplace links are well formed.
//

import Foundation
import ImageIO
import SwiftData
import Testing
@testable import ShutterManager

@MainActor
struct PlatformTests {
    @Test func everyModelIsRegistered() throws {
        let names = Set(AppSchema.models.map { String(describing: $0) })
        #expect(names == ["GearItem", "GearPhoto", "MaintenanceRecord", "MaintenanceReminder",
                          "ShutterCountReading", "GearLoan", "DevelopmentRecipe", "DevelopmentStep",
                          "SavedPlace", "Shoot", "ShotListItem", "Kit", "ShotListTemplate",
                          "ShotListTemplateItem", "FilmRoll"])
        let container = try TestSupport.makeContainer()
        #expect(container.schema.entities.count == AppSchema.models.count)
    }

    @Test func deletingGearDeletesItsChildren() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        body.appendGalleryPhoto(Data([9]), in: context)
        try context.save()
        context.delete(body)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<GearPhoto>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ShutterCountReading>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<GearLoan>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MaintenanceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MaintenanceReminder>()).isEmpty)
    }

    @Test func firstGalleryPhotoBecomesTheCover() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let item = GearItem()
        context.insert(item)
        let first = item.appendGalleryPhoto(Data([1]), in: context)
        let second = item.appendGalleryPhoto(Data([2]), in: context)
        try context.save()
        #expect(first.isPrimary)
        #expect(!second.isPrimary)
        #expect(second.order == first.order + 1)
        #expect(item.primaryPhotoData == Data([1]))
    }

    @Test func storedPhotosLoseTheirLocation() throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 37.33, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 122.0, kCGImagePropertyGPSLongitudeRef: "W"]
        let data = try PhotoMetadataTests.jpeg(properties: [kCGImagePropertyGPSDictionary: gps])
        let original = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let before = CGImageSourceCopyPropertiesAtIndex(original, 0, nil) as? [CFString: Any]
        #expect(before?[kCGImagePropertyGPSDictionary] != nil, "The fixture should start with a location")

        let stripped = PhotoIngest.removingLocation(from: data, source: original)
        let source = try #require(CGImageSourceCreateWithData(stripped as CFData, nil))
        let after = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(after?[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func marketplaceLinksSearchTheRightSites() throws {
        #expect(Marketplace.ebay.searchURL(query: "Nikon Z6 III")?.absoluteString
                == "https://www.ebay.com/sch/i.html?_nkw=Nikon%20Z6%20III")
        let mpb = try #require(Marketplace.mpb.searchURL(query: "Fujifilm X-T5"))
        #expect(mpb.host() == "www.google.com")
        #expect(mpb.absoluteString.contains("site:mpb.com"))
        #expect(Marketplace.google.searchURL(query: "   ") == nil)
        for market in Marketplace.allCases {
            #expect(market.searchURL(query: "Leica M6") != nil)
        }
    }

    @Test func barcodeCategoriesMapToGearCategories() {
        #expect(AddGearView.category(forProductCategory: "Cameras & Optics > Camera Lenses") == .lens)
        #expect(AddGearView.category(forProductCategory: "Cameras & Optics > Cameras") == .cameraBody)
        #expect(AddGearView.category(forProductCategory: "Tripods & Monopods") == .support)
        #expect(AddGearView.category(forProductCategory: "SD Memory Cards") == .memoryCard)
        #expect(AddGearView.category(forProductCategory: "Kitchen") == nil)
    }
}
