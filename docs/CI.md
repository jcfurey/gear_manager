# Continuous integration

One workflow, `.github/workflows/ci.yml`, runs on pushes to `main` and `claude/**`, on every pull
request, and on demand (Actions → CI → Run workflow). Its last job, **CI result**, passes only if
every other job passed or was skipped on purpose, so it's the one status to require in branch
protection (Settings → Branches → `main` → Require status checks → `CI result`).

## Jobs

| Job | Runner | What it checks | When |
|---|---|---|---|
| Detect changes | Linux | Whether anything besides docs changed. Docs-only changes skip the macOS jobs | Always |
| Conventions and lint | Linux | `Tools/ci/check_conventions.py`, actionlint on the workflows, ShellCheck and Python syntax on the CI scripts | Always; the macOS jobs wait for it |
| Foundation tests (Linux) | Linux, in the official Swift image | The Foundation-only unit tests (photography math, film and format catalogs) built with Swift for Linux | App changes |
| Build and unit tests | macOS | Builds the app and both test targets with **warnings as errors**, then runs the unit tests with coverage | App changes |
| Release build (device) | macOS | The Release configuration for a device, unsigned: what an archive compiles | App changes |
| UI tests (iPhone, iPad) | macOS | The XCUITest suite on an iPhone and an iPad simulator, including the accessibility audit of each tab | App changes on pull requests, `main`, and manual runs |
| Screenshots (iphone-6.9, ipad-13) | macOS | Captures the App Store screenshots from a fictional library on an iPhone 17 Pro Max and an iPad Pro 13-inch, checks their sizes, and uploads them as artifacts (`marketing/README.md`) | Manual runs with `screenshots` ticked |
| CI result | Linux | Sums up the jobs above | Always |

Each macOS job writes a summary on the run page (errors and warnings with file and line, test
counts, each failure's message, line coverage) and annotates errors on the changed files. A
failed UI test's summary also shows the app's accessibility hierarchy at the moment it failed,
which is usually enough to see why a control wasn't found. When a
job fails, its `.xcresult` bundle is uploaded as an artifact for 7 days; open it in Xcode for
screenshots, logs and the full test report.

## Design choices

- **Warnings are errors in CI.** The codebase starts with none, so keeping it that way costs
  little. Local builds still treat them as warnings, so work in progress isn't blocked.
- **Xcode is pinned** in `.xcode-version`. With warnings as errors, an unannounced Xcode upgrade on
  the runner image could fail the build for reasons unrelated to the change. Upgrading Xcode is
  a one-line change to that file. If the runner no longer has the pinned version, CI falls back
  to the newest Xcode with the same major version and shows a warning on the run.
- **Simulators are picked by UDID** from the newest iOS runtime (`Tools/ci/select_simulator.py`).
  A name like "iPhone 17" can exist under several runtimes.
- **Build first, then boot.** The build targets the generic simulator
  (`generic/platform=iOS Simulator`, the runner's own architecture), and the simulator boots
  after it. Booting it in the background during the build looked like a saving but made the
  build take 4-5 minutes instead of under one: the build's asset tools wait on the same
  simulator runtime the first boot is busy with. The UI-test and screenshot jobs then boot it
  in the foreground and wait for `simctl bootstatus` before testing: left to `xcodebuild`, the
  first UI test's app launch once landed mid-boot on iPad and timed out acquiring a background
  assertion.
- **The unit-test host app uses a temporary in-memory library.** The unit tests build their own
  containers, so the app hosting them doesn't open the simulator's library or start CloudKit
  setup. That alone took the unit-test step from about 7 minutes to under 4.
- **Unit tests run in one simulator** (`-parallel-testing-enabled NO`). Swift Testing still runs
  tests in parallel within it; cloned simulators are what tends to be slow and flaky in CI.
- **UI tests don't run on every branch push.** They're the slowest job. They run on pull requests,
  on `main`, and on demand. They run on iPhone and iPad, since the app supports both.
- **The Release build is a separate job** so it runs alongside the Debug build. It catches code
  that only compiles in Debug or only for the simulator.
- **The Foundation-only code is also tested on Linux.** `Models/PhotoMath/` and the catalogs must
  not import Apple-only frameworks, so a cloud session without Xcode can test them
  (`Tools/linux/run_foundation_tests.sh`). Building them on Linux enforces that, and the job
  finishes in a couple of minutes, before the macOS ones. The Swift image is pinned by digest
  and updated by hand, as Dependabot doesn't update job containers.
- **The convention checks gate the macOS jobs.** They take seconds, and a rule break caught there
  doesn't spend macOS time.
- **Actions are pinned by commit SHA**, and Dependabot (`.github/dependabot.yml`) proposes updates
  weekly. actionlint is downloaded at a pinned version and checked against its SHA-256.
- **No build caching.** A clean build takes about a minute, and a stale DerivedData cache is a
  classic source of confusing failures.
- **Least privilege.** The workflow's token can only read the repository.

## Running the same checks locally

On any machine with Python 3:

```bash
python3 Tools/ci/check_conventions.py
```

With a Swift toolchain (Linux or macOS), the Foundation-only tests:

```bash
Tools/linux/run_foundation_tests.sh            # or: Tools/linux/run_foundation_tests.sh /path/to/swift
```

On a Mac with Xcode (the commands CI runs):

```bash
Tools/ci/select-xcode.sh                       # optional: switch to the pinned Xcode (uses sudo)
UDID=$(python3 Tools/ci/select_simulator.py iPhone | awk '{print $NF}')

xcodebuild build-for-testing -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination "platform=iOS Simulator,id=$UDID" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES

xcodebuild test-without-building -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination "platform=iOS Simulator,id=$UDID" -only-testing:ShutterManagerTests

xcodebuild test -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination "platform=iOS Simulator,id=$UDID" -only-testing:ShutterManagerUITests
```

## What the convention checks enforce

`Tools/ci/check_conventions.py` covers rules the compiler can't:

- **models**: every `@Model` is CloudKit-safe. Non-optional attributes have defaults,
  relationships are optional, there are no unique constraints, and there is no `.deny` delete rule.
- **registry**: every `@Model` is listed in `AppSchema.models`, and nothing else is.
- **in-memory**: in-memory `ModelConfiguration`s (tests, previews) set `cloudKitDatabase: .none`.
- **logging**: app code logs with `os.Logger`, not `print`, `debugPrint`, `NSLog` or `dump`.
- **capabilities**: the entitlements name the `iCloud.jcameronfurey.shuttermanager` container
  (and Swift code names no other), don't set `default-data-protection`, and Info.plist keeps the
  remote-notification background mode CloudKit sync needs.
- **project**: deployment target, version, build number and Swift version agree across every
  target and configuration; bundle IDs are the expected three; Swift files aren't referenced
  individually (the targets use folder-synced groups); asset catalog JSON parses.
- **leftovers**: no names from the Axe Manager port (guitar, tuner, axemanager, and so on).
- **store-text**: each `marketing/<version>/` folder has every App Store text field, each within
  App Store Connect's limit, and the keywords have no spaces after commas or repeats.

To accept a flagged line on purpose, end it with `// conventions:allow <check-name>`.
