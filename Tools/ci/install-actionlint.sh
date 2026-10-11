#!/usr/bin/env bash
# Installs a pinned actionlint release into $RUNNER_TEMP (or ./.tools) after verifying its
# checksum, and prints the binary's path. Linux x86-64 only, which is what CI uses.
set -euo pipefail

version="1.7.12"
sha256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
archive="actionlint_${version}_linux_amd64.tar.gz"
destination="${RUNNER_TEMP:-$PWD/.tools}/actionlint-${version}"

mkdir -p "$destination"
curl --fail --silent --show-error --location --retry 3 \
  --output "$destination/$archive" \
  "https://github.com/rhysd/actionlint/releases/download/v${version}/${archive}"
echo "${sha256}  $destination/$archive" | sha256sum --check --quiet
tar -xzf "$destination/$archive" -C "$destination" actionlint
echo "$destination/actionlint"
