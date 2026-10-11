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
- run the Foundation-only tests (`PhotoMath`, the film and format catalogs) with
  `Tools/linux/run_foundation_tests.sh [path/to/swift]`. They build and run on Linux, and CI runs
  them there too.

CI treats warnings as errors, so an unused variable fails the build.

## CI

One workflow, `.github/workflows/ci.yml`. `docs/CI.md` describes every job and the reasons for
its design. In short:

- Linux: change detection; conventions, actionlint and ShellCheck, which gate the macOS jobs; and
  the Foundation-only tests in the official Swift image.
- macOS: build for the generic simulator with warnings as errors, then unit tests with coverage;
  an unsigned Release device build; UI tests on iPhone and iPad (pull requests, `main`, and manual
  runs with `ui_tests: true`).
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

**Tabs** (`App/ContentView.swift`): **Inventory · Tools · Light Meter · Shoots · Settings**.

**Folders (`ShutterManager/`):**
- `App/`: entry point (library or `StoreRecoveryView`), root tabs, and `AppNavigation` (the
  selected tab and the Tools stack, for opening one tab from another).
- `Models/`: the `@Model` types.
  - `Catalog/`: Foundation-only catalogs (`GearCategory`, `SensorFormat`, `LensMount`,
    `FilmStock` with `FilmStockCatalog`).
  - `PhotoMath/`: Foundation-only photography math (exposure scales, equivalent exposure, ND,
    Sunny 16, the light meter, optics, astro, time-lapse, flash, print size, reciprocity,
    development timing) and astronomy (`Astronomy`, `SunMoon`, `SkyEvents`: sun and moon
    positions, rise and set, twilights, moon phases, Milky Way windows, and `ShootLight`, a
    shoot's golden hours). Sources are in
    `docs/PHOTO_MATH_REFERENCES.md`; comments cite it rather than re-deriving.
  - `Export/`: `LibraryExport` and its DTOs.
- `Services/`: persistence, export/import, backups, reminders, EXIF, Tip Jar, iCloud status,
  `ToolTimers` (the running bulb and development timers), the camera (`CaptureSessionCoordinator`,
  `BarcodeScannerService`, `LightMeterService`), `LocationService` and `ShootAlertScheduler`.
- `Views/`: `Inventory/`, `Tools/`, `LightMeter/`, `Shoots/` (the shoot log, kits, film rolls,
  shot-list templates), `Places/` (choosing a place), `Settings/`, `Shared/`.
- `Utilities/`: constants, schema, formatters, import validation, photo ingest, marketplace links.
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
- **Import strategies.** Import writes through an isolated context with one final save. Merge skips
  records whose ID already exists; replace removes what the file doesn't have.
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
- **Money** is `Decimal?` (`purchasePrice`, `currentValue`). There is no price history and there
  are no price alerts: the user enters a purchase price and an optional current value.
  `MarketplaceSearch` opens searches on used-gear sites.
- **Gear reminders** (sensor cleaning, loan due dates) go through `NotificationManager`. Its
  notification-center calls are injectable for tests. Reminders are reconciled on foreground,
  import, restore and CloudKit remote changes.
- **Timer alerts** (bulb exposures; development agitations, pour warnings and step ends) go through
  `NotificationManager.scheduleTimerAlerts(_:group:)`.
  - Their identifiers start with `timer_`, so a gear-reminder refresh never removes them.
  - They don't depend on the Gear Reminders setting.
  - `ToolTimers.shared` holds the running timers for the session. Timing comes from wall-clock
    dates, so it stays right in the background.
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
- **Logging and formatting.** Log with `os.Logger` (subsystem `Constants.App.loggerSubsystem`),
  never `print`. Format currency and dates through `CurrencyFormatter` and `DateFormatters`.
  Parse typed numbers with `Double(localizedInput:)` and `Decimal(localizedInput:)`.
- **Constants.** `Utilities/Constants.swift` holds magic numbers and UserDefaults keys in nested
  enums.
- **Shared views.** Reuse `Views/Shared/`: `StatCard`, `EmptyStateView`, `LoadingStateView`,
  `SettingsRow`, `MeasurementField`, `CountField`, `MoneyField`, and `ToastNotificationManager`.
- **Charts** use Swift Charts.
- **Leftovers.** Code copied from Axe Manager must lose its guitar names. The convention check
  flags `guitar`, `tuner`, `axemanager` and similar.
