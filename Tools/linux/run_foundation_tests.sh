#!/bin/bash
# Runs the Foundation-only unit tests (photography math and catalogs) on any machine with a Swift
# toolchain, Linux included, so a cloud session without Xcode can test them before pushing.
#
# Usage: Tools/linux/run_foundation_tests.sh [path/to/swift]
#
# It builds a throwaway SwiftPM package from symlinks to the files below. Add a file here when
# it's Foundation-only and its tests are too. The same tests also run in Xcode with the rest of
# the suite.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SWIFT="${1:-swift}"

SOURCES=(
  ShutterManager/Models/PhotoMath/*.swift
  ShutterManager/Models/Catalog/SensorFormat.swift
  ShutterManager/Models/Catalog/FilmStock.swift
  ShutterManager/Models/Catalog/FilmStockCatalog.swift
)
TESTS=(
  ShutterManagerTests/PhotoMathTests.swift
  ShutterManagerTests/FilmStockTests.swift
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/ShutterManager" "$WORK/Tests/FoundationTests"

cd "$ROOT"
for file in "${SOURCES[@]}"; do
  [ -f "$file" ] && ln -s "$ROOT/$file" "$WORK/Sources/ShutterManager/$(basename "$file")"
done
for file in "${TESTS[@]}"; do
  [ -f "$file" ] && ln -s "$ROOT/$file" "$WORK/Tests/FoundationTests/$(basename "$file")"
done

cat > "$WORK/Package.swift" <<'PACKAGE'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FoundationTests",
    targets: [
        .target(name: "ShutterManager", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FoundationTests", dependencies: ["ShutterManager"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
PACKAGE

cd "$WORK"
"$SWIFT" test 2>&1 | grep -v '^\[[0-9]*/[0-9]*\]'
