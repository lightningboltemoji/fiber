#!/usr/bin/env bash
# Brings chromium/src in line with patches/chromium/, and links core/ into the
# tree as //fiber. build_chromium.sh runs it before every build, so it's quick
# and never touches a file whose patch hasn't changed (that would rebuild it).
#
# Local edits not yet saved with update_patches.sh are never overwritten.
# .git/fiber-patches records each file's patch and contents when the two last
# matched: a file edited since is kept (or, if its patch changed too, stops
# this), and an unedited one whose patch changed is reset and re-patched.
#
# Usage: scripts/apply_patches.sh [--revert | --record]
#   --revert  reset the patched files instead (sync_chromium.sh does this first).
#   --record  record chromium/src as matching the patches (update_patches.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/chromium/src"
STAMP="$SRC/.git/fiber-patches"
MODE="${1:-apply}"

# Repositories nested in chromium/src (DEPS checkouts) that Fiber patches files
# in; update_patches.sh has the same list. A file's patch names its path from
# chromium/src, and git apply there reaches into them.
NESTED=(third_party/ffmpeg)

fail() { echo "error: $*" >&2; exit 1; }
# The repository `file` is in, and its path there.
repo_of() {
  local r
  for r in ${NESTED[@]+"${NESTED[@]}"}; do
    [[ "$1" == "$r/"* ]] && { echo "$SRC/$r ${1#"$r/"}"; return; }
  done
  echo "$SRC $1"
}
contents() { git -C "$SRC" hash-object -- "$1"; }
pristine() { local repo path; read -r repo path <<< "$(repo_of "$1")"; git -C "$repo" diff --quiet -- "$path"; }
reset() { local repo path; read -r repo path <<< "$(repo_of "$1")"; git -C "$repo" checkout -- "$path"; }
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
      "since. Discard them (git checkout -- the file, in its repository) and" \
      "re-run, or merge the patch into them by hand and run make patches."
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
