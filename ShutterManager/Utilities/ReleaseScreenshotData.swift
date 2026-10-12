#if DEBUG && RELEASE_SCREENSHOTS
//
//  ReleaseScreenshotData.swift
//  ShutterManager
//
//  A fictional library for App Store screenshots. Compiled only with DEBUG and RELEASE_SCREENSHOTS,
//  and used only with the UI-test in-memory container, so it never touches anyone's library. See
//  marketing/README.md.
//

import Foundation
import SwiftData

@MainActor
enum ReleaseScreenshotData {
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-releaseScreenshots") && arguments.contains("-uiTestInMemory")
    }

    /// The place the sky planner and the first shoot use.
    static let place = PlaceValue(name: "Mesa Arch", coordinate: GeoCoordinate(latitude: 38.3895, longitude: -109.8679),
                                  timeZoneIdentifier: "America/Denver")

    static func seed(_ context: ModelContext) throws {
        guard isEnabled else { return }
        let now = Date()
        let calendar = Calendar.current
        func day(_ offset: Int, hour: Int = 9, minute: Int = 0, in zone: TimeZone = .current) -> Date {
            var zoned = calendar
            zoned.timeZone = zone
            let start = zoned.startOfDay(for: now)
            let date = zoned.date(byAdding: .day, value: offset, to: start) ?? start
            return zoned.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        // MARK: Gear (fictional makes and models)

        func gear(_ category: GearCategory, _ make: String, _ model: String, added: Int, price: Decimal, value: Decimal? = nil,
                  configure: (GearItem) -> Void = { _ in }) -> GearItem {
            let item = GearItem(category: category, dateAdded: day(-added), make: make, model: model,
                                purchaseDate: day(-added - 30), purchasePrice: price, currentValue: value)
            configure(item)
            context.insert(item)
            return item
        }
        let body = gear(.cameraBody, "Northwind", "NW-45 Mirrorless", added: 1, price: 3499, value: 3100) {
            $0.mount = "NW Mount"
            $0.sensorFormatID = SensorFormat.fullFrame.id
            $0.resolutionWidthPx = 8256
            $0.resolutionHeightPx = 5504
            $0.ratedShutterLife = 400_000
            $0.firmwareVersion = "2.01"
            $0.serialNumber = "NW4500127"
            $0.sensorCleaningIntervalDays = 180
            $0.lastSensorCleaningDate = day(-40)
            $0.notes = "Main body for landscapes and weddings."
        }
        for (offset, count) in [(-300, 8_200), (-220, 15_900), (-140, 24_300), (-70, 33_800), (-5, 41_250)] {
            context.insert(ShutterCountReading(gearItem: body, date: day(offset), count: count))
        }
        let standardZoom = gear(.lens, "Northwind", "24–70mm f/2.8", added: 2, price: 2299, value: 2000) {
            $0.mount = "NW Mount"
            $0.focalLengthMin = 24
            $0.focalLengthMax = 70
            $0.maxApertureWide = 2.8
            $0.maxApertureTele = 2.8
            $0.filterThread = 82
            $0.minFocusDistance = 0.38
        }
        let telezoom = gear(.lens, "Northwind", "70–200mm f/2.8", added: 3, price: 2599, value: 2300) {
            $0.mount = "NW Mount"
            $0.focalLengthMin = 70
            $0.focalLengthMax = 200
            $0.maxApertureWide = 2.8
            $0.maxApertureTele = 2.8
            $0.filterThread = 77
        }
        let prime = gear(.lens, "Northwind", "50mm f/1.8", added: 4, price: 599, value: 520) {
            $0.mount = "NW Mount"
            $0.focalLengthMin = 50
            $0.focalLengthMax = 50
            $0.maxApertureWide = 1.8
            $0.maxApertureTele = 1.8
        }
        let filmCamera = gear(.cameraBody, "Meridian", "FM 35", added: 5, price: 320, value: 450) {
            $0.mount = "Classic Bayonet"
            $0.sensorFormatID = SensorFormat.film35mm.id
            $0.notes = "Fully mechanical. Serviced last spring."
        }
        let flash = gear(.lighting, "Lumen", "Speedlight 60", added: 6, price: 449) { $0.guideNumber = 60 }
        let nd = gear(.filter, "Fieldcraft", "10-Stop ND", added: 7, price: 179) {
            $0.filterThread = 82
            $0.filterStops = 10
        }
        let tripod = gear(.support, "Fieldcraft", "Carbon Travel Tripod", added: 8, price: 389)
        let card = gear(.memoryCard, "Swift", "CFexpress B 256 GB", added: 9, price: 249) {
            $0.capacityGB = 256
            $0.cardType = "CFexpress Type B"
            $0.speedRating = "1700 MB/s"
        }
        _ = gear(.drone, "Skylark", "Mini 4", added: 10, price: 759, value: 650) {
            $0.sensorFormatID = SensorFormat.type1over1_3.id
        }
        context.insert(GearLoan(gearItem: telezoom, direction: .lentOut, person: "Alex", contact: "alex@example.com",
                                outDate: day(-2), dueDate: day(3)))

        // MARK: Places, kits, templates, recipes

        context.insert(SavedPlace(name: place.name, coordinate: place.coordinate, timeZoneIdentifier: place.timeZoneIdentifier,
                                  notes: "Sunrise through the arch. Arrive an hour early."))
        let landscape = Kit(name: "Landscape", notes: "Pack the ND and remote.", symbol: "mountain.2")
        let wedding = Kit(name: "Wedding", notes: "Two batteries per body.", symbol: "heart")
        context.insert(landscape)
        context.insert(wedding)
        landscape.gear = [body, standardZoom, nd, tripod]
        wedding.gear = [body, standardZoom, telezoom, prime, flash, card]

        let twilight = ShotListTemplate(name: "Real estate twilight", notes: "Blue hour, lights on.")
        context.insert(twilight)
        for (order, title) in ["Front exterior", "Pool and garden", "Living room through the windows", "Street view"].enumerated() {
            context.insert(ShotListTemplateItem(template: twilight, title: title, order: order))
        }

        let recipe = DevelopmentRecipe(name: "HP5 Plus at 800", filmStockID: "ilfordHP5Plus", developer: "Ilfotec DD-X",
                                       dilution: "1+4", temperatureCelsius: 20, notes: "One stop push.")
        context.insert(recipe)
        context.insert(DevelopmentStep(recipe: recipe, name: "Developer", order: 0, durationSeconds: 600, agitation: .everyMinute))
        context.insert(DevelopmentStep(recipe: recipe, name: "Stop", order: 1, durationSeconds: 60, agitation: .everyMinute))
        context.insert(DevelopmentStep(recipe: recipe, name: "Fixer", order: 2, durationSeconds: 300, agitation: .everyMinute))
        context.insert(DevelopmentStep(recipe: recipe, name: "Wash", order: 3, durationSeconds: 600))

        // MARK: Shoots

        let denver = place.timeZone
        let sunrise = Shoot(title: "Sunrise at Mesa Arch", startDate: day(1, hour: 5, minute: 30, in: denver),
                            endDate: day(1, hour: 9, in: denver), type: .landscape, notes: "Wide and long, then the canyon.")
        sunrise.place = place
        sunrise.goldenHourAlertMinutes = 30
        context.insert(sunrise)
        sunrise.add(landscape)
        sunrise.setPacked(true, for: body)
        sunrise.setPacked(true, for: tripod)
        sunrise.appendShots([
            ShotListEntry(title: "Sunburst under the arch", notes: "f/16, catch the first light"),
            ShotListEntry(title: "Glowing underside of the arch"),
            ShotListEntry(title: "Long exposure of the clouds", notes: "10-stop ND"),
            ShotListEntry(title: "Canyon layers at 200mm"),
            ShotListEntry(title: "Self-portrait at the rim")
        ], in: context)

        let ceremony = Shoot(title: "Jordan & Sam", startDate: day(12, hour: 14), endDate: day(12, hour: 22), type: .wedding,
                             client: "Jordan Lee", notes: "Ceremony at 3, golden-hour portraits after the toasts.")
        context.insert(ceremony)
        ceremony.add(wedding)
        ceremony.appendShots(ShotListStarter.wedding.entries, in: context)

        let harbour = Shoot(title: "Harbour at blue hour", startDate: day(-6, hour: 19), endDate: day(-6, hour: 21), type: .street)
        context.insert(harbour)
        harbour.gear = [filmCamera, prime, tripod]
        let portraits = Shoot(title: "Studio portraits", startDate: day(-15, hour: 10), endDate: day(-15, hour: 13),
                              type: .portrait, client: "Riley Chen")
        context.insert(portraits)
        portraits.gear = [body, prime, flash]
        portraits.appendShots(ShotListStarter.portraitSession.entries, in: context)

        // MARK: Film

        let loaded = FilmRoll(filmStockID: "ilfordHP5Plus", formatID: SensorFormat.film35mm.id, ratedISO: 800,
                              camera: filmCamera, loadedDate: day(-6))
        loaded.pushPullStops = 1
        loaded.framesShot = 22
        loaded.shoot = harbour
        context.insert(loaded)
        let atLab = FilmRoll(filmStockID: "kodakPortra400", formatID: SensorFormat.film35mm.id, camera: filmCamera,
                             loadedDate: day(-30))
        atLab.framesShot = 36
        atLab.setStatus(.atLab, at: day(-10))
        atLab.lab = "Northside Lab"
        context.insert(atLab)
        let scanned = FilmRoll(filmStockID: "kodakEktar100", formatID: SensorFormat.film35mm.id, camera: filmCamera,
                               loadedDate: day(-60))
        scanned.framesShot = 36
        scanned.setStatus(.scanned, at: day(-45))
        context.insert(scanned)

        try context.save()
        // Ticks after the save, once each shoot's list holds its new items.
        sunrise.orderedShotList.prefix(2).forEach { $0.isDone = true }
        portraits.orderedShotList.forEach { $0.isDone = true }
        try context.save()

        // MARK: Screen state

        // Per-device tool state, as someone part-way through using the app would have it.
        let defaults = UserDefaults.standard
        let tools = Constants.UserDefaultsKeys.toolValuesPrefix
        defaults.set(place.stored, forKey: tools + "sky.place")
        defaults.set("manual", forKey: tools + "meter.source")
        defaults.set(14.0, forKey: tools + "meter.manualEV")
        defaults.set("aperture", forKey: tools + "meter.priority")
        defaults.set(ExposureScale.apertureValue(thirds: 18), forKey: tools + "meter.aperture")
        defaults.set(100.0, forKey: tools + "meter.iso")
        defaults.set("", forKey: tools + "meter.film")
        defaults.set(0.0, forKey: tools + "meter.filterStops")
    }
}
#endif
