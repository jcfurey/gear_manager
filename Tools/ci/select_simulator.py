#!/usr/bin/env python3
"""Picks an available iOS simulator for CI and prints its UDID.

Usage: select_simulator.py [iPhone|iPad]

Chooses from the newest installed iOS runtime, preferring a mainstream model (the base "iPhone N"
with the highest N; an 11-inch iPad Pro or Air), and refers to it by UDID. Names alone are
ambiguous when a device type exists under several runtimes, which is how "name=iPhone 17"
destinations end up on an unexpected OS.

Set SIMULATOR_NAME to force a device by exact name, or to several comma-separated names in order
of preference (the first one available wins, on the newest runtime that has it). Writes udid, name
and runtime to $GITHUB_OUTPUT when that is set.
"""

import json
import os
import re
import subprocess
import sys


def runtime_version(identifier):
    match = re.search(r"SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?$", identifier)
    if not match:
        return None
    return tuple(int(part or 0) for part in match.groups())


def model_rank(family, name):
    if family == "iPhone":
        number = re.match(r"iPhone (\d+)", name)
        is_base = re.fullmatch(r"iPhone \d+", name) is not None
        return (int(number.group(1)) if number else 0, is_base, -len(name))
    preferences = ["iPad Pro 11-inch", "iPad Air 11-inch", "iPad Pro", "iPad Air", "iPad ("]
    for rank, prefix in enumerate(preferences):
        if name.startswith(prefix):
            return (len(preferences) - rank, -len(name))
    return (0, -len(name))


def main():
    family = sys.argv[1] if len(sys.argv) > 1 else "iPhone"
    if family not in ("iPhone", "iPad"):
        sys.exit(f"Unknown device family {family!r}; use iPhone or iPad.")
    forced_names = [name.strip() for name in os.environ.get("SIMULATOR_NAME", "").split(",") if name.strip()]

    listing = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"]))
    candidates = []
    for runtime, devices in listing["devices"].items():
        version = runtime_version(runtime)
        if version is None:
            continue
        for device in devices:
            if not device.get("isAvailable", True) or not device["name"].startswith(family):
                continue
            if forced_names and device["name"] not in forced_names:
                continue
            # A forced name ranks by its place in the list; otherwise the usual model preference.
            rank = (-forced_names.index(device["name"]),) if forced_names else model_rank(family, device["name"])
            candidates.append((version, rank, device, runtime))

    if not candidates:
        print(f"::error title=No simulator::No available {', '.join(forced_names) or family} simulator.")
        subprocess.call(["xcrun", "simctl", "list", "devices", "available"])
        sys.exit(1)

    # A forced list prefers its earlier names over a newer runtime; otherwise the newest runtime wins.
    key = (lambda c: (c[1], c[0])) if forced_names else (lambda c: (c[0], c[1]))
    version, _, device, runtime = max(candidates, key=key)
    major, minor, patch = version
    runtime_name = f"iOS {major}.{minor}" + (f".{patch}" if patch else "")
    print(f"Selected {device['name']} ({runtime_name}) {device['udid']}")

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"udid={device['udid']}\n")
            handle.write(f"name={device['name']}\n")
            handle.write(f"runtime={runtime_name}\n")


if __name__ == "__main__":
    main()
