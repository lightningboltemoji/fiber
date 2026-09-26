#!/usr/bin/env bash
# Launches the built browser against a dev profile kept in chromium/dev-profile.
# Usage: [OUT=Default] scripts/run.sh [start-url] [extra Chromium switches...]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-Default}"

# --no-startup-window: Fiber opens its own window; skip Chrome's.
# --use-mock-keychain: avoid the macOS Keychain prompt on unsigned dev builds.
exec "$ROOT/chromium/src/out/$OUT/Fiber.app/Contents/MacOS/Fiber" \
  --user-data-dir="$ROOT/chromium/dev-profile" \
  --no-first-run \
  --no-default-browser-check \
  --no-startup-window \
  --use-mock-keychain \
  "$@"
