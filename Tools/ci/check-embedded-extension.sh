#!/usr/bin/env bash
# Checks that a built ShutterManager.app carries its widget extension, set up the way iOS and App
# Store Connect require. The builds are quiet, and a target that silently stopped being embedded
# would still compile: this says what the build actually made.
#
# Usage: Tools/ci/check-embedded-extension.sh path/to/ShutterManager.app   (macOS: uses PlistBuddy)
set -euo pipefail

app="${1:?usage: check-embedded-extension.sh path/to/ShutterManager.app}"
appex="$app/PlugIns/ShutterManagerWidgets.appex"
buddy=/usr/libexec/PlistBuddy

fail() {
  echo "::error title=Widget extension::$1"
  echo "$1" >&2
  exit 1
}

# The value at a key path in a bundle's Info.plist, or nothing when it isn't there.
value() {
  "$buddy" -c "Print :$2" "$1/Info.plist" 2>/dev/null || true
}

[[ -d "$app" ]] || fail "No app at $app."
[[ -d "$appex" ]] || fail "The app has no PlugIns/ShutterManagerWidgets.appex: the extension isn't embedded."
[[ -f "$appex/ShutterManagerWidgets" ]] || fail "The extension has no executable."

point="$(value "$appex" "NSExtension:NSExtensionPointIdentifier")"
[[ "$point" == "com.apple.widgetkit-extension" ]] \
  || fail "The extension's NSExtensionPointIdentifier is '$point', not com.apple.widgetkit-extension."

[[ "$(value "$app" "NSSupportsLiveActivities")" == "true" ]] \
  || fail "The app's Info.plist doesn't set NSSupportsLiveActivities, so its Live Activity can't start."

app_id="$(value "$app" "CFBundleIdentifier")"
extension_id="$(value "$appex" "CFBundleIdentifier")"
[[ -n "$app_id" && "$extension_id" == "$app_id".* ]] \
  || fail "The extension's bundle ID '$extension_id' doesn't start with the app's, '$app_id'."

# App Store Connect rejects an extension whose version or build number differs from its app's.
for key in CFBundleShortVersionString CFBundleVersion; do
  app_value="$(value "$app" "$key")"
  extension_value="$(value "$appex" "$key")"
  [[ -n "$app_value" && "$app_value" == "$extension_value" ]] \
    || fail "$key is '$extension_value' in the extension and '$app_value' in the app."
done

echo "Widget extension: $extension_id $(value "$appex" "CFBundleShortVersionString") ($(value "$appex" "CFBundleVersion")), embedded in $app_id."
