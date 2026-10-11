#!/usr/bin/env bash
# Decides whether a push or pull request touches anything the macOS jobs build or test, and
# writes app=true|false to $GITHUB_OUTPUT.
#
# Docs-only changes (Markdown anywhere, docs/, marketing/) skip the macOS jobs. Any doubt (no base
# commit, a force-push, a manual run) counts as an app change, so the full build runs.
#
# Inputs (environment): EVENT, BASE_SHA (pull requests), BEFORE (pushes).
set -euo pipefail

zero_sha="0000000000000000000000000000000000000000"
base=""
case "${EVENT:-}" in
  pull_request)
    base="${BASE_SHA:-}"
    ;;
  push)
    base="${BEFORE:-}"
    if [[ -z "$base" || "$base" == "$zero_sha" ]]; then
      # A new branch: compare with where it left main.
      base="$(git merge-base origin/main HEAD 2>/dev/null || true)"
    fi
    ;;
esac

app=true
if [[ -n "$base" ]] && git cat-file -e "${base}^{commit}" 2>/dev/null; then
  changed="$(git diff --name-only "$base" HEAD)"
  echo "Changed since ${base:0:12}:"
  while IFS= read -r file; do echo "  $file"; done <<<"$changed"
  if [[ -n "$changed" ]] && ! grep -qvE '(\.md$|^docs/|^marketing/)' <<<"$changed"; then
    app=false
  fi
else
  echo "No usable base commit for event '${EVENT:-unknown}'; running everything."
fi

echo "app=$app"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "app=$app" >> "$GITHUB_OUTPUT"
fi
