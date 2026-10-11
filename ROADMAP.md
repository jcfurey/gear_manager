# Shutter Manager — Product Roadmap

A camera-gear manager with field tools for photographers, built on the platform layer of Cam's Axe
Manager. This is the product plan. Keep it current so later sessions can pick up from a clean
working tree. [docs/PROGRESS.md](docs/PROGRESS.md) records where each milestone stands and what
changed from this plan.

> **Stack (same as Axe Manager):** SwiftUI + SwiftData + CloudKit private sync, iOS 18.6+, iPhone
> and iPad, Xcode 26, Swift 5 language mode, Apple frameworks only. **Zero external dependencies,
> no backend, "Data Not Collected."** Any feature that breaks those (a server, a third-party SDK,
> data collection) is a deliberate architectural decision, not a quick win.

---

## Decisions so far

| Topic | Decision |
|---|---|
| Name | **Shutter Manager** |
| Bundle ID | `jcameronfurey.shuttermanager` (tests `.tests`, UI tests `.uitests`) |
| CloudKit container | `iCloud.jcameronfurey.shuttermanager` |
| Apple team | Same as Axe Manager |
| Audience | Hobby, paid client work, film, video and drones |
| Devices | iPhone + iPad, iOS 18.6+ |
| Tabs | **Inventory · Tools · Light Meter · Shoots · Settings** |
| Pricing | Purchase price plus an optional current value you update yourself, and marketplace search links. No price history, no price alerts, no server, no price feed |
| Money | Free, with a Tip Jar. **No Pro mode**: every feature is free, now and later |
| Categories | The list under Inventory, open to additions later |
| Shot lists | Built-in and saved templates in v1 |
| Code | Copied from Axe Manager into a new project here; Axe Manager is not changed |
| License | Same as Axe Manager ("For educational and personal use"); replaces Apache 2.0 before any code lands |
| Location | Current location (asked on first use, while in use only) plus a map picker and saved places |
| Migration | None. Start fresh, no import from Axe Manager |

---

## What carries over from Axe Manager

**Keep, renamed only**
- App shell: `AppStoreController` (CloudKit → local fallback → `StoreRecoveryView`),
  `iCloudSyncManager`, `CloudKitSchemaInitializer`, `AppSchema`, `PreviewModelContainer`.
- Data safety: `BackupManager`, `ImportDocument`, `ImportedSettings`, `DataImportService`,
  `ModelContext+Save`, `PersistenceErrorAlert`, `GearRelationshipSnapshot`.
- Photos: `GearPhoto`, `PhotoIngest`, `ThumbnailCache`, `PhotoGalleryView`.
- Shared UI and utilities: everything in `Views/Shared/`, `AppColors`, `ResponsiveDesign`,
  `AnimationUtilities`, `AccessibilityUtilities`, `CurrencyFormatter`, `DateFormatters`,
  `MeasurementInput`, `Decimal+Extensions`, `String+Extensions`, `HapticFeedbackManager`.
- Barcode: `BarcodeScannerService`, `BarcodeScannerView`, `UPCLookupService`, `ProductInfoView`.
- Collection value: the collection overview card.
- Tip Jar: `TipJarStore`, `TipJarView`, with new product IDs `jcameronfurey.shuttermanager.tip.*`.

**Adapt**
- `GearItem`: drop the guitar fields, add camera fields (see Data model).
- `GearValuationService`: an item's value is its current value, else its purchase price (the
  price-history step in between goes).
- `MaintenanceRecord`, `MaintenanceReminder`, `MaintenanceService`: camera maintenance types;
  string-change reminders become sensor-cleaning and service reminders.
- `NotificationManager`: drop practice, streak and string reminders; add maintenance, loan-due,
  timer and golden-hour notifications.
- `DataExportService` (JSON, CSV, PDF): DTOs for every new model; `replaceUnrestorableNumbers`
  covers every new `Double` field, kept in step with `ImportDocument.validate`.
- `MarketplaceSearch`: MPB, KEH, eBay, B&H, Adorama and Google. eBay and Google take a query in
  the URL. The cloud session couldn't confirm the others' own search URLs (MPB ignored the query
  parameter), so they open a Google search restricted to that site. Switch to a site's own search
  once its URL format is checked on a device.
- `Constants`: new namespaces; tuner, metronome and tension removed.
- Inventory and Settings screens, `AboutView`.
- CI, now one workflow (`ci.yml`; see `docs/CI.md`), and UI-test support (`-uiTestInMemory`,
  `-uiTestStoreFailure`).
- Test suites for data, backup, import/export, CloudKit compatibility and photo ingest.

**Leave behind**
- Tuner and the whole audio stack, `AudioSessionManager`, metronome.
- String tension, Practice and Learn, tunings and temperaments.
- `SerialNumberDecoder` (guitar brands only).
- `MarketValuation`: in Axe Manager it is only export and backup plumbing; nothing creates one.
- Price history and alerts: `PriceEntry`, `PriceAlert`, `PriceAlertManager`, and the trend chart
  and price-entry views (`PriceTrendsChart`, `AddPriceEntryView`, `TimeRangePicker`,
  `PriceAlertsView`). The app tracks what you paid plus an optional current value, so a dated log
  and alerts on prices you type yourself add little.

---

## Tabs

### Inventory
- **Categories** (stored as stable IDs, never renamed): Camera Body · Lens · Flash & Lighting ·
  Support (tripods, gimbals, sliders) · Filter · Drone · Audio · Battery & Power · Memory Card ·
  Bag & Case · Accessory · Other. A film camera is a Camera Body with a film format. The list is
  open: a new category is an additive change (a new ID, plus any fields it needs, all defaulted),
  so it can be added in any release without a migration.
- **Add**: by hand, by barcode (with optional UPC lookup), or **from a photo's EXIF data**.
- **Detail**: sections shown by category; photos; maintenance log; purchase price, current value
  and marketplace links; shutter-count history; loans.
- **Status badges**: needs service, on loan / rented, shutter near rated life, sensor cleaning due.
- **Collection stats**: total value (current value, else purchase price), by category, by mount.

### Tools
A grouped list:
- **Exposure**: equivalent exposure · ND filter with bulb timer · Sunny 16
- **Optics**: depth of field and hyperfocal · field of view and crop
- **Sky**: sun and moon planner · Milky Way planner (dark, moonless hours with the core up) ·
  astro exposure (500 and NPF rules, star trails)
- **Calculators**: time-lapse · flash guide number · print size and DPI
- **Film**: reciprocity · development timer

Tools fill in from inventory where it helps: lens focal length and aperture, body format and
resolution, filter strength, flash guide number. Every value can still be typed by hand.

### Light Meter
- Live reflected reading from the iPhone camera, shown as EV100.
- Aperture, shutter or ISO priority; results snapped to standard 1/3-stop values.
- Spot (tap to meter) or average; hold a reading; calibration offset; filter compensation.
- ISO can come from the film roll loaded in a body you pick.
- Send a reading to the ND calculator.

### Shoots
- **Shoot log**: date, location (with that day's sun times), client, type, gear used, notes.
- **Kits and packing lists**: saved kits ("wedding", "astro"); a pre-shoot check-off that flags
  items that are on loan or need service.
- **Shot lists**: per shoot, ticked off on the day. Start one from a template: built-in starters
  (wedding, engagement, portrait session, event, real estate, product) or your own. Any shoot's
  list can be saved as a new template. Applying a template copies its items into the shoot, so
  editing a template later never changes past shoots.
- **Film roll log**: stock, format, camera, rated ISO, push/pull, frames, and status
  (loaded → shot → at lab → developed → scanned).
- **Usage per item**: number of shoots and last used, derived from the log.

### Settings
As in Axe Manager: iCloud status, backups, export/import, recovery, notifications, Tip Jar, About
and privacy. New: distance units (follow the device locale, with an override), light-meter
calibration, default circle of confusion.

---

## Data model

Same rules as Axe Manager, and `AppSchema` stays the single model list: no `@Attribute(.unique)`, a
default on every non-optional attribute, optional relationships with inverses, no `.deny` delete
rules. Stored catalog IDs (categories, sensor formats, mounts, film stocks, maintenance types) are
stable strings: **never rename or remove one.**

### `GearItem` (adapted)
Kept: identity and dates, category, make, model, purchase date and price, current value, notes,
UPC, serial number, year made, service flag and notes, reference links, photos, maintenance.

New flat fields (`0` or `""` means not set):

| Field | Type | Used for |
|---|---|---|
| `mount` | String (mount ID or free text) | body, lens, adapter |
| `sensorFormatID` | String (`SensorFormat` ID) | body, drone; lens's intended format |
| `resolutionWidthPx`, `resolutionHeightPx` | Int | pixel pitch for the NPF rule |
| `focalLengthMin`, `focalLengthMax` | Double, mm | lens (equal for a prime) |
| `maxApertureWide`, `maxApertureTele` | Double, f-number | lens |
| `minFocusDistance` | Double, m | lens |
| `filterThread` | Double, mm | lens, filter |
| `filterStops` | Double | ND filter (feeds the ND calculator) |
| `guideNumber` | Double, m at ISO 100 | flash (feeds the flash calculator) |
| `firmwareVersion` | String | body, lens, flash, drone |
| `ratedShutterLife` | Int | body |
| `chargeCycles`, `ratedChargeCycles` | Int | camera and drone batteries |
| `capacityGB`, `cardType`, `speedRating` | Double, String, String | memory card |

### New `@Model` types

| Model | Fields | Milestone |
|---|---|---|
| `ShutterCountReading` | date, count, source (manual or photo), gear item | M1 |
| `GearLoan` | direction (lent out / rented in), person or company, contact, out date, due date, returned date, notes, gear item. An item's loan status is derived from its open loan | M1 |
| `DevelopmentRecipe` + `DevelopmentStep` | name, developer, dilution, temperature; steps with name, duration and agitation pattern | M2 |
| `SavedPlace` | name, latitude, longitude, notes | M3 |
| `Shoot` | title, start and end, place name and coordinates, client, type, notes, packed-item state; gear used (many-to-many), shot list, film rolls | M4 |
| `Kit` | name, notes, symbol, gear (many-to-many) | M4 |
| `ShotListItem` | title, notes, order, done, shoot | M4 |
| `ShotListTemplate` + `ShotListTemplateItem` | your saved templates: name, notes; items with title, notes, order. Built-in starters are value types, not stored | M4 |
| `FilmRoll` | stock ID, format, rated ISO, push/pull stops, frame count, frames shot, status, loaded and finished dates, lab, notes; camera, shoot | M4 |

That makes 15 models with the 4 kept ones (`GearItem`, `GearPhoto`, `MaintenanceRecord`,
`MaintenanceReminder`).

### Value-type catalogs (not persisted, Foundation-only)
- `SensorFormat`: built-in digital formats (full frame, APS-C, Canon APS-C, APS-H, Micro Four
  Thirds, 1-inch, 44×33 and 53.4×40 medium format, common drone sensors) and film formats (35mm,
  half-frame, 645, 6×6, 6×7, 6×9, 4×5, 8×10), stored as width × height in mm. Crop factor and
  diagonal are derived. Custom formats encode their size in a `custom:` ID, like Axe Manager's
  custom tunings, so they resolve on any device without a synced table.
- `LensMount`: common mounts, with free text allowed.
- `FilmStock`: built-in stocks with box ISO, process (C-41, E-6, B&W) and reciprocity model, taken
  from the manufacturers' datasheets. Custom stocks use a `custom:` ID like custom formats.
- `GearCategory`, and `MaintenanceType`: sensor cleaning, firmware update, CLA (film cameras),
  shutter replacement, AF calibration, repair, inspection, other.

---

## Photography math (`Models/PhotoMath/`)

Foundation-only, like Axe Manager's `Models/Learning/`, so it is unit-tested in isolation. Sources
go in `docs/PHOTO_MATH_REFERENCES.md` and code comments cite it rather than re-deriving.

| Tool | Method |
|---|---|
| Exposure | APEX: EV = log₂(N²/t); EV100 = EV − log₂(ISO/100); snap to 1/3-stop scales |
| ND filters | t′ = t · 2^stops; optical density 0.3 = 1 stop; filter factor = 2^stops; stacked filters add |
| Sunny 16 | f/16 at 1/ISO in full sun, with stop offsets per condition |
| Depth of field | Thin lens: H = f²/(N·c) + f; near and far limits from H and focus distance; c = format diagonal ÷ 1500 by default, adjustable |
| Field of view | 2 · atan(d / 2f) for width, height and diagonal; equivalent focal length = f × crop |
| Sun | NOAA solar position (Meeus). Golden hour: sun from +6° to −4°; blue hour: −4° to −6°; civil, nautical and astronomical twilight: −6°, −12°, −18° |
| Moon | Meeus ch. 47 (position), 48 (illuminated fraction), 49 (phases); rise and set by altitude search |
| Milky Way | Galactic-centre altitude over the night; window = astronomical darkness with the moon down and the core above ~10° |
| 500 / NPF | 500 ÷ (f × crop); NPF: t = (35N + 30p) ÷ f, with p = pixel pitch in µm |
| Star trails | Sidereal rate 15.04°/h; frame count for a stack |
| Time-lapse | frames = clip length × fps; interval = event length ÷ frames; storage = frames × file size |
| Flash | GN = distance × N at ISO 100; GN scales with √(ISO/100) |
| Print size | size = pixels ÷ DPI |
| Reciprocity | Per stock: the power law Tc = Tm^p where the maker publishes p (Ilford), otherwise the maker's table, interpolated (Kodak, Fujifilm) |

Accuracy targets, checked in tests: sunrise and sunset within 1–2 minutes of NOAA between ±60°
latitude; moonrise and moonset within about 5 minutes of USNO; polar day and night (no rise or
set) handled explicitly.

---

## Device features and permissions

- **Camera** (barcode scanning and the light meter). A new `CaptureSessionCoordinator` is the only
  owner of the camera, the same rule `AudioSessionManager` enforces in Axe Manager: the scanner and
  the meter never run a capture session themselves. The meter stops when its tab is hidden or the
  app goes to the background.
- **Light meter** reads `exposureDuration`, `ISO`, `lensAperture` and `exposureTargetOffset` from the
  active camera. iPhone ISO isn't calibrated the way camera ISO is, so the meter ships with a
  calibration offset and a "calibrate against your camera" step. It is reflected-light only; a
  grey card helps.
- **EXIF** is read from the original picked bytes **before** `PhotoIngest` re-encodes them
  (re-encoding drops metadata). Standard EXIF gives the body serial, lens make, model and serial,
  and focal length. ImageIO exposes a shutter-count key in Nikon's maker notes; other brands get
  checked against sample files, and fall back to manual entry. GPS data is never stored.
- **Location**: `CLLocationManager` while in use, asked the first time you tap "Use my location".
  The MapKit place picker and search send queries to Apple, and the privacy policy says so.
- **Notifications**: maintenance and sensor cleaning, loans due back, bulb and development timers
  (scheduled so they still fire if the app is in the background), and a golden-hour heads-up for
  planned shoots.

---

## Milestones

Each milestone ends with a push to `claude/camera-gear-manager-e1zzxt`, green CI and a short status
note. **No model ships without export, import and backup coverage in the same milestone**, which is
Axe Manager's 1.5.0 rule that export writes only what restore accepts.

### M1 — Foundation and inventory
**Status:** done 2026-10-11. See [docs/PROGRESS.md](docs/PROGRESS.md) for what shipped, the changes
from this plan, and what is still to check on a device.

- Swap the license. New Xcode project `ShutterManager` with folder-synced groups; app, unit-test and
  UI-test targets; entitlements; CI.
- Copy and rename the platform layer.
- Catalogs, the adapted `GearItem`, `ShutterCountReading`, `GearLoan`, adapted maintenance.
- Inventory UI, including EXIF fill, a shutter-count history chart, loans and marketplace links.
- Export, import, backup, CSV and PDF for all of the above. `CLAUDE.md` and `README.md`.
- Tests: model defaults, stable catalog IDs, EXIF fixtures, DTO round trips, import validation,
  CloudKit compatibility.

### M2 — Tools: calculators and film
**Status:** done 2026-10-11. See [docs/PROGRESS.md](docs/PROGRESS.md).

- `PhotoMath`, its references doc, and tests.
- Equivalent exposure, ND with bulb timer, Sunny 16, depth of field and hyperfocal, field of view,
  time-lapse, flash, print size, 500 and NPF, star trails, reciprocity, and the development timer
  with saved recipes.
- Values filled in from inventory.

### M3 — Light Meter and sky planning
**Status:** done 2026-10-11. See [docs/PROGRESS.md](docs/PROGRESS.md).

- `CaptureSessionCoordinator`, with the barcode scanner moved onto it; the Light Meter tab.
- Location, the map picker, `SavedPlace`.
- Sun and moon planner: elevation timeline (Swift Charts), sun and moon direction on a map, a date
  scrubber, upcoming moon phases. Dark-sky and Milky Way windows.

### M4 — Shoots
- `Shoot`, `Kit`, `ShotListItem`, `ShotListTemplate`, `FilmRoll`.
- Shoot log, kits and packing check, shot lists with built-in and saved templates, film roll log,
  golden-hour heads-up, usage per item. The light meter can take ISO from a loaded roll.

### M5 — 1.0 release prep
- Tip Jar products, About, privacy policy, app icon, screenshots and App Store text.
- Accessibility pass, UI tests for the main flows, release notes.
- CloudKit Production schema deployment and acceptance on your devices.

---

## What you'll need to do

These steps can't be done from a cloud session:
- Create the App ID `jcameronfurey.shuttermanager` and the CloudKit container, and turn on iCloud
  (CloudKit) and Background Modes → Remote notifications in Signing & Capabilities.
- Check that "Shutter Manager" is free in App Store Connect.
- Create the three tip products in App Store Connect.
- Device checks: the light meter against your camera or a handheld meter, EXIF from your own
  bodies, sync across your devices.

The cloud session has no Xcode. Code is written here and built and tested by CI on GitHub's macOS
runners. Anything that needs a real camera, GPS or an iCloud account is checked on your devices.

---

## Later candidates

There is no Pro mode, so everything here ships free when it ships. The list stays open: add ideas
as they come up.

- An inventory report for your insurer: a PDF with photos, serials and values, worded as "a
  report for your insurer", never "insurance".
- QR labels for bags and cases.
- Import usage from photos: count shots per body and lens from a batch of photos and update
  shutter counts.
- Lens and body compatibility, including adapters.
- More categories and category-specific fields as they're needed.
- Widgets or a Live Activity for the development and bulb timers.
- Cloud cover via WeatherKit. It is an Apple framework, but it sends your location to Apple and
  has a usage quota, so it changes the privacy story.
- Rental-house or studio mode (checking gear out to clients). A big build for a different user;
  scope it only if there's demand.
