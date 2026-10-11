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

**Cloud sessions have no Xcode.** Write the code there and let CI build it. Before pushing, run
the convention checks and, if a Swift toolchain is available, `swiftc -parse -swift-version 5` on
every changed file. Foundation-only files (catalogs, the Learn-style value types, `PhotoMath`
later) can also be type-checked and run on Linux. CI treats warnings as errors, so an unused
variable fails the build.

## CI

One workflow, `.github/workflows/ci.yml`. `docs/CI.md` describes every job and the reasons for
its design. In short:

- Linux: change detection; conventions, actionlint and ShellCheck. These gate the macOS jobs.
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
Tools, Light Meter and Shoots are placeholders until M2–M4.

**Folders (`ShutterManager/`):**
- `App/`: entry point (library or `StoreRecoveryView`) and root tabs.
- `Models/`: the `@Model` types.
  - `Catalog/`: Foundation-only catalogs (`GearCategory`, `SensorFormat`, `LensMount`).
  - `Export/`: `LibraryExport` and its DTOs.
- `Services/`: persistence, export/import, backups, reminders, EXIF, Tip Jar, iCloud status.
- `Views/`: `Inventory/`, `Settings/`, `Shared/`.
- `Utilities/`: constants, schema, formatters, import validation, photo ingest, marketplace links.
- `Extensions/`: small helpers on Swift types.

**Tests:**
- `ShutterManagerTests/` uses Swift Testing. `TestSupport` provides in-memory containers, isolated
  defaults and sample items.
- `ShutterManagerUITests/` uses XCUITest. Launch with `-uiTestInMemory` for a fresh library, and
  navigate tabs with `selectTab` (it handles the iPad floating tab bar).

### Data layer

Six `@Model` types, registered once in `Utilities/AppSchema.swift`:
- `GearItem`
- `GearPhoto`
- `MaintenanceRecord`
- `MaintenanceReminder`
- `ShutterCountReading`
- `GearLoan`

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

  An ID from a newer version reads as `.other` and is kept as is, through edits, export and
  import. Never rename or remove an ID. Custom sensor formats encode their size in a `custom:` ID,
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
