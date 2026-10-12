//
//  FilmStockCatalog.swift
//  ShutterManager
//
//  The built-in film stocks. Speeds, processes and reciprocity figures come from each maker's
//  datasheet, cited in `source`; see docs/PHOTO_MATH_REFERENCES.md § Film stocks for how each
//  table was read. A stock whose maker publishes no long-exposure figures is `.unpublished` or
//  `.noCorrectionUpTo`, never filled in from third-party tables.
//
//  IDs are stored and synced: never rename or remove one. Add new stocks anywhere in the list.
//

import Foundation

enum FilmStockCatalog {
    static let all: [FilmStock] = ilford + kodak + fujifilm + foma + cineStill

    // MARK: - Ilford and Kentmere (Harman)

    /// Harman: Tc = Tm^P, with no correction at one second or less ("Film Reciprocity Failure
    /// Compensation", Dec 2023). The individual datasheets give the same P values.
    private static func harman(_ id: String, _ maker: String, _ name: String, iso: Int, process: FilmStock.Process = .blackAndWhite,
                               exponent: Double, source: String, note: String? = nil) -> FilmStock {
        FilmStock(id: id, maker: maker, name: name, iso: iso, process: process,
                  reciprocity: .powerLaw(exponent: exponent, from: 1), reciprocityNote: note, source: source)
    }

    private static let ilford: [FilmStock] = [
        harman("ilfordPanFPlus", "Ilford", "Pan F Plus 50", iso: 50, exponent: 1.33,
               source: "Harman technical information, Pan F Plus"),
        harman("ilfordFP4Plus", "Ilford", "FP4 Plus 125", iso: 125, exponent: 1.26,
               source: "Harman technical information, FP4 Plus (Nov 2018)"),
        harman("ilfordHP5Plus", "Ilford", "HP5 Plus 400", iso: 400, exponent: 1.31,
               source: "Harman technical information, HP5 Plus (Nov 2018)"),
        harman("ilfordDelta100", "Ilford", "Delta 100 Professional", iso: 100, exponent: 1.26,
               source: "Harman technical information, Delta 100 Professional (Apr 2023)"),
        harman("ilfordDelta400", "Ilford", "Delta 400 Professional", iso: 400, exponent: 1.41,
               source: "Harman technical information, Delta 400 Professional (Nov 2018)"),
        harman("ilfordDelta3200", "Ilford", "Delta 3200 Professional", iso: 3200, exponent: 1.33,
               source: "Harman technical information, Delta 3200 Professional (Nov 2018)",
               note: "Rated EI 3200; its ISO speed is 1000."),
        harman("ilfordSFX200", "Ilford", "SFX 200", iso: 200, exponent: 1.43,
               source: "Harman, Film Reciprocity Failure Compensation (Dec 2023)",
               note: "From Harman's reciprocity sheet; the SFX 200 datasheet has no long-exposure section."),
        harman("ilfordXP2Super", "Ilford", "XP2 Super 400", iso: 400, process: .c41, exponent: 1.31,
               source: "Harman technical information, XP2 Super (Nov 2018)",
               note: "A black-and-white film developed in C-41."),
        harman("ilfordOrthoPlus", "Ilford", "Ortho Plus 80", iso: 80, exponent: 1.25,
               source: "Harman technical information, Ortho Plus (Oct 2019)",
               note: "Orthochromatic: ISO 80 in daylight, 40 under tungsten."),
        harman("kentmerePan100", "Kentmere", "Pan 100", iso: 100, exponent: 1.26,
               source: "Harman technical information, Kentmere Pan 100 (Jul 2022)"),
        harman("kentmerePan400", "Kentmere", "Pan 400", iso: 400, exponent: 1.30,
               source: "Harman technical information, Kentmere Pan 400 (Jul 2022)")
    ]

    // MARK: - Kodak

    private static let kodakColorNote = "Kodak gives no figures beyond 1 second: for critical work with longer exposures, make tests."

    private static let kodak: [FilmStock] = [
        FilmStock(id: "kodakTriX400", maker: "Kodak", name: "Tri-X 400", iso: 400, process: .blackAndWhite,
                  reciprocity: .table(uncorrectedUpTo: 0.1, points: [
                      ReciprocityPoint(metered: 1, corrected: 2),
                      ReciprocityPoint(metered: 10, corrected: 50),
                      ReciprocityPoint(metered: 100, corrected: 1200)
                  ]),
                  reciprocityNote: "Kodak also cuts development by 10% at 1 s, 20% at 10 s and 30% at 100 s.",
                  source: "Kodak F-4017 (Oct 2021)"),
        FilmStock(id: "kodakTMax100", maker: "Kodak", name: "T-Max 100", iso: 100, process: .blackAndWhite,
                  reciprocity: .table(uncorrectedUpTo: 0.1, points: [
                      ReciprocityPoint(metered: 1, extraStops: 1.0 / 3),
                      ReciprocityPoint(metered: 10, corrected: 15),
                      ReciprocityPoint(metered: 100, corrected: 200)
                  ]),
                  reciprocityNote: "At 1 s Kodak opens the aperture 1/3 stop rather than lengthening the time.",
                  source: "Kodak F-4016 (Jun 2018)"),
        FilmStock(id: "kodakTMax400", maker: "Kodak", name: "T-Max 400", iso: 400, process: .blackAndWhite,
                  reciprocity: .table(uncorrectedUpTo: 1, points: [
                      ReciprocityPoint(metered: 10, extraStops: 1.0 / 3),
                      ReciprocityPoint(metered: 100, corrected: 300)
                  ]),
                  reciprocityNote: "At 10 s Kodak opens the aperture 1/3 stop rather than lengthening the time.",
                  source: "Kodak F-4043 (Feb 2016)"),
        FilmStock(id: "kodakTMaxP3200", maker: "Kodak", name: "T-Max P3200", iso: 3200, process: .blackAndWhite,
                  reciprocity: .noCorrectionUpTo(seconds: 1),
                  reciprocityNote: "A multi-speed film (nominal EI 800–1000). Kodak gives no figures beyond 1 second.",
                  source: "Kodak F-4001 (Apr 2019)"),
        FilmStock(id: "kodakPortra160", maker: "Kodak", name: "Portra 160", iso: 160, process: .c41,
                  reciprocity: .noCorrectionUpTo(seconds: 1), reciprocityNote: kodakColorNote,
                  source: "Kodak E-4051 (Jan 2025)"),
        FilmStock(id: "kodakPortra400", maker: "Kodak", name: "Portra 400", iso: 400, process: .c41,
                  reciprocity: .noCorrectionUpTo(seconds: 1), reciprocityNote: kodakColorNote,
                  source: "Kodak E-4050 (Jan 2025)"),
        FilmStock(id: "kodakPortra800", maker: "Kodak", name: "Portra 800", iso: 800, process: .c41,
                  reciprocity: .noCorrectionUpTo(seconds: 1), reciprocityNote: kodakColorNote,
                  source: "Kodak E-4040 (Jan 2025)"),
        FilmStock(id: "kodakEktar100", maker: "Kodak", name: "Ektar 100", iso: 100, process: .c41,
                  reciprocity: .noCorrectionUpTo(seconds: 1), reciprocityNote: kodakColorNote,
                  source: "Kodak E-4046 (Jan 2025)"),
        FilmStock(id: "kodakGold200", maker: "Kodak", name: "Gold 200", iso: 200, process: .c41,
                  reciprocity: .noCorrectionUpTo(seconds: 1), reciprocityNote: kodakColorNote,
                  source: "Kodak E-7022 (Mar 2022)"),
        FilmStock(id: "kodakUltraMax400", maker: "Kodak", name: "UltraMax 400", iso: 400, process: .c41,
                  reciprocity: .noCorrectionUpTo(seconds: 1),
                  reciprocityNote: "Kodak: exposures longer than 1 second may need compensation and filtration, with no figures given.",
                  source: "Kodak E-7023 (Feb 2016)"),
        FilmStock(id: "kodakColorPlus200", maker: "Kodak", name: "ColorPlus 200", iso: 200, process: .c41,
                  reciprocity: .unpublished),
        FilmStock(id: "kodakEktachromeE100", maker: "Kodak", name: "Ektachrome E100", iso: 100, process: .e6,
                  reciprocity: .noCorrectionUpTo(seconds: 10),
                  reciprocityNote: "Kodak adds CC10R filtration at 120 s and gives no exposure change there.",
                  source: "Kodak E-4000 (Aug 2018)")
    ]

    // MARK: - Fujifilm

    private static let fujifilm: [FilmStock] = [
        FilmStock(id: "fujiVelvia50", maker: "Fujifilm", name: "Velvia 50", iso: 50, process: .e6,
                  reciprocity: .table(uncorrectedUpTo: 1, points: [
                      ReciprocityPoint(metered: 4, extraStops: 1.0 / 3),
                      ReciprocityPoint(metered: 8, extraStops: 1.0 / 2),
                      ReciprocityPoint(metered: 16, extraStops: 2.0 / 3),
                      ReciprocityPoint(metered: 32, extraStops: 1)
                  ], notRecommendedFrom: 64),
                  reciprocityNote: "Fujifilm gives these as aperture openings, with magenta filtration from 5M at 4 s to 12.5M at 32 s. Not recommended at 64 s or longer.",
                  source: "Fujifilm AF3-0221E2"),
        FilmStock(id: "fujiVelvia100", maker: "Fujifilm", name: "Velvia 100", iso: 100, process: .e6,
                  reciprocity: .table(uncorrectedUpTo: 60, points: [
                      ReciprocityPoint(metered: 120, extraStops: 1.0 / 3),
                      ReciprocityPoint(metered: 240, extraStops: 1.0 / 2),
                      ReciprocityPoint(metered: 480, extraStops: 2.0 / 3)
                  ]),
                  reciprocityNote: "Fujifilm gives these as aperture openings, with 2.5M filtration.",
                  source: "Fujifilm AF3-202E"),
        FilmStock(id: "fujiProvia100F", maker: "Fujifilm", name: "Provia 100F", iso: 100, process: .e6,
                  reciprocity: .table(uncorrectedUpTo: 128, points: [
                      ReciprocityPoint(metered: 240, extraStops: 1.0 / 3)
                  ], notRecommendedFrom: 480),
                  reciprocityNote: "Fujifilm gives this as an aperture opening, with 2.5G filtration. Not recommended at 8 minutes or longer.",
                  source: "Fujifilm AF3-036E"),
        FilmStock(id: "fujiAcros100II", maker: "Fujifilm", name: "Acros 100 II", iso: 100, process: .blackAndWhite,
                  reciprocity: .table(uncorrectedUpTo: 120, points: [
                      ReciprocityPoint(metered: 120, extraStops: 0.5),
                      ReciprocityPoint(metered: 1000, extraStops: 0.5)
                  ]),
                  reciprocityNote: "Fujifilm: open up 1/2 stop from 120 to 1000 seconds; no figures beyond.",
                  source: "Fujifilm AF3-0258E")
    ]

    // MARK: - Foma

    private static let fomaNote = "Foma gives these as multipliers on the metered time, or the same in stops by opening the aperture."

    private static let foma: [FilmStock] = [
        FilmStock(id: "fomapan100", maker: "Foma", name: "Fomapan 100 Classic", iso: 100, process: .blackAndWhite,
                  reciprocity: .table(uncorrectedUpTo: 0.5, points: [
                      ReciprocityPoint(metered: 1, multiplier: 2),
                      ReciprocityPoint(metered: 10, multiplier: 8),
                      ReciprocityPoint(metered: 100, multiplier: 16)
                  ]),
                  reciprocityNote: fomaNote, source: "Foma, Fomapan 100 Classic datasheet (05/22)"),
        FilmStock(id: "fomapan200", maker: "Foma", name: "Fomapan 200 Creative", iso: 200, process: .blackAndWhite,
                  reciprocity: .table(uncorrectedUpTo: 0.5, points: [
                      ReciprocityPoint(metered: 1, multiplier: 3),
                      ReciprocityPoint(metered: 10, multiplier: 9),
                      ReciprocityPoint(metered: 100, multiplier: 18)
                  ]),
                  reciprocityNote: fomaNote, source: "Foma, Fomapan 200 Creative datasheet (05/22)"),
        FilmStock(id: "fomapan400", maker: "Foma", name: "Fomapan 400 Action", iso: 400, process: .blackAndWhite,
                  reciprocity: .table(uncorrectedUpTo: 0.5, points: [
                      ReciprocityPoint(metered: 1, multiplier: 1.5),
                      ReciprocityPoint(metered: 10, multiplier: 6),
                      ReciprocityPoint(metered: 100, multiplier: 8)
                  ]),
                  reciprocityNote: fomaNote + " At 1 s the datasheet gives 1.5× but a full stop of aperture; this uses 1.5×.",
                  source: "Foma, Fomapan 400 Action datasheet (04/23)")
    ]

    // MARK: - CineStill

    private static let cineStill: [FilmStock] = [
        FilmStock(id: "cinestill800T", maker: "CineStill", name: "800T", iso: 800, process: .c41,
                  reciprocity: .unpublished, reciprocityNote: "Tungsten balanced (3200 K).",
                  source: "CineStill product page"),
        FilmStock(id: "cinestill50D", maker: "CineStill", name: "50D", iso: 50, process: .c41,
                  reciprocity: .unpublished, source: "CineStill product page"),
        FilmStock(id: "cinestill400D", maker: "CineStill", name: "400D", iso: 400, process: .c41,
                  reciprocity: .unpublished, source: "CineStill product page")
    ]
}
