# Shutter Manager

A camera-gear manager with field tools for photographers, for iPhone and iPad. It's free, with an
optional Tip Jar and no paid tier. Version 1.0 is ready for the App Store, apart from the steps
only the owner can do (see the release checklist in the [roadmap](ROADMAP.md)).

- **Platform:** iOS 18.6 or later; Xcode 26; Swift 5 language mode
- **Architecture:** SwiftUI, SwiftData with private CloudKit sync, and feature services; a
  widget extension for the timers' Live Activity
- **Dependencies:** Apple frameworks only

The five tabs are **Inventory · Tools · Light Meter · Shoots · Settings**.

## What's in 1.0

**Inventory**
- Category-aware forms for:
  - camera bodies and lenses;
  - lighting, support, filters, drones and audio;
  - batteries and power, memory cards, bags, accessories, and other gear.
- Fields include:
  - bodies: mount, sensor format (custom sizes too), resolution, rated shutter life;
  - lenses: focal range, aperture, filter thread, minimum focus;
  - other gear: firmware, charge cycles, guide number.
- **Fill from a photo:** pick a photo the camera or lens took and its EXIF fills in:
  - make, model and serial;
  - firmware and resolution;
  - lens details;
  - the shutter count, from Nikon bodies.
- **Shutter-count history** with a chart against the rated shutter life.
- **Loans and rentals:** who has the gear, when it's due back, and a reminder.
- **Sensor-cleaning reminders**, plus a maintenance log and reminders.
- **Value:** purchase price and an optional current value, with collection stats. Each item links
  to searches on MPB, KEH, eBay, B&H and Adorama.
- Status badges for gear that's on loan, overdue, due for cleaning, needing service, or near its
  shutter's rated life.
- Barcode lookup, photo galleries, search, sort and category filters.

**Tools**
- **Exposure:**
  - equivalent exposure;
  - ND filters (stacked, from your inventory) with a bulb timer;
  - Sunny 16.
- **Optics:** depth of field and hyperfocal distance, field of view, and crop equivalents.
- **Sky:**
  - a sun and moon planner for any place and date: sunrise and sunset, twilights, golden and blue
    hours, moonrise and moonset with directions, an altitude chart to scrub through the day, a map
    of the directions, and the coming moon phases;
  - a Milky Way planner that lists the coming nights' dark, moonless hours with the galactic core
    up;
  - the cloud forecast for those hours, if you turn it on (see below);
  - astro exposure: the NPF and 500 rules from your camera's pixel pitch, and star trails.
- **Places:** your current location, a place found by search or a tap on the map, or typed
  coordinates. Save places to reuse them; they sync with the rest of your library.
- **Calculators:** time-lapse, flash guide numbers, print size and resolution.
- **Film:**
  - long-exposure (reciprocity) correction from the makers' datasheets. There are 33 film stocks;
    the makers publish figures for 29 of them;
  - a development timer that runs your saved recipes step by step, with agitation and pour alerts.
- The tools fill in from your inventory: a camera's format and resolution, a lens's focal length
  and aperture, an ND filter's strength, a flash's guide number.
- Metric or imperial units.

**Light Meter**
- A reflected-light reading from the camera, as EV at ISO 100, whole-frame or from a spot you tap.
- Hold a reading; type the EV by hand when there's no camera.
- Aperture, shutter or ISO priority, with the answer on the third-stop scales.
- Filter compensation, a film's box speed and reciprocity, and a calibration you can set against
  a meter you trust.
- Send the result to the ND filter calculator.

**Shoots**
- A shoot log, upcoming and past: when, where, the client, the type and notes.
- That day's sunrise, sunset and golden and blue hours at the shoot's place, and an optional
  heads-up before golden hour.
- A packing check of the shoot's gear that flags items lent out, needing service or due back.
- Kits: saved sets of gear, added to a shoot in one go.
- Shot lists ticked off on the day. Start one from a built-in starter (wedding, engagement,
  portrait session, event, real estate, product) or your own template, and save any shoot's list
  as a template.
- A film roll log: stock, format, camera, rated speed, push or pull, frames, and where it is
  (loaded, shot, at the lab, developed, scanned). The light meter can meter for a loaded roll.
- Each item's use: how many shoots, when it was last used, its next shoot and its kits.

**Your data**
- Private iCloud sync across your devices, with a local-only fallback.
- Export the whole library, photos included, as one file (a zip any computer can open: the
  records as JSON and each photo as a file), or as JSON, CSV or PDF; import by merge or replace.
- Automatic and manual backups, with retention.

**Accessibility**
- Dynamic Type, including the accessibility sizes; VoiceOver labels throughout; dark mode.

The formulas and sources behind the tools, the light meter and the sky planners are in
[docs/PHOTO_MATH_REFERENCES.md](docs/PHOTO_MATH_REFERENCES.md).

## Added since 1.0

These are built and tested, and aren't in the 1.0 App Store text or release notes yet.

- **A report for your insurer:** a PDF of your gear, or a chosen part of it, with serial numbers,
  purchase prices, current values and photos, grouped by category with totals. From Settings or
  the Collection screen.
- **QR labels:** print labels for kits and gear on Letter or A4, two sizes, with an optional
  "if found" line. Pointing the Camera app at a label opens the kit's checklist or the item. The
  code holds only an ID from your library.
- **Usage from photos:** choose photos, files or a whole folder and see how many shots each body
  and lens took.
  - Bodies and lenses are matched to your inventory by serial number, then by name; a match you
    choose is remembered on that device.
  - A shutter count the files carry (Nikon) is recorded as a reading, dated by the photo.
  - Gear the inventory lacks can be added, and the batch logged as a shoot or its gear added to
    one, which is where an item's use is counted from.
  - Everything is read on the device; the photos aren't copied or kept.
- **Lens and body compatibility:** a body's screen lists your lenses by how they go on it: fits,
  with an adapter you have, with an adapter, or doesn't fit. A lens's screen lists your bodies.
  - Worked out from the flange distances of 33 mounts and 22 adapters that the camera and lens
    makers sell for their own systems, each cited in the references.
  - An adapter you own is added as a lens whose mount names both sides ("Canon EF → Sony E");
    it then counts for that pair.
  - A lens made for a smaller format than the body's says so.
  - A shoot's packing check flags a lens that goes on none of the bodies packed with it.
- **Usage from photos also says how each lens was used:** a zoom's range and the focal lengths
  used most, with a small chart, and the apertures used most.
- **Find Duplicates** (Settings): importing a file before iCloud has finished syncing the same
  library puts every record in twice. This counts the records that share an ID and folds each
  set into one, keeping the copy changed last with anything only another copy had. A backup is
  made first, and the import screen now warns when iCloud hasn't finished.
- **Timers on the Lock Screen and in the Dynamic Island:** a running bulb exposure or
  development step shows as a Live Activity, with a countdown that keeps moving while the phone
  is locked, a progress bar, and what follows ("Next: Stop", "Close the shutter").
- **Cloud forecast**, from Apple Weather, in the sun and moon planner, the Milky Way planner and
  on a shoot still to come: a chart of the hours, and the cloud over each golden hour, dark
  window or the shoot itself, by height (low, mid, high), with the chance of precipitation. It
  reaches ten days ahead. It's off until you turn it on, because getting it sends the place's
  position to Apple, rounded to about a kilometre.
- **One file for a library of any ordinary size.** An export or backup used to be one JSON file
  with the photos inside it, held whole in memory, so it stopped at 256 MB: a larger export was
  refused, and a larger backup left its photos out. A library now travels as a zip with each
  photo as a file of its own, written and read a few at a time, up to 3 GB. Importing one again
  after it stopped part-way adds what's missing, and older JSON files still import.
- **Timers alert in the app when notifications are off:** a banner, a haptic and a short tone at
  each agitation, pour and end, on whichever screen is up, while the app is open.
- **Fixes from a review of the 1.0 code:** maintenance reminders now notify; timer alerts keep
  the ones that matter when there are more than iOS allows; a shoot keeps its clock time when its
  place changes time zone; exports and backups that are too large say so instead of failing
  silently; and a dozen smaller ones (see [docs/PROGRESS.md](docs/PROGRESS.md)).

## Release material
- [docs/RELEASE_NOTES_1.0.md](docs/RELEASE_NOTES_1.0.md): what's in 1.0, and its known limits.
- [docs/PRIVACY.md](docs/PRIVACY.md): the privacy policy to host, written from the one the app
  shows.
- [marketing/](marketing/README.md): the App Store text and answers for 1.0, and how CI makes the
  screenshots.

## Build and test

```bash
xcodebuild -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild test -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ShutterManagerTests

python3 Tools/ci/check_conventions.py   # project rules; needs only Python 3
```

CI runs on GitHub Actions. [docs/CI.md](docs/CI.md) describes each job and how to run the same
checks locally. [CLAUDE.md](CLAUDE.md) lists the code conventions.

## Before running on a device

Run these steps in Xcode → Signing & Capabilities:
1. Register the App ID `jcameronfurey.shuttermanager`.
2. Register the iCloud container `iCloud.jcameronfurey.shuttermanager`.
3. Turn on iCloud (CloudKit) and Background Modes → Remote notifications.

The simulator and CI don't need any of this.

## License

For educational and personal use.
