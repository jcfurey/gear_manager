#!/bin/bash
# Writes docs/PRIVACY.md, the public privacy policy page, from PrivacyPolicy.swift, which is also
# what the app shows. Run it after changing the policy; PrivacyPolicyTests fails until the page
# matches. Needs only a Swift toolchain, so it runs on Linux and macOS alike.
#
# Usage: Tools/linux/write_privacy_policy.sh [path/to/swiftc]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SWIFTC="${1:-swiftc}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf 'print(PrivacyPolicy.markdown, terminator: "")\n' > "$WORK/main.swift"
"$SWIFTC" -swift-version 5 -o "$WORK/write_policy" \
  "$ROOT/ShutterManager/Utilities/PrivacyPolicy.swift" "$WORK/main.swift"
"$WORK/write_policy" > "$ROOT/docs/PRIVACY.md"
echo "Wrote docs/PRIVACY.md"
