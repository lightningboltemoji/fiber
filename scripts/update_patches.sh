#!/usr/bin/env bash
# Regenerates patches/chromium/ from the edits in chromium/src: one patch per
# modified Chromium file, named after its path. New code belongs in core/
# (which is //fiber), not in new files inside the Chromium tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/chromium/src"
OUT="$ROOT/patches/chromium"

mkdir -p "$OUT"
rm -f "$OUT"/*.patch
git -C "$SRC" diff --name-only | while read -r file; do
  name="${file//\//-}.patch"
  git -C "$SRC" diff --no-color -- "$file" > "$OUT/$name"
  echo "wrote $name"
done

# Record that chromium/src and the patches now match.
"$ROOT/scripts/apply_patches.sh" --record
