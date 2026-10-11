# Shutter Manager

A camera-gear manager with field tools for photographers, for iPhone and iPad. It's free, with an
optional Tip Jar and no paid tier. Work is in progress: the [roadmap](ROADMAP.md) has the plan and
milestones.

- **Platform:** iOS 18.6 or later; Xcode 26; Swift 5 language mode
- **Architecture:** SwiftUI, SwiftData with private CloudKit sync, and feature services
- **Dependencies:** Apple frameworks only

The five tabs are **Inventory · Tools · Light Meter · Shoots · Settings**.

## What works today (Milestones 1 and 2)

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
- **Astro:** the NPF and 500 rules from your camera's pixel pitch; star trails.
- **Calculators:** time-lapse, flash guide numbers, print size and resolution.
- **Film:**
  - long-exposure (reciprocity) correction from the makers' datasheets. There are 33 film stocks;
    the makers publish figures for 29 of them;
  - a development timer that runs your saved recipes step by step, with agitation and pour alerts.
- The tools fill in from your inventory: a camera's format and resolution, a lens's focal length
  and aperture, an ND filter's strength, a flash's guide number.
- Metric or imperial units.

**Your data**
- Private iCloud sync across your devices, with a local-only fallback.
- Export to JSON (restorable, photos and development recipes included), CSV and PDF; import by
  merge or replace.
- Automatic and manual backups, with retention.

The Light Meter and Shoots tabs arrive in milestones 3 and 4: a light meter, sun and moon
planning, shoot logs, kits, shot lists, and a film roll log. The formulas and sources behind the
tools are in [docs/PHOTO_MATH_REFERENCES.md](docs/PHOTO_MATH_REFERENCES.md).

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
