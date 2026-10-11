# Photography math: methods and sources

The formulas behind `ShutterManager/Models/PhotoMath/` and the film data in
`Models/Catalog/FilmStockCatalog.swift`. Code comments cite the sections here rather than
re-deriving them. The tests (`PhotoMathTests`, `FilmStockTests`, `LightMeterTests`,
`AstronomyTests`) check worked examples from these sources and run on Linux as well as in Xcode
(`Tools/linux/run_foundation_tests.sh`).

Units inside the math: millimetres for lengths, seconds for times, f-numbers for apertures, ISO
arithmetic speed for sensitivity. Views convert to the user's units (`MeasurementUnits`).

## Exposure

- **Exposure value (APEX).** EV = log₂(N²/t), for f-number N and time t in seconds. The scene
  brightness an exposure suits is EV100 = EV − log₂(ISO/100). This is the Additive System of
  Photographic Exposure, introduced in ASA PH2.5-1960.
- **Equivalent exposures** keep N²/(t·ISO) constant:
  - t′ = t·(N′/N)²·(ISO/ISO′);
  - N′ = N·√((t′/t)·(ISO′/ISO));
  - ISO′ = ISO·(N′/N)²·(t/t′).
- **Scales.** Exact values are powers of two in third stops, with the marked labels cameras print:
  - aperture N = 2^(k/6) from f/1 (so f/5.6 is 5.657);
  - shutter t = 2^(−k/3) from 1 s (so 1/250 is 1/256);
  - ISO = 100·2^(k/3).

  Calculations use the exact values, so moving one mark is exactly a third of a stop. Labels snap
  to the nearest mark within a sixth of a stop. The half-stop scales use the common half-stop
  marks.

## ND filters

- **Density.** Optical density D = −log₁₀(transmittance). One stop halves the light, which is
  D = log₁₀ 2 ≈ 0.301.
  - Makers round this to 0.3 per stop: a "0.9" filter is sold as 3 stops, and "3.0" as 10.
  - The app follows the makers' convention (`NDFilter.densityPerStop`).
- **Filter factor** 2^stops: ND8 = 3 stops, ND1000 ≈ 10.
- **Exposure.** Stacked filters add their stops, and the exposure becomes t·2^stops.

## Sunny 16

A long-standing rule of thumb, printed on film instruction leaflets for decades. In bright sun with
distinct shadows, expose f/16 at 1/ISO, and open up one stop per step of duller light:
- f/22 on snow or sand;
- f/11 in slight overcast;
- f/8 in overcast;
- f/5.6 in heavy overcast;
- f/4 in open shade or at sunset.

It assumes a front-lit subject around the middle of the day.

## Light meter

- **Reading.** The camera's auto-exposure picks an aperture N (fixed on a phone), a time t and an
  ISO S. It also reports `exposureTargetOffset`: how many EV its picture is brighter than the
  brightness it aims for. The scene is EV100 = log₂(N²/t) − log₂(S/100) + offset.
  - Auto-exposure keeps the offset near 0. It grows only when the camera runs out of time or ISO,
    in very dark or very bright scenes, and the formula still gives the scene's EV then.
  - Like any reflected-light meter, it assumes the scene averages to mid-grey. Snow reads too dark
    and a black subject too light, unless you meter something mid-toned and hold the reading.
- **Spot metering** sets the camera's exposure point of interest. The camera meters a region
  around that point, not a narrow 1° spot like a spot meter's.
- **Steadying.** The meter samples five times a second. A change of less than 1 EV eases in by 30%
  a sample; a bigger change (pointing at something else) is taken at once.
- **Calibration** is added to every camera reading. Phone cameras aren't built as light meters, so
  they can disagree with a handheld meter. Calibrating against a meter you trust sets it to the
  trusted meter's EV100 minus this one's uncalibrated reading of the same scene, to 0.1 EV,
  within ±5 EV.
- **Solving.** Filters of f stops in front of the lens, which the meter doesn't see, mean the
  exposure must suit EV100 − f. With E = EV100 − f + log₂(S/100):
  - aperture priority: t = N² ÷ 2^E;
  - shutter priority: N = √(t · 2^E);
  - ISO priority: S = 100 · 2^(log₂(N²/t) − (EV100 − f)).

  The solved value snaps to the nearest third-stop mark. One more than a sixth of a stop past
  either end of its scale is flagged as out of range. The exception is a time longer than 30 s,
  which is kept as it is for a bulb exposure.

## Depth of field

Thin-lens formulas, as in S. F. Ray, *Applied Photographic Optics* (3rd ed., Focal Press, 2002),
for focal length f, f-number N, circle of confusion c and focus distance s (from the lens):

- Hyperfocal distance H = f²/(N·c) + f.
- Near limit = s·(H − f)/(H + s − 2f).
- Far limit = s·(H − f)/(H − s) when s < H; infinite otherwise. Focused at H, the near limit is
  exactly H/2.
- Valid for s > f. The formulas overstate depth at macro distances, which the app doesn't offer.

Circle of confusion: the format diagonal divided by a standard.
- Diagonal ÷ 1500 is the common default; for full frame that's 0.029 mm, close to the classic
  0.03 mm.
- The app also offers ÷1000 (lenient), ÷1730 (the figure usually attributed to Zeiss) and ÷3000
  (critical).

Worked example (test): 50 mm, f/8, 5 m, c = 0.03 mm gives H = 10.47 m, near 3.39 m and far 9.53 m.

## Field of view

- **Angle.** For a rectilinear lens focused at infinity, angle = 2·atan(d/2f), where d is the
  format's width, height or diagonal (Ray, as above). A 50 mm lens on 36×24 mm gives 39.6° × 27.0°,
  46.8° diagonal.
- **35mm equivalent** = f × crop factor, where crop factor = 43.27 mm ÷ the format diagonal.
- **Matching focal length** on another format = f × (target diagonal ÷ source diagonal).
- **Frame size at distance D** ≈ D × (format dimension ÷ f), by similar triangles. Accurate when D
  is many focal lengths.

## Astro

- **500 rule:** t = 500 ÷ (f × crop factor). A film-era rule of thumb; stars trail visibly sooner on
  high-resolution sensors.
- **NPF rule,** simplified form: t = (35·N + 30·p) ÷ f.
  - p is the pixel pitch in µm (format width ÷ pixels across), and f the real focal length in mm.
  - Devised by Frédéric Michaud of the Société Astronomique de France.
- **Star trails.** The sky turns 360° in one sidereal day, 86,164.0905 s, which is about 15.041°
  per hour.
  - Rotation in t seconds = 360 · t ÷ 86,164.0905.
  - A stack of frames each lasting e seconds, with gap g between them, over total time T has
    ⌊T ÷ (e + g)⌋ frames.

## Sun and moon

Methods from Jean Meeus, *Astronomical Algorithms*, 2nd edition (Willmann-Bell, 1998).

- **Time.** Universal Time comes from the device clock. Terrestrial Time is UT + ΔT, from Espenak
  and Meeus's polynomial for 2005–2050 (NASA Eclipse Web Site, 2006). For 2026 it gives about 75 s,
  a few seconds off the measured value, which is far below a minute of rise time.
- **Earth.** Nutation in longitude and obliquity, short version (ch. 22, 0.5″); mean and true
  obliquity (22.2); apparent sidereal time at Greenwich (12.4, with the equation of the
  equinoxes). Horizontal coordinates come from 13.5 and 13.6, with azimuth measured from north.
- **Sun.** Chapter 25's low-accuracy method: apparent longitude good to 0.01°, about 2.4 s of
  sunrise time.
- **Moon.**
  - Chapter 47, from the ELP-2000/82 theory: the 60 longitude and distance terms of Table 47.A,
    and the 60 latitude terms of Table 47.B.
  - All 120 rows were checked one by one against an independent transcription, the Go library
    `github.com/soniakeys/meeus` (`moonposition`). Every row matched.
  - The moon is close enough for parallax to matter. Its topocentric altitude is the geocentric
    altitude minus π·cos(altitude), where π is its horizontal parallax.
  - The lit fraction comes from 48.1–48.3.
- **Events.** Each event is a body's altitude crossing a threshold.
  - The altitude is sampled every 10 minutes through the local day (midnight to midnight in the
    place's time zone), and each crossing is bisected to a second.
  - A body that never crosses is reported as up or down all day, which covers the midnight sun
    and polar night.
  - Sunrise and sunset: the sun's centre at −0.8333°, which is 34′ of refraction plus a 16′
    semi-diameter (ch. 15).
  - Moonrise and moonset: the geocentric altitude at h₀ = 0.7275π − 0.5667° (ch. 15).
  - Twilights: civil −6°, nautical −12°, astronomical −18°.
  - Golden hour: the sun from 6° above to 4° below the horizon. Blue hour: 4° to 6° below.
    Photographers' definitions of both vary; these are common ones.
- **Moon phases.** New, first quarter, full and last quarter are the moments the moon's
  elongation from the sun (difference in ecliptic longitude) reaches 0°, 90°, 180° and 270°. They
  are found by searching every 12 hours and bisecting, not with chapter 49's series. Phase names
  split the elongation into eight 45° sectors centred on the principal phases.
- **Checked against the US Naval Observatory.** The tests compare with USNO's "Sun and Moon Data
  for One Day" (Astronomical Applications Department), which rounds to the minute:
  - six places and dates: Greenwich at the June solstice, Sydney at the December solstice, Quito
    at the March equinox, New York, Tokyo and Ushuaia;
  - sunrise, sunset, civil twilight and solar noon came within 0.53 minutes, and moonrise and
    moonset within 0.44 minutes (the tests allow 2 and 5);
  - Tromsø's midnight sun and polar night;
  - the first 12 principal phases of 2026, each within 3 minutes.
- **Meeus's worked examples** 12.a (sidereal time), 25.a (sun), 47.a (moon) and 48.a (lit
  fraction) are tests too.

## Milky Way

- **Galactic centre:** Sagittarius A* at J2000 RA 266.4168°, Dec −29.0078°. It's precessed to
  the date with the annual rates of Meeus 21.1, which are good to a few arcseconds over decades.
- **A night** runs from local noon to the next noon.
  - **Dark:** the sun more than 18° below the horizon (astronomical night).
  - **Moonless:** the moon below its rising altitude.
  - **Core window:** dark and moonless, with the core at least 10° up. Below about 10° the core is
    dimmed by the thicker air near the horizon, and most horizons hide it anyway. This is the
    app's choice of cut-off.

## Time-lapse

- **Frames** = ⌊event duration ÷ interval⌋.
- **Clip length** = frames ÷ fps; **speed-up** = interval × fps.
- **Storage** = frames × file size.
- **For a target clip length:** interval = event ÷ (clip × fps).
- Each exposure should end at least 0.5 s before the next frame, so the camera can write the file.

## Flash

- **Guide number:** GN = distance × f-number, quoted in metres at ISO 100 (ISO 1230 describes how
  guide numbers are determined).
- **ISO.** GN scales with √(ISO/100).
- **Power.** Light output is proportional to power, so GN scales with √(power fraction): half
  power gives GN ÷ √2.
- **Solving:** distance = GN·√(ISO/100) ÷ N, and N = GN·√(ISO/100) ÷ distance.

## Print size

- **Size** = pixels ÷ DPI; DPI = pixels ÷ size.
- **Filling a paper** crops the image to the paper's shape, so the effective resolution is
  min(long pixels ÷ long side, short pixels ÷ short side).
- **Quality bands** follow common print-lab guidance, not a standard:
  - 300 dpi or more for close viewing;
  - 200–300 good;
  - 150–200 for prints seen from a distance.

## Reciprocity

At long exposures, film loses effective speed (reciprocity failure; Schwarzschild, 1900). Each
stock follows its maker's own guidance and nothing else. A maker that publishes nothing gets no
correction, and the app says so rather than borrowing third-party tables.

The engine, `ReciprocityModel`:
- **Power law,** Tc = Tm^P (Harman/Ilford):
  - applies only above 1 s, as Harman's compensation sheet states (below 1 s, Tm^P would shorten
    the time);
  - some Ilford datasheets give ½ s as the no-correction limit, but no correction falls between
    ½ s and 1 s, so the result is the same.
- **Table of metered → corrected times** (Kodak, Fujifilm, Foma):
  - between rows, and from the no-correction limit to the first row, the correction follows a
    straight line on log–log axes;
  - beyond the last row it continues the last segment, flagged as an estimate;
  - past a maker's "not recommended" limit, it's flagged as such.
- **No correction up to X** (Kodak colour negatives): beyond X the app shows the metered time with
  "no figures from the maker".

### How the tables were read
- **Corrections given as aperture openings** (Kodak's "change aperture" rows; Fujifilm's "+⅓ stop
  lens opening") are shown as the equivalent time, metered × 2^stops. The note on each stock says
  when the maker prefers opening up.
- **Foma** gives "lengthening of exposure" multipliers, with the same correction in stops of
  aperture. The multipliers are used.
  - Fomapan 400's datasheet disagrees with itself at 1 s (1.5×, but a full stop of aperture). The
    catalog uses 1.5× and says so.
- **Colour filtration** (Fujifilm's CC filters, Kodak's CC10R for Ektachrome at 120 s) isn't
  computed. The stock's note mentions it.

### Sources (read October 2026)

**Ilford and Kentmere (Harman)**
- Sources:
  - "Film Reciprocity Failure Compensation" (Dec 2023), which gives every P and the 1 s threshold;
  - each film's Technical Information sheet: Pan F Plus; FP4 Plus, HP5 Plus, Delta 400, Delta
    3200, SFX 200 and XP2 Super (Nov 2018); Delta 100 (Apr 2023); Ortho Plus (Oct 2019); Kentmere
    Pan 100 and Pan 400 (Jul 2022).
  - ilfordphoto.com blocks automated downloads, so the files were read from Wayback Machine
    captures of the same download URLs.
- P values:

  | Film | P |
  |---|---|
  | Pan F Plus | 1.33 |
  | FP4 Plus | 1.26 |
  | HP5 Plus | 1.31 |
  | Delta 100 | 1.26 |
  | Delta 400 | 1.41 |
  | Delta 3200 | 1.33 |
  | SFX 200 | 1.43 (from the compensation sheet only; the SFX datasheet has no section) |
  | XP2 Super | 1.31 |
  | Ortho Plus | 1.25 |
  | Kentmere Pan 100 | 1.26 |
  | Kentmere Pan 400 | 1.30 |

- Harman's worked example (HP5 Plus, metered 10 s gives 20.4 s) is a test.

**Kodak** (kodakprofessional.com)

| Datasheet | Film | Guidance |
|---|---|---|
| F-4017 (Oct 2021) | Tri-X 400 | 1 s → 2 s, 10 s → 50 s, 100 s → 1200 s; development −10%, −20%, −30% |
| F-4016 (Jun 2018) | T-Max 100 | 1 s +⅓ stop, 10 s → 15 s, 100 s → 200 s |
| F-4043 (Feb 2016) | T-Max 400 | none to 1 s, 10 s +⅓ stop, 100 s → 300 s |
| F-4001 (Apr 2019) | T-Max P3200 | none to 1 s, nothing beyond |
| E-4051, E-4050, E-4040, E-4046 (Jan 2025) | Portra 160, 400, 800, Ektar 100 | none from 1/10,000 to 1 s; "make tests" beyond |
| E-7022 (Mar 2022) | Gold 200 | as above |
| E-7023 (Feb 2016) | UltraMax 400 | as above; "may require compensation and filtration" |
| E-4000 (Aug 2018) | Ektachrome E100 | none to 10 s; CC10R at 120 s, no exposure change given |

ColorPlus 200 has no datasheet on Kodak's site, so it has no reciprocity data.

**Fujifilm** (asset.fujifilm.com)

| Datasheet | Film | Guidance |
|---|---|---|
| AF3-0221E2 | Velvia 50 | none to 1 s; 4 s +⅓, 8 s +½, 16 s +⅔, 32 s +1 stop; 64 s not recommended |
| AF3-202E | Velvia 100 | none to 1 min; 2 min +⅓, 4 min +½, 8 min +⅔ |
| AF3-036E | Provia 100F | none to 128 s; 4 min +⅓; 8 min not recommended |
| AF3-0258E | Acros 100 II | none below 120 s; +½ stop from 120 to 1000 s |

**Foma** (foma.cz)

| Datasheet | Film | Multipliers at 1 s, 10 s, 100 s |
|---|---|---|
| 05/22 | Fomapan 100 Classic | 2×, 8×, 16× |
| 05/22 | Fomapan 200 Creative | 3×, 9×, 18× |
| 04/23 | Fomapan 400 Action | 1.5×, 6×, 8× |

None of the three needs correction from 1/1000 to ½ s.

**CineStill** product pages give speeds and processes (800T, 50D, 400D; C-41) and no reciprocity
data.

## Development timer

Steps run one after another, each started by hand (you pour between steps). Times come from
wall-clock dates, so the timer stays right in the background. Notifications fire for each
agitation, 10 s before a step ends, and at its end.

Agitation presets follow the small-tank instructions in the makers' film datasheets:
- Ilford (HP5 Plus Technical Information, Nov 2018): "invert the tank four times during the first
  10 seconds, then invert the tank four times again during the first 10 seconds of each further
  minute."
- Kodak (F-4017, Oct 2021): "initial agitation of 5 to 7 inversion cycles in 5 seconds … Then repeat
  this agitation procedure at 30-second intervals."

In a custom pattern, an interval mark that falls inside the initial agitation, or right at its
end, doesn't start a new period.

Recipes store no built-in development times. Times depend on film, developer, dilution and
temperature, so they come from the user's chart.
