# Photography math: methods and sources

The formulas behind `ShutterManager/Models/PhotoMath/`, the film data in
`Models/Catalog/FilmStockCatalog.swift` and the lens-mount table in
`Models/Catalog/MountCompatibility.swift`. Code comments cite the sections here rather than
re-deriving them. The tests (`PhotoMathTests`, `FilmStockTests`, `LightMeterTests`,
`AstronomyTests`, `MountCompatibilityTests`) check worked examples from these sources and run on
Linux as well as in Xcode (`Tools/linux/run_foundation_tests.sh`).

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

## A shoot's golden hours

`ShootLight` picks the golden hours a shoot's heads-up is about. It uses the same windows as the
sun and moon planner (the sun from 6° above to 4° below the horizon), in the place's time zone:
- the windows that overlap the shoot, on the days it spans (up to three);
- if none overlap, the first one after the shoot starts, so a midday shoot hears about the
  evening light;
- a window that runs past midnight, as near the poles in summer, counts as one.

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

## Lens mounts

`Models/Catalog/MountCompatibility.swift` says how a lens goes on a body: the same mount, a
maker's own adapter, or room for a plain one. `MountCompatibilityTests` checks the table against
itself and runs on Linux too.

**The rule.** A lens focuses to infinity only when its mount sits at its own flange focal
distance (mount face to film or sensor). So a lens can be adapted with a spacer, an adapter with
no glass, only to a body whose flange distance is shorter. Wikipedia's "Flange focal distance"
puts it as: "A camera body with a shorter FFD can accept a larger number of lenses (those with a
longer FFD) by using a simple adapter."
- **Room** = lens mount's distance − body mount's distance, rounded to 0.01 mm.
- **1 mm or more** is listed as room for a plain adapter, "if one is made for this pair". 1 mm is
  the gap between M39 (28.8 mm) and Leica M (27.8 mm), which an adapter ring does fill.
- **Less than that** is listed as not fitting: the lens would sit too far out, so an adapter
  needs its own glass or the lens won't reach infinity.
- The rule knows nothing of the mounts' diameters, or of lenses that need power for focus and
  aperture. The app says so beside each result, and never says an adapter exists unless its
  maker does.

**Flange distances** are from the "Standard mounts" table in
[Wikipedia, Flange focal distance](https://en.wikipedia.org/wiki/Flange_focal_distance), read
November 2026. Where the table gives a range or two values, the app uses the first:
- Leica M: 27.8 mm (27.95 mm at the outer rails).
- Pentax 67: 84.95 mm (also given as 85.00).
- Contax/Yashica: 45.5 mm, the Contax C/Y row.
- Minolta MD: 43.5 mm, the Minolta SR row (MD lenses use the SR mount).

| Mount | mm | Mount | mm | Mount | mm |
|---|---|---|---|---|---|
| Canon RF | 20.0 | Canon EF, EF-S | 44.0 | Leica M | 27.8 |
| Canon EF-M | 18.0 | Nikon F | 46.5 | Leica R | 47.0 |
| Nikon Z | 16.0 | Sony A | 44.5 | Canon FD | 42.0 |
| Sony E | 18.0 | Pentax K | 45.46 | Minolta MD | 43.5 |
| Fujifilm X | 17.7 | Four Thirds | 38.67 | Olympus OM | 46.0 |
| Fujifilm G | 26.7 | Sigma SA | 44.0 | Contax/Yashica | 45.5 |
| L-Mount | 20.0 | Pentax 645 | 70.87 | M42 | 45.46 |
| Micro Four Thirds | 19.25 | Pentax 67 | 84.95 | M39 | 28.8 |
| Hasselblad XCD | 18.14 | Hasselblad H | 61.63 | Hasselblad V | 74.9 |
| Nikon 1 | 17.0 | Mamiya 645 | 63.3 | Mamiya RB67 | 112.0 |
| Samsung NX | 25.5 | | | Mamiya RZ67 | 105.0 |

**Canon EF and EF-S.** A body listed as Canon EF-S (crop sensor) takes EF lenses; an EF-S lens
doesn't go on a body listed as Canon EF (full frame). Wikipedia, "Canon EF-S lens mount": "By
design, it is physically impossible to mount EF-S lenses on EF-only cameras", and "Cameras with
the EF-S mount are backward compatible with the EF lenses."

**Makers' own adapters** (`MountCompatibility.makerAdapters`). Each is listed because its maker
says which lenses it puts on which bodies. Pages read November 2026; several are no longer sold.

| Adapter | Lenses → bodies | Source |
|---|---|---|
| Canon Mount Adapter EF-EOS R | EF, EF-S → RF | [Canon](https://asia.canon/en/consumer/mount-adapter-ef-eos-r/main/product): "Enables EF / EF-S lenses to be mounted onto EOS R cameras" |
| Canon Mount Adapter EF-EOS M | EF, EF-S → EF-M | [Canon](https://asia.canon/en/consumer/mount-adapter-ef-eos-m/main/product) |
| Nikon Mount Adapter FTZ II | F → Z | [Nikon](https://imaging.nikon.com/imaging/lineup/accessory/camera/ftz_2/) |
| Nikon Mount Adapter FT1 | F → Nikon 1 | [Nikon, 2011](https://www.nikon.com/company/news/2011/0921_acc_03/): "enables the use of F-mount lenses with Nikon 1 system cameras" |
| Sony LA-EA5 Mount Adaptor | A → E | [Sony Help Guide](https://helpguide.sony.net/ilc/2040/v1/en/contents/TP1000384668.html) |
| Olympus Four Thirds Adapter MMF-3 | Four Thirds → Micro Four Thirds | [Olympus, 2012](https://www.olympus-global.com/en/news/2012a/nr120208em5e.html) |
| Olympus OM Adapter MF-1, MF-2 | OM → Four Thirds; OM → Micro Four Thirds | [OM System support](https://support.jp.omsystem.com/en/support/imsg/digicamera/compati/di004042e_om.html) |
| Leica M-Adapter L | M → L-Mount | [Leica](https://classic.leica-camera.com/en/Leica-M-Adapter-L-black/18771SH-24092026): "allows all Leica M lenses to be used on cameras with an L-mount" |
| Leica R-Adapter L | R → L-Mount | [Leica](https://leica-camera.com/en-US/photography/accessories/adapters/r-adapter-l) (the page's text couldn't be read; the mounts are from a dealer's description) |
| Leica R-Adapter M | R → M | [Leica](https://leica-camera.com/en-GB/photography/accessories/adapters/r-adapter-m-black-lacquered/shop-now) (as above; the mounts are from Leica's 2012 release as reprinted) |
| Hasselblad XH Lens Adapter | H → XCD | [Hasselblad](https://www.hasselblad.com/x-system/accessories/xh-lens-adapter/) |
| Hasselblad XV Lens Adapter | V → XCD | [Hasselblad](https://www.hasselblad.com/x-system/accessories/xv-lens-adapter/) |
| Hasselblad CF Adapter | V → H | [Hasselblad](https://www.hasselblad.com/h-system/accessories/cf-adapter/) |
| Fujifilm M Mount Adapter | Leica M → X | [Fujifilm](https://www.fujifilm-x.com/global/products/accessories/m-mount-adapter/) |
| Fujifilm H Mount Adapter G | Hasselblad H → G | [Fujifilm](https://www.fujifilm-x.com/global/products/accessories/h-mount-adapter-g/) (manual focus only) |
| Sigma Mount Converter MC-21 (SA-L) | Sigma SA → L-Mount | [Sigma](https://www.sigma-global.com/en/accessories/mc-21/) |
| Sigma Mount Converter MC-11 (SA-E) | Sigma SA → Sony E | [Sigma](https://www.sigma-global.com/en/accessories/mc-11/) |
| Pentax Mount Adapter K | M42 → K | [Ricoh Imaging](https://www.ricoh-imaging.co.jp/english/support/qa/k-1/index.html) |
| Pentax Adapter K for 645-System Lenses | 645 → K | [Ricoh Imaging](https://www.ricoh-imaging.co.jp/english/products/filmcamera/accessory/index645n2_others.html) |
| Pentax Adapter K for 67-System Lenses | 67 → K | Ricoh Imaging's K-1 questions and answers, above |
| Pentax Adapter 645 for 67-System Lenses | 67 → 645 | Ricoh Imaging's accessory page, above |

**Left out on purpose.**
- Sigma also sells the MC-21 and MC-11 in Canon EF versions. Sigma describes them as for its own
  EF-mount lenses, so the app doesn't name them for every Canon EF lens: EF lenses on L-Mount and
  Sony E bodies are listed by their room for a plain adapter.
- The ring that puts M39 lenses on Leica M bodies. One is on Leica's own second-hand store, but
  the page doesn't name its maker, so that pair is listed by its 1 mm of room.
- Adapters from other brands. There are many, and no one source for which exist: the app shows
  the room and leaves the search to the user. An adapter the user owns is entered as a lens whose
  mount names both sides ("Canon EF → Sony E") and then counts for that pair, whatever the
  arithmetic says, since it may have glass in it.

**Format.** A lens is flagged as made for a smaller format when its format's diagonal is under
0.9 of the body's. The margin keeps one maker's APS-C lens from being flagged on another's
slightly larger APS-C sensor.


## Cloud forecast

The numbers are Apple Weather's, through WeatherKit; the app works none of them out. What the
code relies on, from Apple's pages (read November 2026):

| What | Source |
|---|---|
| An hourly forecast reaches ten days ahead, and one request returns at most ten days (about 240 hours), from the start date up to but not including the end date. | [`WeatherQuery.hourly(startDate:endDate:)`](https://developer.apple.com/documentation/weatherkit/weatherquery/hourly(startdate:enddate:)) |
| `cloudCover` is the share of the sky covered with cloud; `cloudCoverByAltitude` splits it into low (up to 1,800 m above the model's surface), medium (1,800 to 6,300 m) and high (above 6,300 m). | [`HourWeather`](https://developer.apple.com/documentation/weatherkit/hourweather), [`CloudCoverByAltitude`](https://developer.apple.com/documentation/weatherkit/cloudcoverbyaltitude) |
| Weather data from Apple is shown with the Apple Weather trademark and the legal link to its other data sources. | [WeatherKit, "Apple Weather and third-party attribution"](https://developer.apple.com/weatherkit/) |
| 500,000 requests a month come with the Apple Developer Program membership. | The same page |
| Apple uses the location only to provide the forecast, doesn't associate it with anything that identifies the user, and doesn't track it between requests. | The same page, "Privacy first" |

**A window's clouds** (a golden hour, a night's dark hours, a shoot) are the mean of its hours,
each weighed by how much of the window it holds; the chance of precipitation is the highest
among them; the words and symbol are those of the hour that holds most of it. A window that
runs past the forecast's last hour gets no summary, rather than one for the part that's known.

**The words** for each hour ("Mostly Clear") are Apple's `WeatherCondition`. The app sets no
thresholds of its own between clear and cloudy.

**Where it's asked for.** The place's coordinates are rounded to two decimal places before they
are sent, about 1.1 km of latitude: finer than a forecast's grid, and coarser than where anyone
stood.
