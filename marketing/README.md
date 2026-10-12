# Marketing

The App Store screenshots and text. `1.0/` holds what to enter in App Store Connect for 1.0.0:
the text fields as `.txt` files and everything else in `1.0/APP_STORE.md`. Start a new folder for
a version whose text changes; `Tools/ci/check_conventions.py` checks every folder's text against
App Store Connect's limits.

## Screenshots

The screenshots are captured by CI from a fictional library, so they never show anyone's data and
can be made again whenever the screens change.

1. In GitHub, open **Actions → CI → Run workflow**, choose the branch, and tick
   **screenshots**. (You can tick **ui_tests** too; the two run side by side.)
2. When the run finishes, download the artifacts `screenshots-iphone-6.9` and
   `screenshots-ipad-13`. Each holds `01-inventory.png` to `08-film-rolls.png` and a
   `capture-manifest.json` with each file's size, device and checksum.
3. Upload them to App Store Connect in file-name order.

How it works:
- `ShutterManager/Utilities/ReleaseScreenshotData.swift` builds the library: fictional makes
  (Northwind, Meridian, Lumen, Fieldcraft, Swift, Skylark), shoots around today's date, and a
  shoot at Mesa Arch so the sky planner has a place.
- `ShutterManagerUITests/ReleaseScreenshotTests.swift` walks the app and attaches a screenshot of
  each screen. It runs in English, in dark mode, with the status bar at 9:41 and full battery.
- Both files compile only with the `RELEASE_SCREENSHOTS` flag, which only the `screenshots` CI job
  sets, and the library loads only with `-uiTestInMemory` and `-releaseScreenshots`. An ordinary
  build can't show it.
- The job runs on an iPhone 17 Pro Max (1320 × 2868, the 6.9" size) and an iPad Pro 13-inch
  (2064 × 2752). `export-screenshots.py` takes the attachments out of the result bundle and fails
  if one is missing, repeated, the wrong size, or has transparency, which App Store Connect
  rejects.

To change a screenshot, edit the demo library or the test, then run the job again. Running the
capture in Xcode needs `RELEASE_SCREENSHOTS` added to the scheme's Active Compilation Conditions
for the app and UI-test targets.
