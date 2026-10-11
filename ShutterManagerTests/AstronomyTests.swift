//
//  AstronomyTests.swift
//  ShutterManagerTests
//
//  The sun, moon and Milky Way calculations against Meeus's worked examples and the US Naval
//  Observatory's published times (aa.usno.navy.mil, read October 2026). Foundation-only, so it
//  also runs on Linux.
//

import Foundation
import Testing
@testable import ShutterManager

private func close(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= tolerance }

/// A wall-clock time at a fixed UTC offset, as USNO's tables give them.
private func time(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, utcOffset hours: Double) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: Int(hours * 3600)) ?? TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
}

private func minutes(_ a: Date?, _ b: Date) -> Double {
    guard let a else { return .infinity }
    return abs(a.timeIntervalSince(b)) / 60
}

struct MeeusExampleTests {
    @Test func sunExample25a() {
        // 1992 October 13, 0h TD.
        let sun = SunPosition(AstroTime(jde: 2_448_908.5))
        #expect(close(sun.longitude, 199.908_95, 0.000_5))
        #expect(close(sun.distance, 0.997_66, 0.000_01))
        #expect(close(sun.equatorial.rightAscension, 198.380_83, 0.000_5))
        #expect(close(sun.equatorial.declination, -7.785_07, 0.000_5))
    }

    @Test func moonExample47a() {
        // 1992 April 12, 0h TD.
        let moon = MoonPosition(AstroTime(jde: 2_448_724.5))
        #expect(close(moon.sums.longitude, -1_127_527, 3))
        #expect(close(moon.sums.latitude, -3_229_126, 3))
        #expect(close(moon.sums.distance, -16_590_875, 5))
        #expect(close(moon.geometricLongitude, 133.162_655, 0.000_01))
        #expect(close(moon.latitude, -3.229_126, 0.000_01))
        #expect(close(moon.distance, 368_409.7, 0.1))
        #expect(close(moon.parallax, 0.991_990, 0.000_01))
        // Apparent position; the book uses the full nutation series, this the 0.5″ one.
        #expect(close(moon.longitude, 133.167_265, 0.000_2))
        #expect(close(moon.equatorial.rightAscension, 134.688_470, 0.000_5))
        #expect(close(moon.equatorial.declination, 13.768_368, 0.000_5))
    }

    @Test func siderealTimeExample12a() {
        // 1987 April 10, 0h UT: apparent sidereal time 13h10m46.1351s.
        let date = Date(timeIntervalSince1970: (2_446_895.5 - 2_440_587.5) * 86_400)
        #expect(close(EarthOrientation.greenwichSiderealTime(AstroTime(date)), 197.692_230, 0.000_3))
    }

    @Test func illuminatedFractionExample48a() {
        let time = AstroTime(jde: 2_448_724.5)
        let illumination = MoonPosition(time).illumination(sun: SunPosition(time))
        #expect(close(illumination.fraction, 0.6786, 0.001))
        #expect(illumination.waxing)
    }
}

struct USNOComparisonTests {
    /// Sun times within 2 minutes and moon times within 5, as the roadmap asks. USNO rounds to
    /// the minute.
    private let sunTolerance = 2.0
    private let moonTolerance = 5.0

    private struct Case {
        let name: String
        let latitude: Double, longitude: Double
        let year: Int, month: Int, day: Int, utcOffset: Double
        let civilDawn: (Int, Int)?, sunrise: (Int, Int)?, noon: (Int, Int), sunset: (Int, Int)?, civilDusk: (Int, Int)?
        let moonrise: (Int, Int)?, moonset: (Int, Int)?
    }

    private let cases = [
        Case(name: "Greenwich", latitude: 51.4769, longitude: -0.0005, year: 2026, month: 6, day: 21, utcOffset: 1,
             civilDawn: (3, 55), sunrise: (4, 43), noon: (13, 2), sunset: (21, 21), civilDusk: (22, 9),
             moonrise: (12, 40), moonset: (0, 34)),
        Case(name: "Sydney", latitude: -33.8688, longitude: 151.2093, year: 2026, month: 12, day: 21, utcOffset: 11,
             civilDawn: (5, 11), sunrise: (5, 41), noon: (12, 53), sunset: (20, 5), civilDusk: (20, 35),
             moonrise: (17, 6), moonset: (2, 29)),
        Case(name: "Quito", latitude: -0.1807, longitude: -78.4678, year: 2026, month: 3, day: 20, utcOffset: -5,
             civilDawn: (5, 57), sunrise: (6, 18), noon: (12, 21), sunset: (18, 24), civilDusk: (18, 45),
             moonrise: (7, 28), moonset: (19, 52)),
        Case(name: "New York", latitude: 40.7128, longitude: -74.0060, year: 2026, month: 10, day: 11, utcOffset: -4,
             civilDawn: (6, 36), sunrise: (7, 3), noon: (12, 43), sunset: (18, 22), civilDusk: (18, 49),
             moonrise: (8, 8), moonset: (18, 31)),
        Case(name: "Tokyo", latitude: 35.6762, longitude: 139.6503, year: 2026, month: 1, day: 15, utcOffset: 9,
             civilDawn: (6, 23), sunrise: (6, 51), noon: (11, 51), sunset: (16, 51), civilDusk: (17, 19),
             moonrise: (3, 59), moonset: (13, 23)),
        Case(name: "Ushuaia", latitude: -54.8019, longitude: -68.3030, year: 2026, month: 9, day: 5, utcOffset: -3,
             civilDawn: (7, 28), sunrise: (8, 4), noon: (13, 32), sunset: (19, 0), civilDusk: (19, 36),
             moonrise: (5, 38), moonset: (11, 16))
    ]

    @Test func sunAndMoonTimesMatchUSNO() {
        for c in cases {
            let tz = TimeZone(secondsFromGMT: Int(c.utcOffset * 3600)) ?? .current
            let observer = GeoCoordinate(latitude: c.latitude, longitude: c.longitude)
            let day = SkyDay(date: time(c.year, c.month, c.day, 12, 0, utcOffset: c.utcOffset), observer: observer, timeZone: tz)
            func at(_ hm: (Int, Int)) -> Date { time(c.year, c.month, c.day, hm.0, hm.1, utcOffset: c.utcOffset) }
            #expect(day.sunVisibility == .risesOrSets, "\(c.name)")
            if let t = c.sunrise { #expect(minutes(day.sunrise, at(t)) <= sunTolerance, "\(c.name) sunrise") }
            if let t = c.sunset { #expect(minutes(day.sunset, at(t)) <= sunTolerance, "\(c.name) sunset") }
            if let t = c.civilDawn { #expect(minutes(day.civilDawn, at(t)) <= sunTolerance, "\(c.name) civil dawn") }
            if let t = c.civilDusk { #expect(minutes(day.civilDusk, at(t)) <= sunTolerance, "\(c.name) civil dusk") }
            #expect(minutes(day.solarNoon, at(c.noon)) <= sunTolerance, "\(c.name) solar noon")
            if let t = c.moonrise { #expect(minutes(day.moonrise, at(t)) <= moonTolerance, "\(c.name) moonrise") }
            if let t = c.moonset { #expect(minutes(day.moonset, at(t)) <= moonTolerance, "\(c.name) moonset") }
        }
    }

    @Test func polarDayAndNightAtTromso() {
        let tromso = GeoCoordinate(latitude: 69.6492, longitude: 18.9553)
        let summer = SkyDay(date: time(2026, 6, 21, 12, 0, utcOffset: 2), observer: tromso,
                            timeZone: TimeZone(secondsFromGMT: 7200)!)
        #expect(summer.sunVisibility == .alwaysUp)
        #expect(summer.sunrise == nil && summer.sunset == nil)
        #expect(summer.civilDawn == nil, "The sun never gets as low as civil twilight")
        #expect(minutes(summer.moonset, time(2026, 6, 21, 0, 37, utcOffset: 2)) <= moonTolerance)
        #expect(minutes(summer.moonrise, time(2026, 6, 21, 12, 18, utcOffset: 2)) <= moonTolerance)

        let winter = SkyDay(date: time(2026, 12, 21, 12, 0, utcOffset: 1), observer: tromso,
                            timeZone: TimeZone(secondsFromGMT: 3600)!)
        #expect(winter.sunVisibility == .alwaysDown)
        #expect(minutes(winter.civilDawn, time(2026, 12, 21, 9, 31, utcOffset: 1)) <= sunTolerance)
        #expect(minutes(winter.civilDusk, time(2026, 12, 21, 13, 53, utcOffset: 1)) <= sunTolerance)
        #expect(winter.moonVisibility == .alwaysUp)
    }

    @Test func principalPhasesMatchUSNO() {
        // USNO, 2026, in UT.
        let expected: [(MoonPhase, Int, Int, Int, Int)] = [
            (.full, 1, 3, 10, 3), (.lastQuarter, 1, 10, 15, 48), (.new, 1, 18, 19, 52), (.firstQuarter, 1, 26, 4, 47),
            (.full, 2, 1, 22, 9), (.lastQuarter, 2, 9, 12, 43), (.new, 2, 17, 12, 1), (.firstQuarter, 2, 24, 12, 27),
            (.full, 3, 3, 11, 38), (.lastQuarter, 3, 11, 9, 38), (.new, 3, 19, 1, 23), (.firstQuarter, 3, 25, 19, 18)
        ]
        let phases = MoonPhase.upcoming(after: time(2026, 1, 1, 0, 0, utcOffset: 0), count: expected.count)
        #expect(phases.count == expected.count)
        for (found, want) in zip(phases, expected) {
            #expect(found.phase == want.0)
            #expect(minutes(found.date, time(2026, want.1, want.2, want.3, want.4, utcOffset: 0)) <= 3,
                    "\(want.0.name) \(want.1)/\(want.2)")
        }
    }
}

struct SkyWindowTests {
    private let greenwich = GeoCoordinate(latitude: 51.4769, longitude: -0.0005)

    @Test func goldenAndBlueHoursBracketSunriseAndSunset() throws {
        let tz = TimeZone(secondsFromGMT: 3600)!
        let day = SkyDay(date: time(2026, 6, 21, 12, 0, utcOffset: 1), observer: greenwich, timeZone: tz)
        #expect(day.goldenHours.count == 2)
        #expect(day.blueHours.count == 2)
        let sunrise = try #require(day.sunrise), sunset = try #require(day.sunset)
        let morningGold = try #require(day.goldenHours.first), eveningGold = try #require(day.goldenHours.last)
        #expect(morningGold.start < sunrise && morningGold.end > sunrise)
        #expect(eveningGold.start < sunset && eveningGold.end > sunset)
        let morningBlue = try #require(day.blueHours.first)
        #expect(abs(morningBlue.end.timeIntervalSince(morningGold.start)) < 2, "Blue hour runs into golden hour")
        #expect(day.moonWaxing)
        #expect(abs(day.moonIllumination - 0.45) < 0.08, "USNO gives 45% that day")
    }

    @Test func noAstronomicalDarknessAtMidsummerInLondon() {
        let night = NightSky(evening: time(2026, 6, 21, 12, 0, utcOffset: 1), observer: greenwich,
                             timeZone: TimeZone(secondsFromGMT: 3600)!)
        #expect(night.darkness.isEmpty)
        #expect(night.coreVisible.isEmpty)
    }

    @Test func milkyWayCoreInADarkSouthernSky() {
        // The night of the 2026 March new moon, outside Sydney: the core rises before dawn.
        let observer = GeoCoordinate(latitude: -33.9, longitude: 151.2)
        let night = NightSky(evening: time(2026, 3, 18, 12, 0, utcOffset: 11), observer: observer,
                             timeZone: TimeZone(secondsFromGMT: 11 * 3600)!)
        #expect(night.moonIllumination < 0.05)
        #expect(!night.darkness.isEmpty)
        #expect(!night.coreVisible.isEmpty)
        #expect(night.coreHours > 3600)
        for window in night.coreVisible {
            #expect(night.darkness.contains { $0.start <= window.start && $0.end >= window.end })
        }
        #expect((night.coreBestAltitude ?? 0) > 30)
    }

    @Test func searchesFindCrossingsAndIntervals() {
        let start = Date(timeIntervalSince1970: 0)
        let range = DateInterval(start: start, duration: 86_400)
        // A sine wave with zero crossings at 6 h and 18 h.
        let wave = { (date: Date) in -cos(date.timeIntervalSince(start) / 86_400 * 2 * .pi) }
        let crossings = SkySearch.crossings(in: range, wave)
        #expect(crossings.count == 2)
        #expect(abs(crossings[0].date.timeIntervalSince(start) - 21_600) < 2)
        #expect(crossings[0].rising && !crossings[1].rising)
        let up = SkySearch.intervals(in: range) { wave($0) > 0 }
        #expect(up.count == 1)
        #expect(abs(up[0].duration - 43_200) < 4)
        let peak = SkySearch.maximum(in: range, wave)
        #expect(abs(peak.timeIntervalSince(start) - 43_200) < 2)
    }

    @Test func compassAndDestination() {
        #expect(AngleMath.compassPoint(0) == "N")
        #expect(AngleMath.compassPoint(359) == "N")
        #expect(AngleMath.compassPoint(112.5) == "ESE")
        #expect(AngleMath.compassPoint(270) == "W")
        let east = GeoCoordinate(latitude: 0, longitude: 0).destination(bearing: 90, distance: 1_000_000)
        #expect(close(east.latitude, 0, 1e-9))
        #expect(close(east.longitude, 8.9932, 0.0001))
        #expect(GeoCoordinate(latitude: 91, longitude: 0).isValid == false)
    }

    @Test func phaseNamesBySector() {
        #expect(MoonPhase.name(elongation: 3) == "New Moon")
        #expect(MoonPhase.name(elongation: 60) == "Waxing Crescent")
        #expect(MoonPhase.name(elongation: 180) == "Full Moon")
        #expect(MoonPhase.name(elongation: 300) == "Waning Crescent")
        #expect(MoonPhase.name(elongation: 350) == "New Moon")
    }
}

struct SkySampleTests {
    @Test func samplesCoverTheRangeAtTheStep() {
        let sky = Sky(observer: GeoCoordinate(latitude: 51.5, longitude: 0))
        let range = DateInterval(start: Date(timeIntervalSince1970: 1_780_000_000), duration: 3600)
        let samples = sky.samples(in: range, step: 600)
        #expect(samples.count == 7)
        #expect(samples.first?.time == range.start)
        #expect(samples.last?.time == range.end)
        #expect(samples.allSatisfy { abs($0.sun) <= 90 && abs($0.moon) <= 91 && abs($0.galacticCenter) <= 90 })
    }
}

struct ShootLightTests {
    private let greenwich = GeoCoordinate(latitude: 51.4769, longitude: -0.0005)
    private let bst = TimeZone(secondsFromGMT: 3600)!

    private func shoot(_ startHour: Int, _ startMinute: Int, hours: Double) -> DateInterval {
        DateInterval(start: time(2026, 6, 21, startHour, startMinute, utcOffset: 1), duration: hours * 3600)
    }

    @Test func anEveningShootGetsTheEveningGoldenHour() throws {
        let windows = ShootLight.goldenHours(for: shoot(19, 0, hours: 3), observer: greenwich, timeZone: bst)
        #expect(windows.count == 1)
        let window = try #require(windows.first)
        // The sun is 6° up about an hour before the 21:21 sunset.
        #expect(window.start > time(2026, 6, 21, 20, 0, utcOffset: 1) && window.start < time(2026, 6, 21, 20, 40, utcOffset: 1))
        #expect(window.end > time(2026, 6, 21, 21, 21, utcOffset: 1))
    }

    @Test func aMorningShootGetsTheMorningGoldenHour() throws {
        let windows = ShootLight.goldenHours(for: shoot(4, 0, hours: 2), observer: greenwich, timeZone: bst)
        #expect(windows.count == 1)
        let window = try #require(windows.first)
        #expect(window.start < time(2026, 6, 21, 4, 43, utcOffset: 1), "It starts before the 04:43 sunrise")
    }

    @Test func aMiddayShootHearsAboutTheEvening() throws {
        let windows = ShootLight.goldenHours(for: shoot(12, 0, hours: 2), observer: greenwich, timeZone: bst)
        #expect(windows.count == 1)
        #expect(try #require(windows.first).start > time(2026, 6, 21, 20, 0, utcOffset: 1))
    }

    @Test func aLongShootGetsEveryWindowItSpans() {
        let windows = ShootLight.goldenHours(for: shoot(3, 0, hours: 20), observer: greenwich, timeZone: bst)
        #expect(windows.count == 2, "Morning and evening")
    }

    @Test func midnightSunWindowsJoinAcrossMidnight() throws {
        // In Tromsø at midsummer the sun skims low around midnight: one golden "hour" over midnight.
        let tromso = GeoCoordinate(latitude: 69.6492, longitude: 18.9553)
        let cest = TimeZone(secondsFromGMT: 7200)!
        let night = DateInterval(start: time(2026, 6, 21, 23, 0, utcOffset: 2), duration: 2 * 3600)
        let windows = ShootLight.goldenHours(for: night, observer: tromso, timeZone: cest)
        #expect(windows.count == 1)
        let window = try #require(windows.first)
        #expect(window.start < time(2026, 6, 21, 23, 0, utcOffset: 2))
        #expect(window.end > time(2026, 6, 22, 1, 0, utcOffset: 2))
    }

    @Test func touchingWindowsMerge() {
        let a = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 100)
        let b = DateInterval(start: Date(timeIntervalSince1970: 100), duration: 100)
        let c = DateInterval(start: Date(timeIntervalSince1970: 500), duration: 100)
        #expect(ShootLight.merge([c, b, a]) == [DateInterval(start: a.start, end: b.end), c])
    }
}

