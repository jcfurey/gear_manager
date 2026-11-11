# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

Shutter Manager is a camera-gear manager with photography field tools for iPhone and iPad. It
started as a copy of the platform layer of Cam's Axe Manager (`jcfurey/guitar_manager`), which
stays a separate app. `ROADMAP.md` holds the product decisions and milestones; read it before
adding a feature.

## Build & Test Commands

```bash
# Build
xcodebuild -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Unit tests (Swift Testing)
xcodebuild test -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ShutterManagerTests

# One suite
xcodebuild test -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ShutterManagerTests/ExportImportTests

# UI tests (XCUITest)
xcodebuild test -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ShutterManagerUITests

# Convention checks (any machine with Python 3; CI's first job)
python3 Tools/ci/check_conventions.py
```

**Cloud sessions have no Xcode.** Write the code there and let CI build it. Before pushing:
- run the convention checks;
- if a Swift toolchain is available, run `swiftc -parse -swift-version 5` on every changed file;
- run the Foundation-only tests (`PhotoMath`, the film and format catalogs, the privacy policy)
  with `Tools/linux/run_foundation_tests.sh [path/to/swift]`. They build and run on Linux, and CI
  runs them there too.

CI treats warnings as errors, so an unused variable fails the build.

## CI

One workflow, `.github/workflows/ci.yml`. `docs/CI.md` describes every job and the reasons for
its design. In short:

- Linux: change detection; conventions, actionlint and ShellCheck, which gate the macOS jobs; and
  the Foundation-only tests in the official Swift image.
- macOS: build for the generic simulator with warnings as errors, then unit tests with coverage;
  an unsigned Release device build; UI tests on iPhone and iPad (pull requests, `main`, and manual
  runs with `ui_tests: true`); App Store screenshots on the 6.9" iPhone and 13" iPad (manual runs
  with `screenshots: true`, see `marketing/README.md`).
- **CI result** is the single status to require.

Keep these when changing CI:
- Xcode is pinned in `.xcode-version`.
- Actions are pinned by commit SHA, and Dependabot updates them.
- Simulators are chosen by UDID (`Tools/ci/select_simulator.py`).
- Don't boot a simulator in the background during a build. It made builds take 4-5 minutes
  instead of under one.

## Architecture

**Stack:** SwiftUI + SwiftData + feature services. iOS 18.6+, Swift 5 language mode, Xcode 26, no
external dependencies. The targets use folder-synced groups, so a new file in a folder is part of
the target without a project edit.

**Targets:** the app (`ShutterManager/`), its widget extension (`ShutterManagerWidgets/`, bundle
ID `jcameronfurey.shuttermanager.widgets`, embedded in the app), and the unit and UI tests.
`ShutterManagerShared/` is one folder in two targets: the app and the extension both compile
what's in it. The extension's `Info.plist` is `ShutterManagerWidgets-Info.plist` at the root,
beside the app's.

**Tabs** (`App/ContentView.swift`): **Inventory · Tools · Light Meter · Shoots · Settings**.

**Folders (`ShutterManager/`):**
- `App/`: entry point (library or `StoreRecoveryView`), root tabs, and `AppNavigation` (the
  selected tab and the Tools stack, for opening one tab from another).
- `Models/`: the `@Model` types.
  - `Catalog/`: Foundation-only catalogs (`GearCategory`, `SensorFormat`, `LensMount` with
    `MountCompatibility`, `FilmStock` with `FilmStockCatalog`).
  - `PhotoMath/`: Foundation-only photography math (exposure scales, equivalent exposure, ND,
    Sunny 16, the light meter, optics, astro, time-lapse, flash, print size, reciprocity,
    development timing) and astronomy (`Astronomy`, `SunMoon`, `SkyEvents`: sun and moon
    positions, rise and set, twilights, moon phases, Milky Way windows, and `ShootLight`, a
    shoot's golden hours). Sources are in
    `docs/PHOTO_MATH_REFERENCES.md`; comments cite it rather than re-deriving.
  - `Export/`: `LibraryExport` and its DTOs, `LibraryPackage` (the zip a library travels in),
    and the values the printed pages are laid out from (`InsurerReport`, `GearLabel` and
    `LabelSheet`).
  - `PhotoUsage.swift`: Foundation-only counting and matching for Usage from Photos.
  - `CloudForecast.swift`: Foundation-only: a place's cloud forecast by the hour, and what it
    says about a window of time.
- `Services/`: persistence, export/import, backups, reminders, EXIF, Tip Jar, iCloud status,
  `ToolTimers` (the running bulb and development timers), the camera (`CaptureSessionCoordinator`,
  `BarcodeScannerService`, `LightMeterService`), `LocationService`, `ShootAlertScheduler`, the
  printed pages (`PrintDocument`, `InsurerReportRenderer`, `LabelSheetRenderer`), Usage from
  Photos (`PhotoUsageReader`, `PhotoUsageRecorder`), `LibraryDeduplicator`, `TimerCue` (a
  timer's alert when notifications can't show it), and the cloud forecast (`CloudForecastStore`,
  `WeatherKitCloudProvider`).
- `Views/`: `Inventory/`, `Tools/`, `LightMeter/`, `Shoots/` (the shoot log, kits, film rolls,
  shot-list templates), `Places/` (choosing a place), `Settings/`, `Shared/`.
- `Utilities/`: constants, schema, formatters, import validation, photo ingest, marketplace links,
  and `ZipArchive` (a store-only zip reader and writer, Foundation-only).
- `Extensions/`: small helpers on Swift types.

**Tests:**
- `ShutterManagerTests/` uses Swift Testing. `TestSupport` provides in-memory containers, isolated
  defaults and sample items. In Debug, the app hosting the unit tests opens a temporary in-memory
  library, never the simulator's real one.
- `ShutterManagerUITests/` uses XCUITest. Launch with `-uiTestInMemory` for a fresh library, and
  navigate tabs with `selectTab` (it handles the iPad floating tab bar). They run on iPhone and
  iPad. On iPad the top tab bar leaves room for about two trailing toolbar buttons (search takes
  one), and extra ones fold into a "More" menu, so keep a screen's main action in
  `.primaryAction` and move secondary buttons to the leading side.
- `AccessibilityAuditTests` runs Xcode's accessibility audit (labels, touch targets, reachable
  text) on each tab's main screens. Its header says why the other audit types are left out.
- The UI-test helpers expect a slow simulator, because CI's is: `replaceText` waits for typed
  text to show (it can lag by seconds) and types again only if characters are still missing,
  `selectTab` checks that the tab came up and taps again if it didn't,
  `goBack(to:)` taps Back again when the first tap landed mid-push, `tap(_:toShow:)` taps again
  when a tap that should open a screen or a sheet didn't, and the audit waits for a passing
  banner to go. Use them rather than a bare `typeText`, or a bare `tap` on a tab, a Back button
  or anything tapped just after a sheet closes or a screen pops.
- Under `-uiTestInMemory` the app turns UIKit animations off (Debug), so a tap can't land
  part-way through a push, a pop or a sheet.
- Settings a UI test leaves behind stay on the simulator for the tests after it: the planners'
  place is one, so a later test finds the sun and moon planner already showing a day.

### Data layer

Fifteen `@Model` types, registered once in `Utilities/AppSchema.swift`:
- `GearItem`
- `GearPhoto`
- `MaintenanceRecord`
- `MaintenanceReminder`
- `ShutterCountReading`
- `GearLoan`
- `DevelopmentRecipe`
- `DevelopmentStep`
- `SavedPlace`
- `Shoot` and `ShotListItem`
- `Kit`
- `ShotListTemplate` and `ShotListTemplateItem`
- `FilmRoll`

The app container, previews (`PreviewModelContainer`) and tests all build from `AppSchema`, so a
new model only needs listing there.

SwiftData mirrors to the private CloudKit database `iCloud.jcameronfurey.shuttermanager`.
`AppStoreController` falls back to local-only storage if CloudKit can't start. Every `@Model`
must stay CloudKit-compatible:
- no `@Attribute(.unique)`;
- a default on every non-optional attribute;
- optional relationships with inverses;
- no `.deny` delete rule.

In-memory containers set `cloudKitDatabase: .none`. The convention checks enforce all of this.

Don't add the `com.apple.developer.default-data-protection` entitlement; the iOS default is what
background sync needs. The debug-only launch argument `-initializeCloudKitSchema` initializes the
Development schema. Deploying to Production is done by hand in CloudKit Console.

## Key Conventions

- **Stable string IDs, never stored enums.** These properties store a string ID and expose an enum
  through a computed property:
  - `GearItem.category` (`gearCategory`)
  - `MaintenanceRecord.typeID` and `MaintenanceReminder.typeID` (`type`)
  - `ShutterCountReading.sourceID` (`source`)
  - `GearLoan.directionID` (`direction`)
  - `GearItem.sensorFormatID` (`sensorFormat`)
  - `Shoot.typeID` (`type`) and `FilmRoll.statusID` (`status`)

  An ID from a newer version reads as `.other` (a roll's status as `.shot`, so it's never the
  loaded roll) and is kept as is, through edits, export and import. Never rename or remove an ID. Custom sensor formats encode their size in a `custom:` ID,
  so they resolve on any device.
- **One list of editable fields.** `GearItemDTO.applyFields(to:)` is the single place that writes
  a gear item's fields. Import, the edit draft and its rollback all use it. Adding a field means:
  1. add it to `GearItem`;
  2. add it to `GearItemDTO`: its stored property, `init(from:)` and `applyFields`;
  3. if it's a `Double`, add it to `replaceUnrestorableNumbers` and `ImportDocument.validate`;
  4. extend the round-trip test.
- **Edits use detached drafts.** Add Gear and the detail editor bind to `GearItem.detachedCopy`
  and write to the library only on Save or Done. Check `saveOrLog()`'s result before dismissing,
  and use `persistenceErrorAlert` when a save fails.
- **Export writes only what import accepts.** `ImportDocument` decodes and validates off the main
  actor. It rejects only what can hurt the app: non-finite values, magnitudes past
  `Constants.DataLimits`, and record counts over the limit. `LibraryExport.formatVersion` rises
  only for a change older versions can't read; a newer file is refused with a clear message.
- **A library travels as a package** (`LibraryPackage`): a zip with `library.json` (a
  `LibraryExport` with no photos in it), `photos.json` (which item or record each photo belongs
  to) and each photo as an entry. Exports' Library format and every backup write one.
  - Photos go in and come out `Constants.DataLimits.packagePhotoBatch` at a time. Read their
    bytes through a scratch `ModelContext` that's let go, never from the library's own objects:
    those stay in memory as long as the screens showing them. Keep the scratch context alive
    while its objects are read (`withExtendedLifetime`).
  - The zip is store-only and in the format's plain form (`ZipArchive`), so any tool opens it.
    A test pins the bytes the writer produces; if the writer changes, check its output again
    with a standard zip tool. Never change an entry name or the index's keys: files already
    written must keep importing.
  - Import tells a package from a JSON file by how it starts (`ImportDocument.open`), not by
    its name. JSON files with photos inside, as earlier versions wrote, still import.
- **Too large to write.** A package past `DataExportService`'s limit (3 GB) is refused with
  `ExportError.photosTooLarge`, which says to leave the photos out. A backup that large is
  written without its photos, and the Backups screen says so. A JSON export past its own limit
  (256 MB) throws `ExportError.tooLarge`.
- **Import strategies.** The records are written through an isolated context with one final save.
  Merge skips records whose ID already exists; replace removes what the file doesn't have.
  - A package's photos follow that save in small lots, each saved by itself: all of them in one
    save would need all of them in memory. So a failure there leaves the records in and some
    photos out (`ImportError.photosIncomplete`), and importing the file again adds the rest.
  - That's why photos merge one by one: a gear photo already in the library (by ID) is left
    alone, and an item the library has gains the file's photos it's missing.
  - `didImportNotification` is posted when the records are in, before the photos start, and
    again when they finish: a replace has removed what other screens were showing.
- **After the library is replaced** (a replace-import, Delete All Data), call
  `AppNavigation.libraryWasReplaced()`: the tabs are rebuilt, so no screen is left holding a
  deleted record.
- **Doubled records.** A file imported before iCloud has finished downloading the same library
  leaves every record in twice, as two rows with one `id`: CloudKit allows no unique constraint.
  - `LibraryDeduplicator` finds them and folds each set into one (Settings → Find Duplicates). It
    keeps the copy changed last, then the one with more hanging off it, and moves over the parts
    and links only another copy had.
  - It runs only when the user asks. Never make it automatic: nothing in a row says which copy
    it is, so two devices choosing for themselves could each keep the copy the other deletes.
  - A new model is added to its `models`, `find` and `merge`; a test compares `models` with
    `AppSchema.models`.
- **One place for "everything".**
  - Export and backups read the library through `LibraryContents.fetch(from:)`. A new top-level
    model is added there, and to `LibraryExport` as an optional array so older files still decode.
  - Replace-import and "Delete All Data" use `ModelContext.deleteEveryRecord()`, which covers every
    model in `AppSchema`.
  - Recipe steps, shot lists and template items travel nested inside their parent's DTO. Shoots,
    kits and rolls name their gear (and a roll its shoot) by ID; import drops an ID that matches
    nothing.
- **Value drafts.** `DevelopmentRecipeDraft`, `ShootDraft`, `KitDraft`, `FilmRollDraft` and
  `ShotListTemplateDraft` hold an editor's changes and write them on Save; the lists inside
  recipes and templates are matched by ID. Ticks (packing, shots) and additions on a shoot's screen
  save as they happen.
- **Settings in exports.** Every key in `Constants.UserDefaultsKeys.exportableSettings` needs a
  typed rule in `ImportedSettings`; a test checks this.
- **Photos.** Read EXIF (`PhotoMetadataReader`) from the original bytes *before* `PhotoIngest`
  downsamples them. Stored photos have their location removed. Only Nikon maker notes expose a
  shutter count through ImageIO.
- **Printed pages** (the report for your insurer, QR labels).
  - Lay a page out first as `PrintElement`s with frames, then draw it with `PrintDocument`. The
    tests check the layout's frames and read the PDF back with PDFKit.
  - Paper comes from `PrintPaper.size()`: Letter where it's the custom, A4 elsewhere.
  - Say "a report for your insurer". The word "insurance" is banned from the app's strings and the
    App Store text (the `wording` convention check).
- **QR labels.** A label's code is a `LabelLink`: `shuttermanager://kit/<id>` or
  `shuttermanager://gear/<id>`, an ID and nothing else. The scheme is in `Info.plist`;
  `AppNavigation.open(_:)` handles it and `ContentView` shows what it names. Never change the
  link's form: printed labels can't be updated.
- **Usage from Photos** (`PhotoUsageView`, from Collection and from a shoot).
  - `PhotoUsageReader` reads only metadata, from the file where the system put it
    (`PhotoMetadataReader.read(contentsOf:)`); a raw file and a JPEG of the same name are one shot.
  - `PhotoUsageMatcher` matches by serial number, then by name. A match the user chooses is
    remembered per device (`PhotoUsageMatchStore`), not synced.
  - No tally is stored. `PhotoUsageRecorder` writes shutter-count readings, gear the user asks to
    add, and a shoot or its gear, in one save: an item's use still comes from the shoot log.
  - A lens's group also counts the focal lengths and apertures its shots were taken at, shown as
    a line of words and, for a zoom, a chart. Those are shown, not saved.
  - The pickers can't be driven from a UI test: `-uiTestPhotoUsageSample` (Debug) adds a button
    that reads a fixed batch.
- **Money** is `Decimal?` (`purchasePrice`, `currentValue`). There is no price history and there
  are no price alerts: the user enters a purchase price and an optional current value.
  `MarketplaceSearch` opens searches on used-gear sites.
- **Gear reminders** (sensor cleaning, loan due dates, maintenance reminders) go through
  `NotificationManager`. Its notification-center calls are injectable for tests. Reminders are
  reconciled on foreground, import, restore and CloudKit remote changes.
- **Timer alerts** (bulb exposures; development agitations, pour warnings and step ends) go through
  `NotificationManager.scheduleTimerAlerts(_:group:)`.
  - Their identifiers start with `timer_`, so a gear-reminder refresh never removes them.
  - They don't depend on the Gear Reminders setting.
  - `ToolTimers.shared` holds the running timers for the session. Timing comes from wall-clock
    dates, so it stays right in the background.
  - When notifications can't be shown, `ToolTimers.giveDueCues` gives each alert through
    `TimerCue` while the app is open: a banner, a haptic and a tone made in code
    (`TimerToneData`). With notifications on it does nothing, so no alert comes twice.
- **Live Activities** (a running timer on the Lock Screen and in the Dynamic Island).
  - `ShutterManagerShared/TimerActivityAttributes.swift` is what an activity shows, with the
    words and numbers worked out there so the app's tests can check them. The extension
    (`TimerLiveActivity`) only draws.
  - `ToolTimers` asks `TimerActivityPresenting` to show or end; `TimerActivityController` is the
    ActivityKit one, and only `ToolTimers.shared` has it. Tests pass a recorder, or nothing.
  - Nothing is pushed to an activity: there's no server. A running countdown is drawn by the
    system (`Text(timerInterval:)`), and its stale date, set to when it runs out, is what makes
    the activity say "Time's up" with the app asleep. Anything that must change at a moment the
    app may not be running has to work that way.
  - What the extension needs from the app goes in the activity's content state. It can't read
    the library: sharing that would take an App Group, which the app doesn't have.
  - The extension's version and build number must match the app's, and its bundle ID must start
    with the app's. The convention checks hold both.
- **Photography math.**
  - `Models/PhotoMath/` stays Foundation-only, with lengths in millimetres, times in seconds and
    temperatures in °C.
  - Exposure math uses the exact scale values (`ExposureScale`: f/5.6 is 2^2.5) and shows the
    camera labels.
  - Views convert to the user's units with `MeasurementUnits` (Settings → Units).
  - When adding a Foundation-only file or test, list it in `Tools/linux/run_foundation_tests.sh`.
- **Film data comes only from makers' datasheets.**
  - Each `FilmStock` cites its `source`, and `docs/PHOTO_MATH_REFERENCES.md` records how each table
    was read.
  - A stock whose maker publishes no figures is `.unpublished` or `.noCorrectionUpTo`; never fill
    it from third-party tables.
  - Film stock IDs are stored and synced like the other catalog IDs: never rename or remove one.
- **Lens mounts and compatibility.**
  - `GearItem.mount` is text: a `LensMount` suggestion or any typed name. An adapter's mount
    names both sides, lens first: "Canon EF → Canon RF" (`LensMount.adapterName`; a typed "->"
    reads the same). It's a stored form: never change it.
  - `MountCompatibility.fit` answers from, in order: the same mount, a maker's own adapter, then
    the room between the two flange distances. An adapter in the inventory counts for its pair
    whatever the arithmetic says.
  - The data comes only from the sources in `docs/PHOTO_MATH_REFERENCES.md` ("Lens mounts"): a
    flange distance from the table, a maker's adapter from the maker's own page. Never say an
    adapter exists unless its maker does; other brands' adapters are shown as room, "if one is
    made for this pair".
  - `CompatibilityView` (from a body's or a lens's screen) lists the inventory by fit, and
    `GearItem.packingIssues(for:)` flags a lens that goes on no body packed with it.
- **One camera owner.** `CaptureSessionCoordinator.shared` owns the capture session and its one
  preview layer, like `AudioSessionManager` in Axe Manager.
  - The barcode scanner and the light meter each start it for themselves. `stop(for:)` does
    nothing once the other client has taken it.
  - Don't create an `AVCaptureSession` anywhere else.
  - `CameraPreviewUIView` shows the shared layer. Representables re-attach it in `updateUIView`,
    because the other screen may have taken it.
  - The light meter runs only while its tab is on screen and the app isn't in the background.
- **Places and location.**
  - `PlaceValue` is a place as the planners use it, saved or not. The planners keep the chosen
    one per device as JSON; `SavedPlace` is the synced list.
  - `LocationService` asks for one location, while in use, only when "Use My Location" is tapped.
  - Sky times show in the place's own time zone, not the device's.
- **Cloud forecast** (Apple Weather, in the sky planners and on a shoot still to come).
  - It's off until the user turns it on (`CloudForecastStore.setEnabled`), because asking sends
    the place to Apple. Nothing asks for weather while it's off. The switch is per device and
    never exported: a file from another device can't agree for this one.
  - `CloudForecastStore.shared` is the one owner, and `WeatherKitCloudProvider` the one file that
    imports WeatherKit. The convention checks hold that, and the entitlement it needs.
  - A place is asked for at `GeoCoordinate.forecastPoint` (two decimal places, about a
    kilometre), and again only once its forecast is `Constants.CloudForecast.lifetime` old: each
    request counts against the developer account's monthly allowance.
  - Forecasts live in memory for the session. Don't store or sync one: Apple's terms allow only
    temporary caching.
  - Apple's terms also ask for its credit wherever its data shows: the Apple Weather mark and
    the legal link (`WeatherAttributionRow`). A screen shows a forecast through
    `CloudForecastRows`, which adds the credit, and asks for it with
    `task(id: CloudForecastStore.shared.request(for:))`.
  - `Models/CloudForecast.swift` stays Foundation-only. A window's clouds weigh each hour by its
    share of the window; one that runs past the forecast's ten days gets no summary.
  - CI's simulator isn't signed for WeatherKit, so the real provider always fails there.
    `-uiTestCloudSample` (Debug) puts a fixed forecast in its place, and under `-uiTestInMemory`
    the switch starts off and isn't saved.
- **Sky math.**
  - Every event is an altitude crossing found by `SkySearch` (sample, then bisect to a second), so
    polar day and night come out as no crossing.
  - The tests compare with Meeus's worked examples and USNO's tables.
  - The planners compute off the main actor (`Task.detached`).
- **The shoot log.**
  - A shoot copies its place (name, coordinates, time zone) rather than linking a `SavedPlace`,
    and shows its times in that time zone.
  - Shoots and kits link to gear many-to-many; only `Shoot.gear` and `Kit.gear` declare the
    inverse. Deleting across the log unlinks; a shoot's shot list and a template's items go with
    it.
  - Shot lists are copies: applying a template never links to it, so editing one later leaves
    shoots alone. Built-in starters (`ShotListStarter`) are values, not stored.
  - Packing ticks are item IDs in `Shoot.packedGearIDs`. `GearItem.packingIssues(for:)` flags
    gear that's lent out, needing service or a cleaning, or a rental due back before the shoot
    ends.
  - Usage per item comes from the log: shoots that have started count, planned ones don't.
- **Golden-hour heads-ups** go through `ShootAlertScheduler`, which works out each shoot's windows
  with `ShootLight` off the main actor and hands them to `NotificationManager.replaceShootAlerts`.
  - Their identifiers start with `shoot_`, so gear-reminder refreshes leave them alone.
  - Each shoot turns its own on; they don't depend on the Gear Reminders setting.
  - They're reconciled wherever gear reminders are, and after a shoot is saved or deleted. Only
    saving a shoot that asks for one can show the permission prompt.
- **Tool inputs** persist per device with `@AppStorage` under
  `Constants.UserDefaultsKeys.toolValuesPrefix`. They aren't exported; the units, depth-of-field and
  light-meter calibration settings are.
- **No Pro mode, ever.** Money is a Tip Jar only (`TipJarStore`,
  `jcameronfurey.shuttermanager.tip.*`). Every feature is free.
  - `ShutterManager.storekit` (the repository root) is the scheme's StoreKit configuration for
    trying tips in Xcode; a unit test checks it offers exactly `TipProduct.allCases`.
  - Don't import StoreKitTest: its headers use a type iOS 18 deprecates, which fails the build with
    warnings as errors.
- **The privacy policy** has one source, `Utilities/PrivacyPolicy.swift`, which the app shows.
  `docs/PRIVACY.md`, the public page, is written from it by `Tools/linux/write_privacy_policy.sh`,
  and a test fails when they differ. Update it, and its date, whenever data leaves the device in a
  new way.
- **Accessibility.**
  - Build `ResponsiveConstants` with the view's `@Environment(\.dynamicTypeSize)`; the argument
    is required so layouts follow the user's text size.
  - Hide decorative icons, combine a row that reads as one thing, add `.isSelected` to the chosen
    option in a list, and say state in words (overdue, up or down, invalid), never by color or a
    symbol alone.
  - Colored text uses `AppColors`: `goodText`, `warningText`, `badText` and `infoText` for status,
    `category(_:)` for gear categories, and the accent. Each reads at 4.8:1 or better in both
    modes; plain system red, orange, green and yellow are for icons and fills only.
  - Buttons and other controls get a 44-point target, even when they show only a glyph.
  - Don't use a `Label` as a `LabeledContent` value: on iOS 26 it leaves a tall gap under the row.
    Use an `HStack` of a hidden `Image` and a `Text`.
  - In a button's label, `.foregroundStyle(.primary)` resolves to the button's tint. Use
    `Color.primary` and `Color.secondary` for text that shouldn't be tinted.
  - Charts of a place's day mark hours on that place's clock (`placeHourAxis` in the sky views);
    Swift Charts' own labels use the device's time zone.
- **Release material.**
  - App Store screenshots come from the `screenshots` CI job: `ReleaseScreenshotData` and
    `ReleaseScreenshotTests` compile only with `RELEASE_SCREENSHOTS`, which only that job sets.
  - The App Store text is in `marketing/<version>/`, one `.txt` file per field; the convention
    checks enforce App Store Connect's limits.
  - `Tools/generate_app_icon.py` writes the default, dark and tinted icons.
- **Logging and formatting.** Log with `os.Logger` (subsystem `Constants.App.loggerSubsystem`),
  never `print`. Format currency and dates through `CurrencyFormatter` and `DateFormatters`.
  Parse typed numbers with `Double(localizedInput:)` and `Decimal(localizedInput:)`.
- **Constants.** `Utilities/Constants.swift` holds magic numbers and UserDefaults keys in nested
  enums.
- **Swift pitfalls CI has caught here.**
  - Don't name an enum case `none`: next to an optional it reads as `Optional.none`, with a
    warning. Use a word for what it means (`unmatched`, `leftOut`).
  - Don't name a local after the method that makes it (`let pages = pages(for:)`).
  - A default argument can't read a main-actor static: take an optional and fill it in inside.
  - Turn a `Double` into an `Int` with `Int(saturating:)`: a calculator's result can be infinite.
- **Shared views.** Reuse `Views/Shared/`: `StatCard`, `EmptyStateView`, `LoadingStateView`,
  `SettingsRow`, `MeasurementField`, `CountField`, `MoneyField`, and `ToastNotificationManager`.
- **Charts** use Swift Charts.
- **Leftovers.** Code copied from Axe Manager must lose its guitar names. The convention check
  flags `guitar`, `tuner`, `axemanager` and similar.
