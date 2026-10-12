#!/usr/bin/env python3
"""Copy the named App Store captures out of an xcresult attachment export, checking each one.

Usage: export-screenshots.py ATTACHMENTS DESTINATION --device iphone-6.9|ipad-13

ATTACHMENTS is the folder `xcrun xcresulttool export attachments` wrote. Each capture must exist
exactly once, be a native-size 8-bit RGB PNG with no alpha, and is copied unchanged; a manifest
records sizes and SHA-256 hashes. See marketing/README.md.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct

NAMES = (
    "01-inventory", "02-gear-detail", "03-shoots", "04-shoot-detail",
    "05-sun-and-moon", "06-tools", "07-light-meter", "08-film-rolls",
)
SIZES = {"iphone-6.9": (1320, 2868), "ipad-13": (2064, 2752)}
TEST = "ReleaseScreenshotTests/testCaptureReleaseScreenshots()"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("attachments", type=Path, help="xcresulttool attachment export folder")
    parser.add_argument("destination", type=Path)
    parser.add_argument("--device", choices=SIZES, required=True)
    args = parser.parse_args()

    manifest = json.loads((args.attachments / "manifest.json").read_text())
    selected = {}
    for test in manifest:
        if test.get("testIdentifier") != TEST:
            continue
        for attachment in test.get("attachments", []):
            for name in NAMES:
                if attachment["suggestedHumanReadableName"].startswith(name + "_"):
                    if name in selected:
                        raise SystemExit(f"Multiple captures for {name}; export a single successful run")
                    selected[name] = attachment
    missing = sorted(set(NAMES) - set(selected))
    if missing:
        raise SystemExit(f"Missing captures: {missing}")

    verified = []
    for name in NAMES:
        attachment = selected[name]
        source = args.attachments / attachment["exportedFileName"]
        data = source.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise SystemExit(f"Not a PNG: {source}")
        width, height, depth, color = struct.unpack(">IIBB", data[16:26])
        if (width, height) != SIZES[args.device] or depth != 8 or color != 2:
            raise SystemExit(f"{name}: expected a native {SIZES[args.device]} 8-bit RGB PNG without alpha, "
                             f"got {(width, height)}, depth {depth}, colour type {color}")
        offset = 8
        while offset + 12 <= len(data):
            length = struct.unpack(">I", data[offset:offset + 4])[0]
            if data[offset + 4:offset + 8] == b"tRNS":
                raise SystemExit(f"{name}: unexpected transparency")
            offset += length + 12
        verified.append((source, {
            "file": name + ".png", "width": width, "height": height,
            "sha256": hashlib.sha256(data).hexdigest(),
            "device": attachment.get("deviceName", ""), "capturedAt": attachment.get("timestamp", ""),
        }))

    args.destination.mkdir(parents=True, exist_ok=True)
    for source, record in verified:
        shutil.copyfile(source, args.destination / record["file"])
    (args.destination / "capture-manifest.json").write_text(
        json.dumps([record for _, record in verified], indent=2) + "\n")
    print(f"Exported {len(verified)} verified {args.device} screenshots to {args.destination}")


if __name__ == "__main__":
    main()
