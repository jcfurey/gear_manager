# Progress

Where each milestone in [ROADMAP.md](../ROADMAP.md) stands, what changed from the plan, and what
is still to check on a device. Add a section when a milestone finishes.

| Milestone | Status |
|---|---|
| M1 — Foundation and inventory | Done (2026-10-11) |
| M2 — Tools: calculators and film | Done (2026-10-11) |
| M3 — Light Meter and sky planning | Done (2026-10-11) |
| M4 — Shoots | Done (2026-10-11) |
| M5 — 1.0 release prep | Done in code (2026-10-12); the release checklist in the roadmap is the owner's |
| After 1.0 — later candidates, round 1 | Done (2026-11-10); not merged to `main` yet |
| After 1.0 — round 2: what the review left | Done (2026-11-10); not merged to `main` yet |

---

## After 1.0 — round 2: what the review left

**Done 2026-11-10** on `claude/camera-gear-manager-e1zzxt` (commits `d522bd9`, `e9ecf5c`,
`adacdc3`, `0a982ca`, and the commit that adds this section). The roadmap's remaining candidates
each wait on a decision (a second app target, a change to the privacy story, demand), so this
round took what round 1's review had left, and the one extension round 1 had noted.

### What shipped
- **Find Duplicates** (`d522bd9`), in Settings. Importing a file before iCloud has finished
  downloading the same library leaves every record in twice.
  - It counts the records that share an ID, by kind, and folds each set into one when asked.
  - The copy changed last is kept; where a record keeps no change date, the copy with more
    hanging off it. Photos, history, list entries, and places on shoots, in kits and on rolls
    that only another copy had move to the kept one.
  - A backup is made first, the other tabs are rebuilt afterwards, and a failed merge is rolled
    back.
  - The import screen warns when iCloud is syncing, or hasn't finished a download since the app
    opened.
- **Timers alert in the app when notifications are off** (`e9ecf5c`). A bulb timer used to end
  silently, and a development step's agitations showed only on its own screen.
  - While the app is open, each alert comes as a banner, a haptic and a two-note tone, on
    whichever screen is up.
  - Of several due together, the one that ends an exposure or a step wins over an agitation. An
    alert more than two seconds old is skipped, so coming back from the background replays
    nothing.
  - The tone is made in code and played as a system alert sound: it mixes with other audio and
    is a vibration when the phone is on silent.
- **Usage from photos says how each lens was used** (`0a982ca`): a zoom's range and its most
  used focal lengths, with a chart of shots at each focal length marked on a zoom ring, and the
  apertures used most.
- **The banner's close button** has a full 44-point target. The accessibility audit caught the
  bare glyph (see below).
- **Tests:** 127 Foundation-only tests (8 new), 320 unit tests in all (26 new), and 26 UI
  tests on each device (1 new).

### Verified
- `0a982ca`: [run 42757396845](https://github.com/jcfurey/gear_manager/actions/runs/42757396845)
  passed the convention checks, 127 Foundation-only tests on Linux, the Debug and Release builds
  with warnings as errors, and 318 unit tests.
- The commit that adds this section, with one more unit test and the CI change below: the run,
  with UI tests on iPhone and iPad, is recorded here once it finishes.

### Changes from the plan
- **Find Duplicates is a tool, not an automatic pass.** Round 1 left this as "a pass that finds
  records doubled by importing". Two copies of a record are the same in every field, the ID
  included, so no two devices can be sure of keeping the same one. Run automatically, one
  device could keep the copy another deletes, and iCloud would remove both. So the user starts
  it, and the screen says to do it on one device.
- **The in-app alert only speaks when a notification can't.** With notifications on, the
  notification is already shown in the app, with its sound; a second alert would double it.

### Found by CI and fixed
- The test build failed on `e9ecf5c`: a helper's default argument read a main-actor static,
  which Swift 5 mode reports as an error under warnings-as-errors. The pitfall was already in
  `CLAUDE.md`; the static is now nonisolated (`adacdc3`).
- The unit-test step on `0a982ca` took 17 minutes for 38 seconds of tests: the runner's
  simulator sat for 16 minutes before the first test. The job now boots the simulator and
  launches the app once in a step of its own, as the UI-test job has since round 1.
- The first UI test of the run, `AccessibilityAuditTests.testInventoryScreens`, failed on both
  devices in [run 42759636285](https://github.com/jcfurey/gear_manager/actions/runs/42759636285),
  for two reasons. The other 25 passed on each.
  - On iPad the audit flagged the close button on the "Gear saved" banner, whose touch target
    was the 12-point glyph. The banner then left while the test was reading the finding, and the
    lookup failed. The button now has a 44-point target, and the audit waits for a banner to go.
  - On iPhone the simulator was at its slowest in its first minute (18 seconds to go idle, 11 to
    find a button), and the Add Gear sheet took more than the 10 seconds the test allowed. That
    class's waits are now 30 seconds.

### Left for later
- A package format so a large library exports and backs up with its photos. It changes the
  backup and restore path, so it's best chosen deliberately rather than slipped in.
- A record deleted on another device while its detail screen is open here. It needs two devices
  on one iCloud account to see what happens, and to check any fix.

### Still to check on a device
- **The timer tone:** that it's audible over music, vibrates on silent, and comes at each
  agitation and at the end with notifications off. A simulator plays no alert sounds.
- **Find Duplicates on a doubled library:** import an export on a second device before iCloud
  has synced, run it on one device, and watch the other follow.
- **Focal lengths and apertures** from real files, a zoom's especially.

---

## After 1.0 — later candidates, round 1

**Done 2026-11-10** on `claude/camera-gear-manager-e1zzxt`, restarted from `main` after pull
request #1 merged (commits `7c418c5`, `a4d7101`, `b8e19a0`, `1f8c38d`, and the commit that adds
this section). The first four of the roadmap's later candidates, and a review of the 1.0 code.

### What shipped
- **A report for your insurer** (`7c418c5`): a PDF of all gear or a chosen part, grouped by
  category with totals, with serial numbers, prices, values and one or all photos per item. From
  Settings and from the Collection screen. The word "insurance" is kept out of the app and the App
  Store text by a convention check.
- **QR labels** (`a4d7101`): labels for kits and gear, 8 or 18 to a page, on Letter or A4, with
  an optional "if found" line.
  - A label's code is `shuttermanager://kit/<id>` or `shuttermanager://gear/<id>`: an ID and
    nothing else. The Camera app opens it in the app, which shows the kit's checklist or the item,
    and says so when the label is from another library.
  - The app registers the `shuttermanager` URL scheme. Nothing else uses it.
- **Usage from photos** (`1f8c38d`): choose photos, files or a folder and see the shots each body
  and lens took.
  - Matching is by serial number, then by name. It knows Nikon's "Z 6_2" is the Z6 II, and that a
    lens named "NIKKOR Z 50mm f/1.8 S" is the item "Z 50mm f/1.8 S". A match you choose is
    remembered on that device.
  - A shutter count in the files is recorded as a reading dated by the photo. Choosing the same
    photos twice records it once.
  - Gear the inventory lacks can be added. The batch can be logged as a shoot, or its gear added
    to the shoot it was opened from.
  - Only metadata is read, from the file where the system put it, so a 60 MB raw file costs
    little. A raw file and a JPEG of the same name count as one shot. Up to 10,000 photos a batch.
- **Lens and body compatibility** (the commit that adds this section): a body's screen lists the
  inventory's lenses as fitting, fitting with an adapter you have, fitting with an adapter, or
  not fitting; a lens's screen lists the bodies.
  - The answer comes from the same mount, then a maker's own adapter, then the room between the
    two mounts' flange distances. 33 mounts and 22 makers' adapters, each with its source in
    `docs/PHOTO_MATH_REFERENCES.md`.
  - An adapter you own is a lens whose mount names both sides ("Canon EF → Sony E"), chosen from
    the mount field's menu. It counts for its pair.
  - A lens made for a smaller format than the body's says to expect a crop or dark corners.
  - A shoot's packing check flags a lens that goes on none of the bodies packed with it, and
    names the maker's adapter when that's what's missing.
- **Fixes from a review of the 1.0 code** (`b8e19a0`). Two reviewers read the services and the
  views; each finding was checked against the code before it was fixed.
  - Maintenance reminders were never scheduled as notifications. They are now, and they count
    toward an item needing attention.
  - With more timer alerts than iOS keeps, the ones that end a step are kept and agitation
    reminders go first. Development alerts are topped up when the app comes back.
  - A shoot keeps its clock time when its place moves it to another time zone.
  - An export too large to write says so and names the fix; a backup that large is written
    without photos and the Backups screen says so. Both used to fail without a reason.
  - A calculator result that isn't a finite number no longer crashes a conversion to a whole
    number (`Int(saturating:)`); an ND stack stops at 40 stops.
  - After a replace-import or Delete All Data, the tabs are rebuilt, so no screen is left showing
    a deleted record.
  - Failed saves are reported in six places that used to ignore them: deleting gear (from the
    list and from its screen), a roll or a loan, changes on a shoot's screen, and dismissing a
    reminder.
  - Smaller ones: a photo's location is removed on the fallback path too; coordinates typed with
    a decimal comma are read; a record repeated inside one import file is added once; a distance
    in feet shows three decimals, not sixteen; Add Gear dates a photo's shutter count by the
    photo; a note appears beside timers and heads-ups when notifications are off.
- **The privacy policy** now covers usage from photos, the report and the labels, dated
  November 10, 2026. No data leaves the device in a new way.
- **Tests' typing:** `replaceText` checks what arrived and types again when the simulator
  dropped keystrokes.
- **Tests:** 119 Foundation-only tests (49 new), 294 unit tests in all (115 new), and 25 UI
  tests on each device (8 new).

### Verified
Each commit ran CI, the later ones with UI tests on iPhone 17 and iPad (iOS 26.5):
- `7c418c5` and `a4d7101`:
  [run 42732745496](https://github.com/jcfurey/gear_manager/actions/runs/42732745496) and
  [run 42733904367](https://github.com/jcfurey/gear_manager/actions/runs/42733904367) passed the
  convention checks, the Linux tests, the Debug build with unit tests and the Release build.
- `b8e19a0`: [run 42735785866](https://github.com/jcfurey/gear_manager/actions/runs/42735785866)
  passed everything but one iPhone UI test, the dropped keystrokes described below. The iPad run
  passed all 21 UI tests, the new ones for labels and the report among them.
- `1f8c38d`: [run 42738975436](https://github.com/jcfurey/gear_manager/actions/runs/42738975436)
  passed 99 Foundation-only tests on Linux, 273 unit tests, the Release build and all 23 UI tests
  on iPhone. On iPad 21 passed, both new usage tests among them, and the first two of the run
  never launched the app: see below.
- The lens compatibility commit and the CI change after it (`c0b8607`):
  [run 42743213703](https://github.com/jcfurey/gear_manager/actions/runs/42743213703) passed
  every job:
  - 119 Foundation-only tests in the Swift 6.2 Linux image;
  - the Debug and Release builds with warnings as errors;
  - 294 unit tests;
  - 25 UI tests on each of iPhone 17 and iPad Pro 11-inch (iOS 26.5), the accessibility audit
    included.

### Changes from the plan
- **Usage from photos stores no tally.** The roadmap said "count shots per body and lens … and
  update shutter counts". The counts are shown, and what's kept goes where the app already keeps
  it: shutter-count readings, and the shoot log, which is where an item's use is counted from. A
  stored per-item tally would need a schema change and would double on a second pass over the
  same photos.
- **Shutter counts come only from files that carry them**, which through ImageIO means Nikon.
  The number of photos isn't turned into an estimate: kept photos undercount the shutter, and an
  electronic shutter doesn't move it.
- **Labels carry an ID, not a name.** A label for a kit doesn't change when the kit's contents do,
  and a found bag gives nothing away.
- **An adapter's two mounts live in the mount text**, not in new fields. The roadmap asked for
  "compatibility, including adapters"; a second mount field would have been a schema change. An
  older version of the app shows the text as it is.
- **Only makers' own adapters are named.** Other brands make many more, with no one source for
  which exist, so those pairs show the room between the mounts and say "if one is made for this
  pair". Sigma's Canon EF converters are left out because Sigma offers them for its own lenses.
- **No schema change in the round.** All fifteen models are as they were, so there is nothing new
  to deploy in CloudKit Console.
- **Not in the plan:** the code review and its fixes, the URL scheme, remembered matches, and
  the packing check for lenses.

### Found by CI and fixed
- The iPhone UI run on `b8e19a0` failed one test: `AccessibilityAuditTests.testShootScreens`
  looked for a shoot titled "Harbour", and the result bundle showed the shoot open with the title
  "Ha". The simulator had dropped keystrokes. The app was right; `replaceText` now retypes text
  that arrived short.
- The iPad UI run on `1f8c38d` failed its first two tests with "Timed out while launching
  application", one of them holding the job for ten minutes; the other 21 passed. A newly booted
  simulator's first launch of a newly installed app outlasted XCUITest's launch limit. The job
  now installs the app and launches it once before the tests. In the next run that first
  install and launch took 4 minutes on iPhone and 2.5 on iPad, and then all 25 tests passed on
  both.

### Left for later
These came out of the review and weren't fixed here. Round 2, above, took the first and third.
- A pass that finds records doubled by importing a file before iCloud finished syncing. Today the
  import screen warns about it.
- A package format so a large library exports and backs up with its photos.
- A sound or banner inside the app when a timer ends and notifications are off. Today there is
  only the note.
- A record deleted on another device while its detail screen is open here.

### Still to check on a device
- **Usage from photos** with real files: a card's folder of raw files from the Files app, photos
  chosen from the Photos library (raw and HEIC), and photos still in iCloud, which should count
  as unreadable until downloaded.
- **A Nikon body's shutter count** through the batch reader, against the camera's own count.
- **QR labels:** print a sheet on Letter and A4 and scan the labels with the Camera app.
- **The report for your insurer** printed, and opened in Files and Mail.
- **Compatibility** against gear you own: a few lens and body pairs you know the answer for,
  and an adapter of yours entered as one.
- **The camera preview in landscape**, in the barcode scanner, the label scanner and the light
  meter. The review flagged its rotation as possibly wrong; a simulator has no camera to check.
- **The camera beside another app on iPad** (Split View, Stage Manager): whether the light meter
  and scanner are interrupted, and what they show if so.

---

## M5 — 1.0 release prep

**Done 2026-10-12** on `claude/camera-gear-manager-e1zzxt` (commits `af1e66d`…`4dd3a1e`, and
the commit that adds this section). What's left needs your Apple account and devices: the
[release checklist](../ROADMAP.md#release-checklist).

### What shipped
- **Tip Jar:** `ShutterManager.storekit` offers the three tips when you run from Xcode, and a
  test checks it against the app's list.
- **About and privacy:**
  - About describes all seven areas of the app.
  - The privacy policy has one source, shown in the app and written to `docs/PRIVACY.md` for
    hosting; a test fails if the two differ. It covers the barcode lookup, Apple Maps, iCloud
    and notifications.
- **App Store material:**
  - `marketing/1.0/`: name, subtitle, promotional text, keywords, description, What's New and
    review notes as one file per field, checked against App Store Connect's limits, plus
    `APP_STORE.md` with the category, age rating, App Privacy answer, tip products and
    screenshot order.
  - `docs/RELEASE_NOTES_1.0.md`: what's in 1.0 and its known limits.
  - Dark and tinted app icons from the same generator.
- **Screenshots:** a CI job captures eight screens on the 6.9" iPhone and 13" iPad from a
  fictional library, in dark mode at 9:41, and checks their sizes.
- **Accessibility:**
  - Dynamic Type everywhere `ResponsiveConstants` is used, now a required argument; line limits
    relax at accessibility sizes, and wide rows stack.
  - VoiceOver: decorative icons hidden, rows combined, chosen options marked as selected, chart
    bands and the map labelled, countdowns spoken as durations, and the sun and moon chart's
    moment moved by swiping up or down.
  - State in words, not only color: overdue, invalid input, up or down in value.
  - Readable color: the light-mode accent, category colors and status text all reach 4.8:1 or
    better in both modes (`AppColors`).
  - 44-point targets on the day stepper and the mount menu.
- **Tests:**
  - 70 Foundation-only tests (2 new for the privacy policy), which run on Linux too;
  - 179 unit tests in all;
  - 17 UI tests on each of iPhone and iPad, 5 of them new: Xcode's accessibility audit on each
    tab's main screens.

### Verified
[CI run 38190897231](https://github.com/jcfurey/gear_manager/actions/runs/38190897231) passed
every job:
- the Foundation tests in the Swift 6.2 Linux image;
- the Debug and Release builds with warnings as errors;
- 179 unit tests;
- 17 UI tests on each of iPhone 17 and iPad (iOS 26.5), the accessibility audit included;
- the screenshots on iPhone 17 Pro Max and iPad Pro 13-inch (M5).

### Changes from the plan
- **The audit runs three checks** (labels, touch targets, reachable text). A full audit of every
  type was run once, and its real findings were fixed. Its Dynamic Type check flagged system text
  styles that do scale, and made two iPad audits run past the 10-minute test limit. Its contrast
  check flagged text under the iOS 26 bars' edge fade. `AccessibilityAuditTests` says why.
- **CloudKit Production deployment and device acceptance** are steps in the release checklist,
  since they need your account and devices.
- **Not in the plan:**
  - App Store text checked by the convention checks;
  - a script that writes the public privacy page.

### Found by the screenshots and the audit, and fixed
- On iOS 26, a `Label` used as a row's value left a tall empty gap under the gear Category and
  shoot Type rows.
- The sun and moon chart labelled its hours, and the date picker showed the day, in the device's
  time zone rather than the place's.
- Button rows set `.primary` text, which a button tints with the accent.
- The inventory card's category chip broke mid-word beside a badge.
- The light-mode accent was 2.5:1 on white; system yellow, mint, cyan and orange category text,
  and red, orange and green status text, were 1.6 to 3.6:1.
- Importing StoreKitTest fails the build with warnings as errors (a header uses a type iOS 18
  deprecates), so the tip test checks the configuration file instead.

### Still to check on a device
Everything in the release checklist's acceptance step, and in particular:
- VoiceOver and the largest text sizes on each tab, which simulators can only approximate;
- the light-mode colors, which the screenshots (dark mode) don't show;
- the dark and tinted icons on the Home Screen.

---

## M4 — Shoots

**Done 2026-10-11** on `claude/camera-gear-manager-e1zzxt` (commits `094d470`…`9bb8cf6`).

### What shipped
- **The Shoots tab:** a searchable shoot log, upcoming and past, with links to film rolls, kits and
  shot-list templates.
- **A shoot:**
  - title, type, start and end, client, place and notes;
  - that day's sunrise, sunset and golden and blue hours at the place, in its time zone;
  - an optional golden-hour heads-up, 15 minutes to 2 hours before.
- **Packing check:** tick off the shoot's gear. Items lent out, needing service or a sensor
  cleaning, or rented and due back before the shoot ends are flagged.
- **Kits:** named sets of gear with a symbol, added to a shoot in one go.
- **Shot lists:**
  - ticked off on the day, with shots added as you go;
  - start from six built-in starters (wedding, engagement, portrait session, event, real
    estate, product) or your own templates;
  - save any shoot's list as a template. Templates are copied, never linked, so editing one
    later leaves shoots alone.
- **Film roll log:**
  - stock, format, camera, rated speed, push or pull, frames shot, lab and notes;
  - status from loaded to shot, at the lab, developed and scanned, with a swipe to the next one;
  - rolls attach to the shoot they were shot on.
- **The light meter** can meter for a loaded roll: its film (for reciprocity) and its rated speed.
- **Gear detail** shows each item's use: shoots so far, when it was last used, its next shoot, its
  kits, and the roll loaded in a film camera.
- **Data:** six new models (`Shoot`, `ShotListItem`, `Kit`, `ShotListTemplate`,
  `ShotListTemplateItem`, `FilmRoll`), covered by export, import (merge and replace), backups,
  the import preview and "Delete All Data".
- **Privacy policy:** shoots and their places, kits, templates, film rolls and golden-hour
  heads-ups.
- **Tests:**
  - 68 Foundation-only tests, 6 of them new (a shoot's golden hours), which run on Linux too;
  - unit tests for the log's rules, the drafts, deleting, export and import with gear links, and
    shoot alerts, bringing the total to 176;
  - 2 new UI tests: plan a shoot and tick off its shot list; load a roll and meter for it.

### Verified
[CI run 38180936784](https://github.com/jcfurey/gear_manager/actions/runs/38180936784) passed
every job:
- the Foundation tests in the Swift 6.2 Linux image;
- the Debug and Release builds with warnings as errors;
- 176 unit tests;
- 12 UI tests on each of iPhone 17 and iPad (iOS 26.5).

### Changes from the plan
- **The golden-hour heads-up** is set per shoot. It covers the golden hours that overlap the
  shoot, or the next one after it starts, so a midday shoot hears about the evening light.
  Background refreshes never show the permission prompt; saving a shoot that asks for a
  heads-up can.
- **A shoot copies its place** rather than linking to a saved place, so deleting or renaming a
  saved place never changes a shoot.
- **Packing ticks** are stored on the shoot as item IDs, not as another model.
- **Usage counts only shoots that have started.** Planned ones show as the next shoot.
- **Not in the plan:**
  - a "next shoot" and the loaded roll on gear detail;
  - a rented item due back before the shoot ends is flagged in the packing check;
  - built-in starters can be copied into your own templates.

### Found by CI and fixed
- The shoot-alert unit tests had been appended to the wrong suite and couldn't build.
- On iPad, the light meter's "Use a Loaded Roll" menu never opened under UI tests. It's now a
  pushed list, the same on iPhone and iPad.

### Still to check on a device
- A golden-hour heads-up arriving on time, for a shoot at your location and one in another time
  zone.
- The packing check and shot list on a real shoot, and the film roll log through a roll's life.
- The new models need the CloudKit schema updated. Run `-initializeCloudKitSchema` again, review
  `Shoot`, `ShotListItem`, `Kit`, `ShotListTemplate`, `ShotListTemplateItem` and `FilmRoll` in
  CloudKit Console, then check that shoots and their gear links sync between two devices.

---

## M3 — Light Meter and sky planning

**Done 2026-10-11** on `claude/camera-gear-manager-e1zzxt` (commits `ce01591`…`f4f46de`).

### What shipped
- **The Light Meter tab:**
  - a reflected-light reading from the camera, as EV at ISO 100, from the whole frame or a spot
    you tap on the preview;
  - hold, and a typed EV when there's no camera (or you'd rather);
  - aperture, shutter or ISO priority, with the answer snapped to third stops and a warning when
    it's off the scale;
  - filter compensation, typed or from an inventory filter;
  - a film's box speed for the ISO, and its reciprocity correction on long times;
  - "Send to ND Filter", which opens the ND calculator in the Tools tab with the metered time.
- **One camera owner.** `CaptureSessionCoordinator` owns the capture session and its one preview
  layer. The barcode scanner moved onto it. Each client starts the camera for itself, and a stop
  only lands while that client still owns it.
- **Sky planners** (Tools → Sky):
  - **Sun & Moon:** sunrise, sunset and solar noon; civil, nautical and astronomical twilight;
    golden and blue hours; moonrise and moonset with their directions; phase and lit fraction.
    An altitude chart shades the golden and blue hours and can be dragged to read any moment. A
    map draws the directions, and a list shows the next four moon phases. Days step back and
    forward, or come from a date picker.
  - **Milky Way:** the next 21 nights, each with its dark, moonless hours and when the galactic
    core is at least 10° up. A night's detail charts the core, moon and sun.
- **Places:**
  - `SavedPlace`, covered by export, import (merge and replace), backups and "Delete All Data";
  - one-shot location while in use;
  - a place picker with Apple Maps search, a tap on the map, or typed coordinates, which looks up
    the place's name and time zone;
  - times show in the place's time zone.
- **Astronomy** (`Models/PhotoMath/`, Foundation-only): Meeus's sun (ch. 25) and moon (ch. 47),
  sidereal time, nutation and ΔT; events found by searching altitude crossings; moon phases from
  the elongation; the galactic centre precessed to date.
- **Settings:** the light meter's calibration, exported with the other settings.
- **Privacy policy:** location, Apple Maps search, the light meter, and timer alerts.
- **Tests:**
  - 62 Foundation-only tests, 25 of them new (astronomy and the light meter), which run on Linux
    too;
  - unit tests for saved places in export, import and backups, and the calibration setting,
    bringing the total to 151;
  - 2 new UI tests: the sun and moon planner from typed coordinates, and a typed light-meter
    reading sent to the ND calculator. The tools test opens the two new tools.

### Verified
[CI run 38163447209](https://github.com/jcfurey/gear_manager/actions/runs/38163447209) passed
every job:
- the Foundation tests in the Swift 6.2 Linux image;
- the Debug and Release builds with warnings as errors;
- 151 unit tests;
- 10 UI tests on each of iPhone 17 and iPad (iOS 26.5).

### Accuracy
Against USNO's "Sun and Moon Data for One Day" for six places and dates (see
[PHOTO_MATH_REFERENCES.md](PHOTO_MATH_REFERENCES.md#sun-and-moon)):
- sunrise, sunset, twilight and solar noon came within 0.53 minutes, against a target of 1–2;
- moonrise and moonset came within 0.44 minutes, against a target of about 5;
- Tromsø's midnight sun and polar night are handled;
- 2026's first 12 principal moon phases came within 3 minutes.

### Changes from the plan
- **The Milky Way planner is its own tool**, beside Astro Exposure, rather than part of it.
- **Moon phases are found numerically** from the moon's elongation, instead of with Meeus
  chapter 49's series. They agree with USNO within 3 minutes.
- **The date scrubber** is a day stepper with a date picker; dragging across the chart scrubs the
  time of day.
- **Spot metering** sets the camera's exposure point of interest. The camera meters a region
  around it, not a 1° spot.
- **ISO from film:** the meter takes a film stock's box speed now. Taking it from a loaded roll
  waits for M4's roll log, as planned.
- **Not in the plan:**
  - `AppNavigation`, the selected tab and the Tools stack, which lets the meter open the ND
    calculator;
  - reciprocity on the meter's long times;
  - the preview stays level as an iPad turns.

### Found by CI and fixed
- A CoreLocation delegate method, which isn't isolated to the main actor, read a main-actor
  message. It was the only compile error.
- Picking a place on the map didn't return to the planner. The selection list called `dismiss`
  from underneath the map picker, which doesn't pop the stack. Place selection is now a sheet, so
  every way of choosing closes it, picker and all.
- The light-meter UI test looked for a stepper button labelled "Increment". SwiftUI names a
  stepper's buttons after its identifier (`meter.manualEV-Increment`).

### Still to check on a device
- The light meter against a handheld meter or your camera in bright sun, overcast, indoors and at
  dusk, then set the calibration. Check the spot point, holding, and the preview on an iPad as it
  turns.
- The barcode scanner on the shared camera, and moving between it and the light meter.
- The location prompt and "Use My Location"; search, and the names and time zones of picked
  places.
- Sun and moon times where you are against a source you trust.
- `SavedPlace` needs the CloudKit schema updated. Run `-initializeCloudKitSchema` again, review
  `SavedPlace` in CloudKit Console, then check that places sync between two devices.

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
