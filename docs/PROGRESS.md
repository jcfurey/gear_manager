# Progress

Where each milestone in [ROADMAP.md](../ROADMAP.md) stands, what changed from the plan, and what
is still to check on a device. Add a section when a milestone finishes.

| Milestone | Status |
|---|---|
| M1 — Foundation and inventory | Done (2026-10-11) |
| M2 — Tools: calculators and film | Done (2026-10-11) |
| M3 — Light Meter and sky planning | Not started |
| M4 — Shoots | Not started |
| M5 — 1.0 release prep | Not started |

---

## M2 — Tools: calculators and film

**Done 2026-10-11** on `claude/camera-gear-manager-e1zzxt` (commits `087f888`…`df75477`).

### What shipped
- **The Tools tab:** eleven calculators in five groups.
  - Exposure:
    - equivalent exposure;
    - ND filters, stacked, from inventory or presets, with optional film reciprocity and a bulb
      timer;
    - Sunny 16.
  - Optics:
    - depth of field, with near and far limits, hyperfocal distance and a sharp-zone bar;
    - field of view, with angles, 35mm equivalent, frame size at a distance and matching focal
      length on another format.
  - Sky: the NPF and 500 rules from the camera's pixel pitch, and star trails.
  - Calculators: time-lapse, flash guide numbers, and print size with paper sizes.
  - Film: reciprocity correction and the development timer.
- **Filling from inventory:**
  - a camera's format and resolution;
  - a lens's focal length (the short end of a zoom) and widest aperture;
  - ND filters' stops;
  - a flash's guide number.

  Each calculator remembers its last inputs on the device.
- **`PhotoMath`** (`Models/PhotoMath/`, Foundation-only): the math behind every tool, with
  sources in [PHOTO_MATH_REFERENCES.md](PHOTO_MATH_REFERENCES.md).
- **Film stocks:**
  - 33 stocks from Ilford, Kentmere, Kodak, Fujifilm, Foma and CineStill;
  - reciprocity figures from each maker's datasheet for the 29 that publish them;
  - custom stocks with an optional reciprocity exponent.
- **Development recipes:**
  - `DevelopmentRecipe` and `DevelopmentStep`: film, developer, dilution, temperature, and
    ordered steps with agitation;
  - starting templates for B&W, C-41 and E-6 that name the steps but leave the times to the user;
  - covered by export, import (merge and replace), backups and "Delete All Data".
- **Timers:**
  - the bulb timer and the development timer keep running across screens;
  - notifications cover each agitation, a pour warning 10 seconds before a step ends, and the end
    of each step and exposure;
  - the development timer keeps the screen on while it's showing.
- **Settings:** units (automatic, metric or imperial) and the depth-of-field standard (circle of
  confusion d/1000, d/1500, d/1730 or d/3000). Both export and import.
- **Tests:**
  - 37 Foundation-only tests (math and film catalog), which run on Linux too;
  - unit tests for recipes, timer alerts, timers and settings, bringing the total to 122;
  - 3 new UI tests: every tool opens, depth of field shows results, and create a recipe and run
    its timer.

### Verified
[CI run 38141822666](https://github.com/jcfurey/gear_manager/actions/runs/38141822666) passed
every job:
- the Foundation tests in the Swift 6.2 Linux image;
- the Debug and Release builds with warnings as errors;
- 122 unit tests;
- 8 UI tests on each of iPhone 17 and iPad (iOS 26.5).

### Changes from the plan
- **Reciprocity data comes only from makers' datasheets.**
  - Kodak ColorPlus 200 and the three CineStill films have no published figures, so the app shows
    the metered time and says so. Kodak's colour negatives have figures only up to 1 second.
  - Ilford's sheets were read from Wayback Machine captures, because ilfordphoto.com blocks
    automated downloads.
- **Agitation presets were checked against the datasheets.**
  - Ilford: four inversions in the first 10 s of each minute.
  - Kodak: 5–7 inversions in 5 s, every 30 s. The first draft's Kodak preset was wrong and was
    corrected before shipping.
- **Not in the plan:**
  - the ND calculator can apply a film's reciprocity correction;
  - the development timer has a pour warning;
  - recipes carry no built-in development times (they depend on film, developer, dilution and
    temperature).
- **New shared code:**
  - `LibraryContents`, the one place export and backups read the library from;
  - `ModelContext.deleteEveryRecord()`, which covers every model for replace-import and Delete All
    Data.

  Both keep M3 and M4's new models from being missed.
- **CI:** a Linux job runs the Foundation-only tests in the official Swift image, pinned by
  digest. It also keeps `PhotoMath` free of Apple-only frameworks.
- **The sun and moon planner** stays in M3, as planned. The Sky group has Astro Exposure for now.

### Found by CI and fixed
- A default argument (`= .shared`) read a main-actor singleton from outside the main actor. It
  was the only compile error.

### Still to check on a device
- Timer notifications with the phone locked and silent; the development timer through a real
  development; the bulb timer on a long exposure.
- The new models need the CloudKit schema updated. Run `-initializeCloudKitSchema` again and
  review `DevelopmentRecipe` and `DevelopmentStep` in CloudKit Console, then check recipe sync
  between two devices.
- The units setting in a US region (Automatic should show feet and °F).

---

## M1 — Foundation and inventory

**Done 2026-10-11** on `claude/camera-gear-manager-e1zzxt` (commits `39b6b7b`…`9b27c91`).

### What shipped
- **Project:**
  - `ShutterManager.xcodeproj` with folder-synced groups, plus app, unit-test and UI-test targets;
  - bundle ID `jcameronfurey.shuttermanager` and CloudKit container
    `iCloud.jcameronfurey.shuttermanager`;
  - an aperture app icon;
  - the license line from Axe Manager.
- **CI:** one workflow (`.github/workflows/ci.yml`; see [CI.md](CI.md)). Every job must pass for
  **CI result** to pass:
  - convention checks, actionlint and ShellCheck;
  - a Debug simulator build with warnings as errors, and the unit tests with coverage;
  - an unsigned Release device build;
  - UI tests on iPhone and iPad.
- **Platform layer from Axe Manager:**
  - the store with its CloudKit → local-only → recovery fallback;
  - backups, import validation, photos, barcode lookup, shared views and the Tip Jar.
- **Models:**
  - `GearItem` with the camera fields from the roadmap;
  - `ShutterCountReading`, `GearLoan`, and the adapted maintenance records and reminders;
  - catalogs: `GearCategory` (12 categories), `SensorFormat` (22 built-in formats plus custom
    sizes) and `LensMount`.
- **Inventory:**
  - a form that shows the right fields for each category, with edits made on a detached draft;
  - fill from a photo's metadata, including the shutter count from Nikon bodies;
  - shutter-count history with a chart against the rated shutter life;
  - loans and rentals, sensor-cleaning reminders and the maintenance log;
  - purchase price plus an optional current value, collection stats (by category and by mount)
    and marketplace links;
  - status badges.
- **Data:**
  - JSON export and import (merge or replace) cover every M1 model, and so do backups;
  - CSV and PDF inventories;
  - the export format is versioned (`formatVersion` 1), and files from a newer version are refused.
- **Tests:**
  - 69 unit tests: catalogs and stable IDs, model defaults, EXIF fixtures (including a real JPEG
    written and read back through ImageIO), export/import round trips, import validation, backups,
    maintenance and reminders;
  - 5 UI tests on each device: launch and tabs, add gear, edit and cancel, log a shutter count,
    lend and return.

### Verified
[CI run 38117682416](https://github.com/jcfurey/gear_manager/actions/runs/38117682416) passed
every job, on iPhone 17 and iPad (iOS 26.5) with Xcode 26.6. It took about 8 minutes.

### Changes from the plan
- **One CI workflow instead of three.** Change detection skips the macOS jobs for docs-only
  changes. UI tests run on pull requests, on `main`, and on manual runs with `ui_tests: true`.
- **Maintenance types:** the roadmap's "AF calibration" is a general **Calibration** type, and a
  general **Cleaning** type was added.
- **Extra `GearItem` fields:**
  - `sensorCleaningIntervalDays` and `lastSensorCleaningDate`, behind the sensor-cleaning
    reminders;
  - `reminderHour` and `reminderMinute`, the time of day an item's reminders fire.
- **Marketplace links:**
  - eBay and Google search directly;
  - MPB, KEH, B&H and Adorama open a Google search restricted to that site, until each site's own
    search URL is checked on a device.
- **Settings deferred to the milestones that use them:**
  - distance units and the default circle of confusion, to M2 (depth of field);
  - light-meter calibration, to M3.
- **The `FilmStock` catalog** moves to M2, where reciprocity needs it.

### Found by CI and fixed
- **iPad hid Add Gear.** On iPadOS 26 the tab bar shares the navigation bar's row, leaving room
  for about two trailing toolbar buttons. With Sort & Filter, Add and Search all trailing, Add Gear
  folded into a "More" menu. Sort & Filter now sits on the leading side, and Add Gear is the primary
  action. The rule is in CLAUDE.md.
- **VoiceOver read iPad cards category first.** Rows and cards now share a name-first summary.
- **The unit-test host opened the real library.** It now gets a temporary in-memory library,
  which cut the unit-test step from about 7 minutes to 4.
- **A 21-element array literal timed out the type checker.** It now has an explicit type.

CI also got easier to diagnose: a failed UI test's summary now shows the app's accessibility
hierarchy at the failure.

### Still to check on a device
- Register the App ID and the iCloud container, and turn on Background Modes → Remote
  notifications.
- Run the app with `-initializeCloudKitSchema` once to create the Development schema, and review
  it in CloudKit Console.
- Fill from a photo with your own bodies and lenses, especially the serial number, the lens
  details, and the shutter count from Nikon bodies.
- iCloud sync between two devices.
- The MPB, KEH, B&H and Adorama search URLs.
