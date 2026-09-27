#!/usr/bin/env bash
# Brings chromium/src in line with patches/chromium/, and links core/ into the
# tree as //fiber. Each patched file ends up as Chromium's version plus its
# patch. build_chromium.sh runs this before every build, so a pull that changes
# the patches takes effect on its own; checking all of them takes a fraction of
# a second, and a file whose patch hasn't changed isn't touched (nor rebuilt).
#
# Local edits (made in chromium/src and not yet saved to a patch with
# update_patches.sh) are never overwritten. chromium/src/.git/fiber-patches
# records, for each file, its patch and its contents the last time the two
# matched. That tells edits in progress (the patch hasn't changed since: keep
# them) from a stale file (it's as the old patch left it: reset it and apply the
# new one). A file with edits whose patch also changed is a conflict, and this
# stops.
#
# Usage: scripts/apply_patches.sh [--revert | --record]
#   --revert  reset the patched files instead (sync_chromium.sh does this first).
#   --record  record chromium/src as matching the patches (update_patches.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/chromium/src"
STAMP="$SRC/.git/fiber-patches"
MODE="${1:-apply}"

fail() { echo "error: $*" >&2; exit 1; }
contents() { git -C "$SRC" hash-object -- "$1"; }
pristine() { git -C "$SRC" diff --quiet -- "$1"; }
reset() { git -C "$SRC" checkout -- "$1"; }
# "<patch hash> <contents>" as of the last time the file matched its patch.
synced() { [[ -f "$STAMP" ]] && awk -v f="$1" '$3 == f { print $1, $2 }' "$STAMP" || true; }

next_stamp="$(mktemp)"
trap 'rm -f "$next_stamp"' EXIT

shopt -s nullglob
patches=("$ROOT"/patches/chromium/*.patch)
files=()
for patch in ${patches[@]+"${patches[@]}"}; do
  file="$(sed -n '1s|^diff --git a/\(.*\) b/.*|\1|p' "$patch")"
  [[ -n "$file" ]] || fail "$(basename "$patch") isn't a diff of one file"
  files+=("$file")
done
# Hashed in two calls, not two per file: this runs before every build.
wants=() nows=()
if (( ${#patches[@]} )); then
  wants=($(git hash-object --no-filters -- "${patches[@]}"))
  nows=($(git -C "$SRC" hash-object -- "${files[@]}"))
fi

patched=" "
for i in ${patches[@]+"${!patches[@]}"}; do
  patch="${patches[$i]}" file="${files[$i]}" want="${wants[$i]}" now="${nows[$i]}"
  patched+="$file "
  last_patch="" last_contents=""
  read -r last_patch last_contents <<< "$(synced "$file")" || true

  case "$MODE" in
    --record)
      echo "$want $now $file" >> "$next_stamp"
      continue ;;
    --revert)
      # Without a record (a checkout from before them), trust that an applied
      # patch is all there is.
      if [[ "$now" == "$last_contents" ]] || { [[ -z "$last_contents" ]] &&
          git -C "$SRC" apply --reverse --check "$patch" 2>/dev/null; }; then
        reset "$file"
        echo "reverted $file"
      elif ! pristine "$file"; then
        fail "$file has edits that aren't in its patch; save them with" \
          "make patches or discard them, and re-run"
      fi
      continue ;;
  esac

  if [[ "$now" == "$last_contents" && "$want" == "$last_patch" ]]; then
    :
  elif pristine "$file"; then
    git -C "$SRC" apply "$patch"
    echo "applied $file"
  elif [[ "$now" == "$last_contents" ]]; then
    reset "$file"
    git -C "$SRC" apply "$patch"
    echo "updated $file"
  elif [[ -z "$last_contents" ]] &&
      git -C "$SRC" apply --reverse --check "$patch" 2>/dev/null; then
    : # A checkout from before the records, with the patch applied.
  elif [[ "$want" == "$last_patch" ]]; then
    echo "keeping edits to $file that aren't in its patch yet (make patches)"
    echo "$last_patch $last_contents $file" >> "$next_stamp"
    continue
  else
    fail "$file has edits that aren't in its patch, and the patch has changed" \
      "since. Discard them (git -C chromium/src checkout -- $file) and re-run," \
      "or merge the patch into them by hand and run make patches."
  fi
  echo "$want $(contents "$file") $file" >> "$next_stamp"
done

# Files whose patch is gone.
if [[ -f "$STAMP" && "$MODE" != --record ]]; then
  while read -r _ last_contents file; do
    [[ "$patched" == *" $file "* ]] && continue
    if [[ "$(contents "$file")" == "$last_contents" ]]; then
      reset "$file"
      echo "reverted $file (its patch is gone)"
    elif ! pristine "$file"; then
      echo "warning: keeping edits to $file, whose patch is gone" >&2
    fi
  done < "$STAMP"
fi

if [[ "$MODE" == --revert ]]; then
  rm -f "$STAMP"
else
  mv "$next_stamp" "$STAMP"
  ln -sfn ../../core "$SRC/fiber"
  grep -qx '/fiber' "$SRC/.git/info/exclude" || echo '/fiber' >> "$SRC/.git/info/exclude"
fi
