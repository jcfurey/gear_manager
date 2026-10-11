#!/usr/bin/env python3
"""Turns an Xcode result bundle into a GitHub job summary and annotations.

Usage:
  summarize_xcresult.py build <path.xcresult> <title>
  summarize_xcresult.py test  <path.xcresult> <title>

build: lists compiler errors and warnings, and annotates them on the changed files.
test:  shows pass/fail/skip counts, each failure with its message, and per-target line coverage
       when the bundle has coverage.

It only reports. It always exits 0 so the xcodebuild step stays the one that decides whether the
job fails, and a missing or unreadable bundle (xcodebuild died before writing one) is noted in the
summary rather than hiding the real error.
"""

import json
import os
import subprocess
import sys
from urllib.parse import parse_qs, unquote, urlparse

WORKSPACE = os.environ.get("GITHUB_WORKSPACE", os.getcwd())


def run_json(args):
    try:
        output = subprocess.check_output(args, stderr=subprocess.PIPE)
    except (subprocess.CalledProcessError, FileNotFoundError) as error:
        stderr = getattr(error, "stderr", b"") or b""
        print(f"Could not run {' '.join(args)}: {stderr.decode(errors='replace').strip() or error}")
        return None
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        return None


def escape_annotation(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def escape_property(text):
    return escape_annotation(text).replace(":", "%3A").replace(",", "%2C")


def location(source_url):
    """(repo-relative path, 1-based line) from an xcresult sourceURL, or (None, None)."""
    if not source_url:
        return None, None
    parsed = urlparse(source_url)
    path = unquote(parsed.path)
    if path.startswith(WORKSPACE.rstrip("/") + "/"):
        path = path[len(WORKSPACE.rstrip("/")) + 1:]
    fragment = parse_qs(parsed.fragment)
    line = fragment.get("StartingLineNumber", [None])[0]
    # xcresult line numbers are zero-based.
    return path, (int(line) + 1 if line is not None and line.isdigit() else None)


def annotate(level, message, source_url=None, title=None):
    path, line = location(source_url)
    properties = []
    if path:
        properties.append(f"file={escape_property(path)}")
    if line:
        properties.append(f"line={line}")
    if title:
        properties.append(f"title={escape_property(title)}")
    print(f"::{level} {','.join(properties)}::{escape_annotation(message)}")


def write_summary(lines):
    text = "\n".join(lines) + "\n"
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(text)
    else:
        print(text)


def summarize_build(bundle, title):
    results = run_json(["xcrun", "xcresulttool", "get", "build-results", "--path", bundle])
    if results is None:
        write_summary([f"### {title}", "", "No build results in the result bundle; see the step log."])
        return
    errors = results.get("errors", [])
    warnings = results.get("warnings", []) + results.get("analyzerWarnings", [])
    lines = [f"### {title}", "", f"**{len(errors)}** errors · **{len(warnings)}** warnings", ""]
    for level, issues in (("error", errors), ("warning", warnings)):
        for issue in issues:
            message = issue.get("message", "").strip()
            path, line = location(issue.get("sourceURL"))
            where = f"`{path}:{line}` " if path and line else (f"`{path}` " if path else "")
            lines.append(f"- {level}: {where}{message}")
            annotate(level, message, issue.get("sourceURL"), issue.get("issueType"))
    write_summary(lines)


def summarize_tests(bundle, title):
    summary = run_json(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", bundle])
    if summary is None:
        write_summary([f"### {title}", "", "No test results in the result bundle; see the step log."])
        return
    passed = summary.get("passedTests", 0)
    failed = summary.get("failedTests", 0)
    skipped = summary.get("skippedTests", 0)
    total = summary.get("totalTestCount", passed + failed + skipped)
    outcome = summary.get("result", "Unknown")
    icon = "✅" if outcome == "Passed" else "❌"
    lines = [f"### {icon} {title}", "",
             f"**{total}** tests · {passed} passed · {failed} failed · {skipped} skipped", ""]

    failures = summary.get("testFailures", [])
    if failures:
        lines += ["| Test | Failure |", "|---|---|"]
        for failure in failures:
            name = failure.get("testIdentifierString") or failure.get("testName", "?")
            text = failure.get("failureText", "").strip()
            cell = text.replace("|", "\\|").replace("\n", "<br>")
            lines.append(f"| `{name}` | {cell} |")
            annotate("error", text, title=f"{failure.get('targetName', '')} {name}".strip())
        lines.append("")

    coverage = run_json(["xcrun", "xccov", "view", "--report", "--only-targets", "--json", bundle])
    targets = coverage if isinstance(coverage, list) else (coverage or {}).get("targets", [])
    if targets:
        lines += ["| Target | Line coverage |", "|---|---|"]
        for target in targets:
            executable = target.get("executableLines", 0)
            covered = target.get("coveredLines", 0)
            lines.append(f"| {target.get('name', '?')} | {target.get('lineCoverage', 0):.1%} "
                         f"({covered}/{executable} lines) |")
    write_summary(lines)


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ("build", "test"):
        sys.exit(__doc__)
    mode, bundle, title = sys.argv[1:]
    if not os.path.exists(bundle):
        write_summary([f"### {title}", "", f"No result bundle at `{bundle}`; see the step log."])
        return
    (summarize_build if mode == "build" else summarize_tests)(bundle, title)


if __name__ == "__main__":
    main()
