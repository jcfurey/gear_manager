#!/usr/bin/env python3
"""Checks the project rules a compiler can't: CloudKit-safe models, the model registry, logging,
project settings that must agree across targets, and leftovers from the Axe Manager port.

Usage: python3 Tools/ci/check_conventions.py

Runs on any machine with Python 3.9+ (no Xcode needed), so it is CI's first, fast job and can be
run locally before pushing. Each problem prints as a GitHub annotation and a plain line; the exit
status is 1 when there are any.

To accept one flagged line on purpose, end it with `// conventions:allow <check-name>`.
"""

import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "ShutterManager"
TEST_DIRS = [ROOT / "ShutterManagerTests", ROOT / "ShutterManagerUITests"]
PROJECT = ROOT / "ShutterManager.xcodeproj" / "project.pbxproj"
ENTITLEMENTS = APP / "ShutterManager.entitlements"
INFO_PLIST = ROOT / "Info.plist"
APP_SCHEMA = APP / "Utilities" / "AppSchema.swift"

BUNDLE_ID = "jcameronfurey.shuttermanager"
CLOUDKIT_CONTAINER = "iCloud.jcameronfurey.shuttermanager"
EXPECTED_BUNDLE_IDS = {BUNDLE_ID, f"{BUNDLE_ID}.tests", f"{BUNDLE_ID}.uitests"}

problems = []


def report(check, path, line, message):
    relative = path.relative_to(ROOT) if path.is_absolute() else path
    problems.append((check, relative, line, message))


def allowed(text, check):
    return f"conventions:allow {check}" in text


def swift_files(*directories):
    for directory in directories:
        if directory.exists():
            yield from sorted(directory.rglob("*.swift"))


def code_only(line):
    """The line with string literals emptied and any // comment removed."""
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    return line.split("//", 1)[0]


# MARK: - Logging


def check_logging():
    """App code logs through os.Logger; print/NSLog output is lost on device and unfiltered."""
    pattern = re.compile(r"(?<![\w.])(print|debugPrint|NSLog|dump)\(")
    for path in swift_files(APP):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if pattern.search(code_only(line)) and not allowed(line, "logging"):
                report("logging", path, number, "Use os.Logger, not print/debugPrint/NSLog/dump.")


# MARK: - Leftovers from the Axe Manager port


def check_port_leftovers():
    pattern = re.compile(r"guitar|axemanager|Axe Manager|theweegee|\btuner\b|fretboard", re.IGNORECASE)
    for path in swift_files(APP, *TEST_DIRS):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if pattern.search(line) and not allowed(line, "leftovers"):
                report("leftovers", path, number, f"Axe Manager leftover: {line.strip()[:100]}")


# MARK: - SwiftData / CloudKit model rules


def model_classes():
    """{name: (path, line number of the class line, body lines with their numbers)} for every @Model."""
    models = {}
    for path in swift_files(APP):
        lines = path.read_text().splitlines()
        index = 0
        while index < len(lines):
            if code_only(lines[index]).strip().startswith("@Model"):
                # The class declaration is on this line or one of the next few.
                for offset in range(0, 4):
                    if index + offset >= len(lines):
                        break
                    match = re.search(r"\bclass\s+(\w+)", code_only(lines[index + offset]))
                    if match:
                        start = index + offset
                        models[match.group(1)] = (path, start + 1, class_body(lines, start))
                        index = start
                        break
            index += 1
    return models


def class_body(lines, start):
    """[(line number, text)] of the lines directly inside the class (brace depth 1)."""
    depth = 0
    body = []
    opened = False
    for number in range(start, len(lines)):
        code = code_only(lines[number])
        depth_before = depth
        depth += code.count("{") - code.count("}")
        if not opened and "{" in code:
            opened = True
            continue
        if opened and depth_before == 1:
            body.append((number + 1, lines[number]))
        if opened and depth <= 0:
            break
    return body


PROPERTY = re.compile(
    r"^\s*(?P<attrs>(?:@\w+(?:\([^)]*\))?\s+)*)"
    r"(?:(?:private|fileprivate|internal|public)(?:\(set\))?\s+)*"
    r"(?P<static>static\s+)?var\s+(?P<name>\w+)\s*:\s*(?P<type>[^={]+?)\s*(?P<default>=[^{]*)?(?P<brace>\{.*)?$")


def check_models():
    models = model_classes()
    names = set(models)
    for name, (path, class_line, body) in models.items():
        pending_attributes = ""
        for number, line in body:
            code = code_only(line)
            stripped = code.strip()
            if stripped.startswith("@") and " var " not in f" {stripped} ":
                pending_attributes += stripped + " "
                continue
            match = PROPERTY.match(code)
            attributes = pending_attributes + (match.group("attrs") if match else "")
            pending_attributes = ""
            if not match or match.group("static"):
                continue
            if "@Transient" in attributes:
                continue
            type_text = match.group("type").strip()
            has_default = match.group("default") is not None
            if match.group("brace") and not has_default:
                continue  # computed property
            optional = type_text.endswith("?")
            element = re.sub(r"[\[\]?!]", "", type_text).strip()
            if element in names:
                if not optional and not allowed(line, "models"):
                    report("models", path, number,
                           f"{name}.{match.group('name')}: CloudKit needs relationships to be optional ({type_text}?).")
            elif not has_default and not optional and not allowed(line, "models"):
                report("models", path, number,
                       f"{name}.{match.group('name')}: CloudKit needs a default for every non-optional attribute.")

    for path in swift_files(APP):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = code_only(line)
            if (".unique" in code or "#Unique" in code) and not allowed(line, "models"):
                report("models", path, number, "CloudKit doesn't support unique constraints.")
            if re.search(r"deleteRule:\s*\.deny", code) and not allowed(line, "models"):
                report("models", path, number, "CloudKit doesn't support the .deny delete rule.")

    check_registry(models)


def check_registry(models):
    """Every @Model is registered in AppSchema.models, and nothing else is."""
    if not models and not APP_SCHEMA.exists():
        return
    if not APP_SCHEMA.exists():
        report("registry", APP_SCHEMA, 1, "AppSchema.swift is missing but the app has @Model types.")
        return
    text = APP_SCHEMA.read_text()
    block = re.search(r"static let models[^=]*=\s*\[(.*?)\]", text, re.DOTALL)
    if not block:
        report("registry", APP_SCHEMA, 1, "Could not find `static let models = [...]` in AppSchema.")
        return
    registered = set(re.findall(r"(\w+)\.self", block.group(1)))
    for name in sorted(set(models) - registered):
        path, line, _ = models[name]
        report("registry", path, line, f"@Model {name} is not listed in AppSchema.models.")
    for name in sorted(registered - set(models)):
        report("registry", APP_SCHEMA, 1, f"AppSchema.models lists {name}, which is not an @Model.")


def check_in_memory_containers():
    """In-memory containers (tests, previews) must not try to mirror to CloudKit."""
    for path in swift_files(APP, *TEST_DIRS):
        lines = path.read_text().splitlines()
        for number, line in enumerate(lines, 1):
            if "isStoredInMemoryOnly: true" not in code_only(line):
                continue
            window = " ".join(code_only(text) for text in lines[max(0, number - 4):number + 3])
            if "cloudKitDatabase: .none" not in window and not allowed(line, "in-memory"):
                report("in-memory", path, number, "In-memory ModelConfiguration needs cloudKitDatabase: .none.")


# MARK: - Capabilities and project settings


def load_plist(path, check):
    try:
        with path.open("rb") as handle:
            return plistlib.load(handle)
    except FileNotFoundError:
        report(check, path, 1, "File is missing.")
    except Exception as error:  # noqa: BLE001 - any parse failure is the finding
        report(check, path, 1, f"Not a valid property list: {error}")
    return None


def check_capabilities():
    entitlements = load_plist(ENTITLEMENTS, "capabilities")
    if entitlements is not None:
        containers = entitlements.get("com.apple.developer.icloud-container-identifiers", [])
        if containers != [CLOUDKIT_CONTAINER]:
            report("capabilities", ENTITLEMENTS, 1, f"iCloud containers should be [{CLOUDKIT_CONTAINER}], found {containers}.")
        if "com.apple.developer.default-data-protection" in entitlements:
            report("capabilities", ENTITLEMENTS, 1,
                   "Don't set default-data-protection: the iOS default already applies and the entitlement breaks archiving.")
    info = load_plist(INFO_PLIST, "capabilities")
    if info is not None and "remote-notification" not in info.get("UIBackgroundModes", []):
        report("capabilities", INFO_PLIST, 1, "CloudKit sync needs UIBackgroundModes → remote-notification.")

    # Swift code that names a container must name the one in the entitlements.
    for path in swift_files(APP):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            for container in re.findall(r'"(iCloud\.[\w.]+)"', line):
                if container != CLOUDKIT_CONTAINER:
                    report("capabilities", path, number, f"Container {container} doesn't match the entitlements.")


def check_project_settings():
    if not PROJECT.exists():
        report("project", PROJECT, 1, "Project file is missing.")
        return
    text = PROJECT.read_text()
    for setting in ("IPHONEOS_DEPLOYMENT_TARGET", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION", "SWIFT_VERSION"):
        values = set(re.findall(rf"\b{setting} = ([^;]+);", text))
        if len(values) > 1:
            report("project", PROJECT, 1, f"{setting} differs between configurations: {sorted(values)}.")
    bundle_ids = set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", text))
    if bundle_ids != EXPECTED_BUNDLE_IDS:
        report("project", PROJECT, 1, f"Bundle IDs should be {sorted(EXPECTED_BUNDLE_IDS)}, found {sorted(bundle_ids)}.")
    if re.search(r"isa = PBXFileReference;[^}]*path = [^;]*\.swift;", text):
        report("project", PROJECT, 1,
               "Swift files are referenced individually; the targets use folder-synced groups, so add files on disk instead.")
    for path in sorted(APP.rglob("Contents.json")):
        try:
            json.loads(path.read_text())
        except json.JSONDecodeError as error:
            report("project", path, 1, f"Invalid JSON: {error}")


# MARK: - Main


def main():
    check_logging()
    check_port_leftovers()
    check_models()
    check_in_memory_containers()
    check_capabilities()
    check_project_settings()

    for check, path, line, message in problems:
        print(f"::error file={path},line={line},title=conventions/{check}::{message}")
    for check, path, line, message in problems:
        print(f"{path}:{line}: [{check}] {message}")
    if problems:
        print(f"\n{len(problems)} convention problem(s).")
        return 1
    print("All convention checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
