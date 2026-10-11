# Shutter Manager

A camera-gear manager with field tools for photographers, for iPhone and iPad. Under construction:
see the [roadmap](ROADMAP.md) for the plan and milestones.

- **Platform:** iOS 18.6 or later; Xcode 26; Swift 5 language mode
- **Architecture:** SwiftUI, SwiftData with private CloudKit sync, and feature services
- **Dependencies:** Apple frameworks only

The five tabs are **Inventory · Tools · Light Meter · Shoots · Settings**.

## Build and test

```bash
xcodebuild -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild test -project ShutterManager.xcodeproj -scheme ShutterManager \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ShutterManagerTests
```

CI runs on GitHub Actions; [docs/CI.md](docs/CI.md) describes each job and how to run the same
checks locally.

## License

For educational and personal use.
