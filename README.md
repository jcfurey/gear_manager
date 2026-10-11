# Shutter Manager

A camera-gear manager with field tools for photographers, for iPhone and iPad. It's free, with an
optional Tip Jar and no paid tier. Work is in progress: the [roadmap](ROADMAP.md) has the plan and
milestones.

- **Platform:** iOS 18.6 or later; Xcode 26; Swift 5 language mode
- **Architecture:** SwiftUI, SwiftData with private CloudKit sync, and feature services
- **Dependencies:** Apple frameworks only

The five tabs are **Inventory · Tools · Light Meter · Shoots · Settings**.

## What works today (Milestone 1)

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

**Your data**
- Private iCloud sync across your devices, with a local-only fallback.
- Export to JSON (restorable, photos optional), CSV and PDF; import by merge or replace.
- Automatic and manual backups, with retention.

The Tools, Light Meter and Shoots tabs arrive in milestones 2–4: exposure, depth of field and
astro calculators, a light meter, sun and moon planning, shoot logs, kits, shot lists, and film.

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
