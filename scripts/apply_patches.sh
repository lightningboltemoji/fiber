#!/usr/bin/env bash
# Applies patches/chromium/*.patch to chromium/src and links core/ into the tree
# as //fiber. Already-applied patches are skipped, so it's safe to re-run.
# Usage: scripts/apply_patches.sh [--revert]
#   --revert  un-apply the patches instead (sync_chromium.sh does this first).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/chromium/src"
REVERT=0
[[ "${1:-}" == "--revert" ]] && REVERT=1

shopt -s nullglob
for patch in "$ROOT"/patches/chromium/*.patch; do
  name="$(basename "$patch")"
  if git -C "$SRC" apply --reverse --check "$patch" 2>/dev/null; then
    if (( REVERT )); then
      git -C "$SRC" apply --reverse "$patch"
      echo "reverted $name"
    fi
  elif (( ! REVERT )); then
    git -C "$SRC" apply "$patch"
    echo "applied $name"
  fi
done

if (( ! REVERT )); then
  ln -sfn ../../core "$SRC/fiber"
  grep -qx '/fiber' "$SRC/.git/info/exclude" || echo '/fiber' >> "$SRC/.git/info/exclude"
fi
