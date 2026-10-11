//
//  SkyEvents.swift
//  ShutterManager
//
//  When things happen in the sky at a place: sunrise and sunset, twilights, golden and blue
//  hours, moonrise and moonset, moon phases, and the dark hours when the Milky Way's core is up.
//  Foundation-only. Every event is found the same way: sample a body's altitude through the day
//  and refine each threshold crossing by bisection to a second, so polar day and night (no
//  crossing at all) fall out naturally. See docs/PHOTO_MATH_REFERENCES.md § Sun and moon.
//

import Foundation

/// Altitudes that define the sun's events, in degrees, for the centre of the disc without
/// refraction.
enum SunAltitude {
    /// Sunrise and sunset: the upper limb on the horizon, with standard refraction (34′) and the
    /// sun's semi-diameter (16′).
    static let riseSet = -0.8333
    static let civilTwilight = -6.0
    static let nauticalTwilight = -12.0
    static let astronomicalTwilight = -18.0
    /// Golden hour: the sun between 6° above and 4° below the horizon.
    static let goldenHourTop = 6.0
    static let goldenHourBottom = -4.0
    /// Blue hour: the sun between 4° and 6° below the horizon.
    static let blueHourBottom = -6.0
}

/// The galactic centre (Sagittarius A*), J2000.
enum GalacticCenter {
    static let rightAscensionJ2000 = 266.416_837
    static let declinationJ2000 = -29.007_811
    /// The core counts as up for photography above this altitude (degrees).
    static let usefulAltitude = 10.0

    /// Position of date, precessed with the annual rates of Meeus 21.1 (good to a few arcseconds
    /// over decades).
    static func equatorial(_ time: AstroTime) -> EquatorialPosition {
        let years = (time.jde - AstroTime.j2000) / 365.25
        let α = rightAscensionJ2000.radians, δ = declinationJ2000.radians
        let deltaAlpha = (3.075 + 1.336 * sin(α) * tan(δ)) * years * 15 / 3600
        let deltaDelta = 20.04 * cos(α) * years / 3600
        return EquatorialPosition(rightAscension: AngleMath.normalized(rightAscensionJ2000 + deltaAlpha),
                                  declination: declinationJ2000 + deltaDelta)
    }
}

/// A place's sky: positions of the sun, moon and galactic centre at any moment.
struct Sky: Sendable {
    let observer: GeoCoordinate

    func sun(at date: Date) -> HorizontalPosition {
        let time = AstroTime(date)
        return SkyCoordinates.horizontal(SunPosition(time).equatorial, observer: observer, time: time)
    }

    /// The moon's topocentric position: geocentric altitude lowered by the parallax (up to 1°).
    func moon(at date: Date) -> HorizontalPosition {
        let time = AstroTime(date)
        let moon = MoonPosition(time)
        let geocentric = SkyCoordinates.horizontal(moon.equatorial, observer: observer, time: time)
        let topocentric = geocentric.altitude - moon.parallax * cos(geocentric.altitude.radians)
        return HorizontalPosition(altitude: topocentric, azimuth: geocentric.azimuth)
    }

    /// How far the moon's geocentric altitude is above its rising altitude h₀ = 0.7275π − 0.5667°
    /// (Meeus ch. 15): positive while the moon is up.
    func moonAboveHorizon(at date: Date) -> Double {
        let time = AstroTime(date)
        let moon = MoonPosition(time)
        let altitude = SkyCoordinates.horizontal(moon.equatorial, observer: observer, time: time).altitude
        return altitude - (0.7275 * moon.parallax - 0.5667)
    }

    func galacticCenter(at date: Date) -> HorizontalPosition {
        let time = AstroTime(date)
        return SkyCoordinates.horizontal(GalacticCenter.equatorial(time), observer: observer, time: time)
    }

    /// The moon's lit fraction and whether it's waxing.
    static func moonIllumination(at date: Date) -> (fraction: Double, waxing: Bool) {
        let time = AstroTime(date)
        return MoonPosition(time).illumination(sun: SunPosition(time))
    }

    /// Moon minus sun in ecliptic longitude, 0–360°: 0 new, 90 first quarter, 180 full, 270 last.
    static func moonElongation(at date: Date) -> Double {
        let time = AstroTime(date)
        return AngleMath.normalized(MoonPosition(time).longitude - SunPosition(time).longitude)
    }
}

// MARK: - Searching

enum SkySearch {
    /// Where `f` changes sign inside `range`, refined to about a second. `rising` is true where f
    /// goes from negative to positive.
    static func crossings(in range: DateInterval, step: TimeInterval = 600,
                          _ f: (Date) -> Double) -> [(date: Date, rising: Bool)] {
        var results: [(Date, Bool)] = []
        var t0 = range.start
        var v0 = f(t0)
        while t0 < range.end {
            let t1 = min(t0.addingTimeInterval(step), range.end)
            let v1 = f(t1)
            if (v0 < 0) != (v1 < 0) {
                results.append((refine(t0, t1, negativeAtStart: v0 < 0) { f($0) < 0 }, v0 < 0))
            }
            t0 = t1
            v0 = v1
        }
        return results
    }

    /// The stretches of `range` where `condition` holds, with edges refined to about a second.
    static func intervals(in range: DateInterval, step: TimeInterval = 300,
                          where condition: (Date) -> Bool) -> [DateInterval] {
        var results: [DateInterval] = []
        var t0 = range.start
        var c0 = condition(t0)
        var openStart: Date? = c0 ? range.start : nil
        while t0 < range.end {
            let t1 = min(t0.addingTimeInterval(step), range.end)
            let c1 = condition(t1)
            if c0 != c1 {
                // `refine` looks for where "not holding" flips.
                let edge = refine(t0, t1, negativeAtStart: !c0) { !condition($0) }
                if c1 {
                    openStart = edge
                } else if let start = openStart {
                    results.append(DateInterval(start: start, end: edge))
                    openStart = nil
                }
            }
            t0 = t1
            c0 = c1
        }
        if let start = openStart, start < range.end {
            results.append(DateInterval(start: start, end: range.end))
        }
        return results
    }

    /// Bisection between `a` and `b`, where `isNegative` is `negativeAtStart` at `a` and the
    /// opposite at `b`.
    private static func refine(_ a: Date, _ b: Date, negativeAtStart: Bool, _ isNegative: (Date) -> Bool) -> Date {
        var low = a, high = b
        while high.timeIntervalSince(low) > 1 {
            let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            if isNegative(mid) == negativeAtStart { low = mid } else { high = mid }
        }
        return low.addingTimeInterval(high.timeIntervalSince(low) / 2)
    }

    /// The moment `f` peaks within `range` (golden-section search around the best sample).
    static func maximum(in range: DateInterval, step: TimeInterval = 600, _ f: (Date) -> Double) -> Date {
        var best = range.start, bestValue = f(range.start)
        var t = range.start
        while t < range.end {
            t = min(t.addingTimeInterval(step), range.end)
            let value = f(t)
            if value > bestValue { best = t; bestValue = value }
        }
        var low = max(best.addingTimeInterval(-step), range.start)
        var high = min(best.addingTimeInterval(step), range.end)
        let ratio = (5.0.squareRoot() - 1) / 2
        while high.timeIntervalSince(low) > 1 {
            let span = high.timeIntervalSince(low)
            let m1 = high.addingTimeInterval(-ratio * span), m2 = low.addingTimeInterval(ratio * span)
            if f(m1) < f(m2) { low = m1 } else { high = m2 }
        }
        return low.addingTimeInterval(high.timeIntervalSince(low) / 2)
    }
}

// MARK: - A day

/// Whether a body rises and sets on a day, or stays up or down.
enum DayVisibility: Equatable, Sendable {
    case risesOrSets, alwaysUp, alwaysDown
}

/// The sun and moon over one local day (midnight to midnight in `timeZone`).
struct SkyDay: Sendable {
    let interval: DateInterval
    let observer: GeoCoordinate

    let solarNoon: Date
    let sunrise: Date?
    let sunset: Date?
    let sunVisibility: DayVisibility
    let civilDawn: Date?, civilDusk: Date?
    let nauticalDawn: Date?, nauticalDusk: Date?
    let astronomicalDawn: Date?, astronomicalDusk: Date?
    /// Usually a morning and an evening one; one long one in high-latitude winter.
    let goldenHours: [DateInterval]
    let blueHours: [DateInterval]

    let moonrise: Date?
    let moonset: Date?
    let moonVisibility: DayVisibility
    /// At local noon.
    let moonIllumination: Double
    let moonWaxing: Bool

    init(date: Date, observer: GeoCoordinate, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        // Locals, not `self.interval`: the closures below can't capture self before it's set up.
        let day = DateInterval(start: start, end: end)
        interval = day
        self.observer = observer
        let sky = Sky(observer: observer)
        let sunAltitude: (Date) -> Double = { sky.sun(at: $0).altitude }

        let noonPeak = SkySearch.maximum(in: day, sunAltitude)
        solarNoon = noonPeak
        func events(_ threshold: Double) -> (rise: Date?, set: Date?) {
            let crossings = SkySearch.crossings(in: day) { sunAltitude($0) - threshold }
            return (crossings.first { $0.rising }?.date, crossings.last { !$0.rising }?.date)
        }
        let riseSet = events(SunAltitude.riseSet)
        sunrise = riseSet.rise
        sunset = riseSet.set
        if riseSet.rise == nil && riseSet.set == nil {
            sunVisibility = sunAltitude(noonPeak) > SunAltitude.riseSet ? .alwaysUp : .alwaysDown
        } else {
            sunVisibility = .risesOrSets
        }
        let civil = events(SunAltitude.civilTwilight)
        civilDawn = civil.rise
        civilDusk = civil.set
        let nautical = events(SunAltitude.nauticalTwilight)
        nauticalDawn = nautical.rise
        nauticalDusk = nautical.set
        let astronomical = events(SunAltitude.astronomicalTwilight)
        astronomicalDawn = astronomical.rise
        astronomicalDusk = astronomical.set
        goldenHours = SkySearch.intervals(in: day) {
            (SunAltitude.goldenHourBottom...SunAltitude.goldenHourTop).contains(sunAltitude($0))
        }
        blueHours = SkySearch.intervals(in: day) {
            let altitude = sunAltitude($0)
            return altitude >= SunAltitude.blueHourBottom && altitude < SunAltitude.goldenHourBottom
        }

        let moonCrossings = SkySearch.crossings(in: day) { sky.moonAboveHorizon(at: $0) }
        moonrise = moonCrossings.first { $0.rising }?.date
        moonset = moonCrossings.first { !$0.rising }?.date
        if moonCrossings.isEmpty {
            moonVisibility = sky.moonAboveHorizon(at: start) > 0 ? .alwaysUp : .alwaysDown
        } else {
            moonVisibility = .risesOrSets
        }
        let noon = calendar.date(byAdding: .hour, value: 12, to: start) ?? start
        let illumination = Sky.moonIllumination(at: noon)
        moonIllumination = illumination.fraction
        moonWaxing = illumination.waxing
    }
}

// MARK: - Moon phases

enum MoonPhase: Int, CaseIterable, Sendable {
    case new = 0, firstQuarter = 90, full = 180, lastQuarter = 270

    var name: String {
        switch self {
        case .new: return "New Moon"
        case .firstQuarter: return "First Quarter"
        case .full: return "Full Moon"
        case .lastQuarter: return "Last Quarter"
        }
    }

    var systemImage: String {
        switch self {
        case .new: return "moonphase.new.moon"
        case .firstQuarter: return "moonphase.first.quarter"
        case .full: return "moonphase.full.moon"
        case .lastQuarter: return "moonphase.last.quarter"
        }
    }

    /// The next `count` principal phases after `date`: the moments the moon's elongation from the
    /// sun reaches 0°, 90°, 180° and 270°.
    static func upcoming(after date: Date, count: Int) -> [(phase: MoonPhase, date: Date)] {
        var results: [(MoonPhase, Date)] = []
        var t0 = date
        var e0 = Sky.moonElongation(at: t0)
        // Half a day: the elongation grows about 12° a day, so each phase is bracketed once.
        let step: TimeInterval = 43_200
        while results.count < count {
            let t1 = t0.addingTimeInterval(step)
            let e1 = Sky.moonElongation(at: t1)
            for phase in allCases {
                let target = Double(phase.rawValue)
                let before = AngleMath.normalizedSigned(e0 - target), after = AngleMath.normalizedSigned(e1 - target)
                guard before < 0, after >= 0, after - before < 90 else { continue }
                let range = DateInterval(start: t0, end: t1)
                if let crossing = SkySearch.crossings(in: range, step: step, {
                    AngleMath.normalizedSigned(Sky.moonElongation(at: $0) - target)
                }).first {
                    results.append((phase, crossing.date))
                }
            }
            t0 = t1
            e0 = e1
        }
        return results.sorted { $0.1 < $1.1 }.prefix(count).map { ($0.0, $0.1) }
    }

    /// The everyday name for the moon at an elongation: eight 45° sectors centred on the
    /// principal phases.
    static func name(elongation: Double) -> String {
        let names = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                     "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
        return names[Int((AngleMath.normalized(elongation) + 22.5) / 45) % 8]
    }

    static func systemImage(elongation: Double) -> String {
        let images = ["moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter",
                      "moonphase.waxing.gibbous", "moonphase.full.moon", "moonphase.waning.gibbous",
                      "moonphase.last.quarter", "moonphase.waning.crescent"]
        return images[Int((AngleMath.normalized(elongation) + 22.5) / 45) % 8]
    }
}

// MARK: - Night sky

/// One night (local noon to the next noon) for astrophotography.
struct NightSky: Sendable {
    let interval: DateInterval
    /// Astronomical darkness: the sun more than 18° down.
    let darkness: [DateInterval]
    /// Darkness with the moon below the horizon.
    let darkAndMoonless: [DateInterval]
    /// Moonless darkness with the Milky Way's core at least 10° up.
    let coreVisible: [DateInterval]
    /// The moon's lit fraction at local midnight.
    let moonIllumination: Double
    /// The core's highest altitude during moonless darkness, if it's up then.
    let coreBestAltitude: Double?

    init(evening date: Date, observer: GeoCoordinate, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let noon = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: date)) ?? date
        let night = DateInterval(start: noon, duration: 86_400)
        interval = night
        let sky = Sky(observer: observer)
        let dark = SkySearch.intervals(in: night) { sky.sun(at: $0).altitude < SunAltitude.astronomicalTwilight }
        darkness = dark
        let moonless = dark.flatMap { stretch in
            SkySearch.intervals(in: stretch) { sky.moonAboveHorizon(at: $0) < 0 }
        }
        darkAndMoonless = moonless
        let core = moonless.flatMap { window in
            SkySearch.intervals(in: window) { sky.galacticCenter(at: $0).altitude >= GalacticCenter.usefulAltitude }
        }
        coreVisible = core
        moonIllumination = Sky.moonIllumination(at: noon.addingTimeInterval(43_200)).fraction
        coreBestAltitude = core.map { window in
            sky.galacticCenter(at: SkySearch.maximum(in: window, step: 900) { sky.galacticCenter(at: $0).altitude }).altitude
        }.max()
    }

    var coreHours: TimeInterval { coreVisible.reduce(0) { $0 + $1.duration } }
    var moonlessDarkHours: TimeInterval { darkAndMoonless.reduce(0) { $0 + $1.duration } }
}

// MARK: - Samples for charts

/// The altitudes of the sun, moon (topocentric) and galactic centre at one moment.
struct SkySample: Identifiable, Sendable {
    let time: Date
    let sun: Double
    let moon: Double
    let galacticCenter: Double

    var id: Date { time }
}

extension Sky {
    /// Altitudes through `range` every `step` seconds, ends included.
    func samples(in range: DateInterval, step: TimeInterval = 600) -> [SkySample] {
        var result: [SkySample] = []
        var t = range.start
        while t <= range.end {
            result.append(SkySample(time: t, sun: sun(at: t).altitude, moon: moon(at: t).altitude,
                                    galacticCenter: galacticCenter(at: t).altitude))
            t = t.addingTimeInterval(step)
        }
        return result
    }
}
