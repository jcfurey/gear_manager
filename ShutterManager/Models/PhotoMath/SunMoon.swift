//
//  SunMoon.swift
//  ShutterManager
//
//  Geocentric positions of the sun (Meeus ch. 25, about 0.01°) and the moon (Meeus ch. 47, about
//  10″ in longitude), and the moon's illuminated fraction (ch. 48). Foundation-only. See
//  docs/PHOTO_MATH_REFERENCES.md § Sun and moon.
//

import Foundation

/// The sun's apparent geocentric position.
struct SunPosition: Equatable, Sendable {
    /// Apparent ecliptic longitude, degrees.
    let longitude: Double
    /// Distance in astronomical units.
    let distance: Double
    let equatorial: EquatorialPosition

    /// Meeus ch. 25, "low accuracy": good to 0.01°, about 2.4 s of sunrise time.
    init(_ time: AstroTime) {
        let t = time.centuries
        let l0 = 280.46646 + 36000.76983 * t + 0.000_3032 * t * t
        let m = (357.52911 + 35999.05029 * t - 0.000_1537 * t * t).radians
        let e = 0.016_708_634 - 0.000_042_037 * t - 0.000_000_1267 * t * t
        let c = (1.914_602 - 0.004_817 * t - 0.000_014 * t * t) * sin(m)
            + (0.019_993 - 0.000_101 * t) * sin(2 * m) + 0.000_289 * sin(3 * m)
        let trueLongitude = l0 + c
        let trueAnomaly = m + c.radians
        distance = 1.000_001_018 * (1 - e * e) / (1 + e * cos(trueAnomaly))
        let omega = (125.04 - 1934.136 * t).radians
        longitude = AngleMath.normalized(trueLongitude - 0.005_69 - 0.004_78 * sin(omega))
        let obliquity = EarthOrientation.meanObliquity(time) + 0.002_56 * cos(omega)
        equatorial = SkyCoordinates.equatorial(longitude: longitude, latitude: 0, obliquity: obliquity)
    }
}

/// The moon's apparent geocentric position.
struct MoonPosition: Equatable, Sendable {
    /// Apparent ecliptic longitude and latitude, degrees.
    let longitude: Double
    let latitude: Double
    /// Centre-to-centre distance in kilometres.
    let distance: Double
    let equatorial: EquatorialPosition

    /// Equatorial horizontal parallax, degrees.
    var parallax: Double { asin(6378.14 / distance).degrees }

    /// The periodic-term sums of Meeus ch. 47 (Σl and Σb in 10⁻⁶ degree, Σr in metres) and the
    /// geometric longitude, kept for checking against the book's worked example.
    let sums: (longitude: Double, latitude: Double, distance: Double)
    let geometricLongitude: Double

    init(_ time: AstroTime) {
        let t = time.centuries
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t
        let lp = 218.316_447_7 + 481_267.881_234_21 * t - 0.001_578_6 * t2 + t3 / 538_841 - t4 / 65_194_000
        let d = 297.850_192_1 + 445_267.111_403_4 * t - 0.001_881_9 * t2 + t3 / 545_868 - t4 / 113_065_000
        let m = 357.529_109_2 + 35_999.050_290_9 * t - 0.000_153_6 * t2 + t3 / 24_490_000
        let mp = 134.963_396_4 + 477_198.867_505_5 * t + 0.008_741_4 * t2 + t3 / 69_699 - t4 / 14_712_000
        let f = 93.272_095_0 + 483_202.017_523_3 * t - 0.003_653_9 * t2 - t3 / 3_526_000 + t4 / 863_310_000
        let a1 = 119.75 + 131.849 * t
        let a2 = 53.09 + 479_264.290 * t
        let a3 = 313.45 + 481_266.484 * t
        let e = 1 - 0.002_516 * t - 0.000_007_4 * t2

        func eccentricity(_ mCoefficient: Int) -> Double {
            switch abs(mCoefficient) {
            case 1: return e
            case 2: return e * e
            default: return 1
            }
        }

        var sumL = 0.0, sumR = 0.0, sumB = 0.0
        for term in MoonTables.longitudeDistance {
            let argument = (Double(term.d) * d + Double(term.m) * m + Double(term.mp) * mp + Double(term.f) * f).radians
            let factor = eccentricity(term.m)
            sumL += Double(term.l) * factor * sin(argument)
            sumR += Double(term.r) * factor * cos(argument)
        }
        for term in MoonTables.latitude {
            let argument = (Double(term.d) * d + Double(term.m) * m + Double(term.mp) * mp + Double(term.f) * f).radians
            sumB += Double(term.b) * eccentricity(term.m) * sin(argument)
        }
        // Venus, Jupiter and the Earth's flattening.
        sumL += 3958 * sin(a1.radians) + 1962 * sin((lp - f).radians) + 318 * sin(a2.radians)
        sumB += -2235 * sin(lp.radians) + 382 * sin(a3.radians) + 175 * sin((a1 - f).radians)
            + 175 * sin((a1 + f).radians) + 127 * sin((lp - mp).radians) - 115 * sin((lp + mp).radians)

        sums = (sumL, sumB, sumR)
        geometricLongitude = AngleMath.normalized(lp + sumL / 1_000_000)
        latitude = sumB / 1_000_000
        distance = 385_000.56 + sumR / 1000
        let nutation = EarthOrientation.nutation(time)
        longitude = AngleMath.normalized(geometricLongitude + nutation.longitude)
        equatorial = SkyCoordinates.equatorial(longitude: longitude, latitude: latitude,
                                                obliquity: EarthOrientation.obliquity(time))
    }

    static func == (lhs: MoonPosition, rhs: MoonPosition) -> Bool {
        lhs.longitude == rhs.longitude && lhs.latitude == rhs.latitude && lhs.distance == rhs.distance
    }

    /// The fraction of the disc that's lit, 0–1 (Meeus 48.1–48.3), and whether it's waxing.
    func illumination(sun: SunPosition) -> (fraction: Double, waxing: Bool) {
        let elongation = acos(cos(latitude.radians) * cos((longitude - sun.longitude).radians))
        let sunKilometres = sun.distance * 149_597_870.7
        let phaseAngle = atan2(sunKilometres * sin(elongation), distance - sunKilometres * cos(elongation))
        let waxing = AngleMath.normalized(longitude - sun.longitude) < 180
        return ((1 + cos(phaseAngle)) / 2, waxing)
    }
}

/// Meeus Tables 47.A and 47.B: multiples of D, M, M′, F and the coefficients of the sine terms of
/// longitude (10⁻⁶°), the cosine terms of distance (10⁻³ km) and the sine terms of latitude
/// (10⁻⁶°). Checked row by row against a published implementation of the book (see
/// docs/PHOTO_MATH_REFERENCES.md).
enum MoonTables {
    struct LongitudeDistanceTerm {
        let d: Int, m: Int, mp: Int, f: Int, l: Int, r: Int
    }

    struct LatitudeTerm {
        let d: Int, m: Int, mp: Int, f: Int, b: Int
    }

    private static func ld(_ d: Int, _ m: Int, _ mp: Int, _ f: Int, _ l: Int, _ r: Int) -> LongitudeDistanceTerm {
        LongitudeDistanceTerm(d: d, m: m, mp: mp, f: f, l: l, r: r)
    }

    private static func lat(_ d: Int, _ m: Int, _ mp: Int, _ f: Int, _ b: Int) -> LatitudeTerm {
        LatitudeTerm(d: d, m: m, mp: mp, f: f, b: b)
    }

    static let longitudeDistance: [LongitudeDistanceTerm] = [
        ld(0, 0, 1, 0, 6_288_774, -20_905_355), ld(2, 0, -1, 0, 1_274_027, -3_699_111),
        ld(2, 0, 0, 0, 658_314, -2_955_968), ld(0, 0, 2, 0, 213_618, -569_925),
        ld(0, 1, 0, 0, -185_116, 48_888), ld(0, 0, 0, 2, -114_332, -3_149),
        ld(2, 0, -2, 0, 58_793, 246_158), ld(2, -1, -1, 0, 57_066, -152_138),
        ld(2, 0, 1, 0, 53_322, -170_733), ld(2, -1, 0, 0, 45_758, -204_586),
        ld(0, 1, -1, 0, -40_923, -129_620), ld(1, 0, 0, 0, -34_720, 108_743),
        ld(0, 1, 1, 0, -30_383, 104_755), ld(2, 0, 0, -2, 15_327, 10_321),
        ld(0, 0, 1, 2, -12_528, 0), ld(0, 0, 1, -2, 10_980, 79_661),
        ld(4, 0, -1, 0, 10_675, -34_782), ld(0, 0, 3, 0, 10_034, -23_210),
        ld(4, 0, -2, 0, 8_548, -21_636), ld(2, 1, -1, 0, -7_888, 24_208),
        ld(2, 1, 0, 0, -6_766, 30_824), ld(1, 0, -1, 0, -5_163, -8_379),
        ld(1, 1, 0, 0, 4_987, -16_675), ld(2, -1, 1, 0, 4_036, -12_831),
        ld(2, 0, 2, 0, 3_994, -10_445), ld(4, 0, 0, 0, 3_861, -11_650),
        ld(2, 0, -3, 0, 3_665, 14_403), ld(0, 1, -2, 0, -2_689, -7_003),
        ld(2, 0, -1, 2, -2_602, 0), ld(2, -1, -2, 0, 2_390, 10_056),
        ld(1, 0, 1, 0, -2_348, 6_322), ld(2, -2, 0, 0, 2_236, -9_884),
        ld(0, 1, 2, 0, -2_120, 5_751), ld(0, 2, 0, 0, -2_069, 0),
        ld(2, -2, -1, 0, 2_048, -4_950), ld(2, 0, 1, -2, -1_773, 4_130),
        ld(2, 0, 0, 2, -1_595, 0), ld(4, -1, -1, 0, 1_215, -3_958),
        ld(0, 0, 2, 2, -1_110, 0), ld(3, 0, -1, 0, -892, 3_258),
        ld(2, 1, 1, 0, -810, 2_616), ld(4, -1, -2, 0, 759, -1_897),
        ld(0, 2, -1, 0, -713, -2_117), ld(2, 2, -1, 0, -700, 2_354),
        ld(2, 1, -2, 0, 691, 0), ld(2, -1, 0, -2, 596, 0),
        ld(4, 0, 1, 0, 549, -1_423), ld(0, 0, 4, 0, 537, -1_117),
        ld(4, -1, 0, 0, 520, -1_571), ld(1, 0, -2, 0, -487, -1_739),
        ld(2, 1, 0, -2, -399, 0), ld(0, 0, 2, -2, -381, -4_421),
        ld(1, 1, 1, 0, 351, 0), ld(3, 0, -2, 0, -340, 0),
        ld(4, 0, -3, 0, 330, 0), ld(2, -1, 2, 0, 327, 0),
        ld(0, 2, 1, 0, -323, 1_165), ld(1, 1, -1, 0, 299, 0),
        ld(2, 0, 3, 0, 294, 0), ld(2, 0, -1, -2, 0, 8_752)
    ]

    static let latitude: [LatitudeTerm] = [
        lat(0, 0, 0, 1, 5_128_122), lat(0, 0, 1, 1, 280_602), lat(0, 0, 1, -1, 277_693),
        lat(2, 0, 0, -1, 173_237), lat(2, 0, -1, 1, 55_413), lat(2, 0, -1, -1, 46_271),
        lat(2, 0, 0, 1, 32_573), lat(0, 0, 2, 1, 17_198), lat(2, 0, 1, -1, 9_266),
        lat(0, 0, 2, -1, 8_822), lat(2, -1, 0, -1, 8_216), lat(2, 0, -2, -1, 4_324),
        lat(2, 0, 1, 1, 4_200), lat(2, 1, 0, -1, -3_359), lat(2, -1, -1, 1, 2_463),
        lat(2, -1, 0, 1, 2_211), lat(2, -1, -1, -1, 2_065), lat(0, 1, -1, -1, -1_870),
        lat(4, 0, -1, -1, 1_828), lat(0, 1, 0, 1, -1_794), lat(0, 0, 0, 3, -1_749),
        lat(0, 1, -1, 1, -1_565), lat(1, 0, 0, 1, -1_491), lat(0, 1, 1, 1, -1_475),
        lat(0, 1, 1, -1, -1_410), lat(0, 1, 0, -1, -1_344), lat(1, 0, 0, -1, -1_335),
        lat(0, 0, 3, 1, 1_107), lat(4, 0, 0, -1, 1_021), lat(4, 0, -1, 1, 833),
        lat(0, 0, 1, -3, 777), lat(4, 0, -2, 1, 671), lat(2, 0, 0, -3, 607),
        lat(2, 0, 2, -1, 596), lat(2, -1, 1, -1, 491), lat(2, 0, -2, 1, -451),
        lat(0, 0, 3, -1, 439), lat(2, 0, 2, 1, 422), lat(2, 0, -3, -1, 421),
        lat(2, 1, -1, 1, -366), lat(2, 1, 0, 1, -351), lat(4, 0, 0, 1, 331),
        lat(2, -1, 1, 1, 315), lat(2, -2, 0, -1, 302), lat(0, 0, 1, 3, -283),
        lat(2, 1, 1, -1, -229), lat(1, 1, 0, -1, 223), lat(1, 1, 0, 1, 223),
        lat(0, 1, -2, -1, -220), lat(2, 1, -1, -1, -220), lat(1, 0, 1, 1, -185),
        lat(2, -1, -2, -1, 181), lat(0, 1, 2, 1, -177), lat(4, 0, -2, -1, 176),
        lat(4, -1, -1, -1, 166), lat(1, 0, 1, -1, -164), lat(4, 0, 1, -1, 132),
        lat(1, 0, -1, -1, -119), lat(4, -1, 0, -1, 115), lat(2, -2, 0, 1, 107)
    ]
}
