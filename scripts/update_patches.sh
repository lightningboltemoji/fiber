#!/usr/bin/env bash
# Regenerates patches/chromium/ from the edits in chromium/src: one patch per
# modified Chromium file, named after its path. New code belongs in core/
# (which is //fiber), not in new files inside the Chromium tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/chromium/src"
OUT="$ROOT/patches/chromium"

# Repositories nested in chromium/src that Fiber patches files in (see
# apply_patches.sh). Their patches name paths from chromium/src too.
NESTED=(third_party/ffmpeg third_party/devtools-frontend/src)

# A rebase's conflict markers (rebase_patches.sh) would be saved with the rest.
left="$(for repo in . ${NESTED[@]+"${NESTED[@]}"}; do
  git -C "$SRC/$repo" diff --name-only -G'^(<<<<<<<|>>>>>>>)( |$)' |
    sed "s|^|${repo#.}/|; s|^/||"
done)"
if [[ -n "$left" ]]; then
  echo "error: resolve the conflicts in these first:" >&2
  sed 's/^/  /' <<< "$left" >&2
  exit 1
fi

mkdir -p "$OUT"
rm -f "$OUT"/*.patch
for repo in . ${NESTED[@]+"${NESTED[@]}"}; do
  prefix="${repo#.}"
  prefix="${prefix:+$prefix/}"
  git -C "$SRC/$repo" diff --name-only | while read -r file; do
    name="${prefix//\//-}${file//\//-}.patch"
    git -C "$SRC/$repo" diff --no-color --src-prefix="a/$prefix" \
      --dst-prefix="b/$prefix" -- "$file" > "$OUT/$name"
    echo "wrote $name"
  done
done

# Record that chromium/src and the patches now match.
"$ROOT/scripts/apply_patches.sh" --record
rm -f "$SRC/.git/fiber-rebase"
