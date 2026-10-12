#!/usr/bin/env bash
# Selects the Xcode version pinned in .xcode-version (for example "26.6").
#
# CI builds with warnings treated as errors, so an unannounced Xcode upgrade on the runner image
# could turn new deprecation warnings into a red build that has nothing to do with the change
# under test. Pinning makes Xcode upgrades a deliberate one-line change to .xcode-version.
#
# Lookup order: /Applications/Xcode_<pin>.app, then the newest /Applications/Xcode_<pin>.*.app.
# If neither exists (the runner image dropped that version), it falls back to the newest Xcode
# with the same major version and emits a GitHub warning, so the build still runs but the drift
# is visible on the run page.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pin="$(tr -d '[:space:]' < "$repo_root/.xcode-version")"
major="${pin%%.*}"

newest_matching() {
  # Newest app bundle matching the glob prefix, by version sort.
  compgen -G "$1" | sort -V | tail -n 1 || true
}

xcode_app=""
if [[ -d "/Applications/Xcode_${pin}.app" ]]; then
  xcode_app="/Applications/Xcode_${pin}.app"
else
  xcode_app="$(newest_matching "/Applications/Xcode_${pin}.*.app")"
fi

if [[ -z "$xcode_app" ]]; then
  xcode_app="$(newest_matching "/Applications/Xcode_${major}.*.app")"
  if [[ -z "$xcode_app" ]]; then
    echo "::error title=Xcode not found::No Xcode ${pin} or ${major}.x on this runner. Installed:"
    ls -d /Applications/Xcode*.app || true
    exit 1
  fi
  echo "::warning title=Pinned Xcode missing::Xcode ${pin} is not on this runner; using ${xcode_app}. Update .xcode-version."
fi

sudo xcode-select --switch "$xcode_app/Contents/Developer"
echo "Selected $xcode_app"
xcodebuild -version
