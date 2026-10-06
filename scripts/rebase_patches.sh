#!/usr/bin/env bash
# Rebases patches/chromium/ onto another Chromium release, as git rebases a
# commit: in each repository, the patches applied to the release they were made
# against are merged with the new one. A patch follows its file where upstream
# moved it; where upstream changed the same lines, the file is left with
# conflict markers, the old release's lines between ||||||| and =======.
#
# Usage: scripts/rebase_patches.sh [--dry-run] <from> [<to>]
#        scripts/rebase_patches.sh --abort
#   <from> is the release the patches were made against; <to> defaults to
#   CHROMIUM_VERSION. sync_chromium.sh runs this when CHROMIUM_VERSION moves,
#   with chromium/src at <to>, and the merge is written there: if it's clean,
#   the patches are rewritten from it; if not, resolve what's listed and run
#   make patches.
#   --dry-run  only report, leaving chromium/src as it is (fetches <to>).
#   --abort    discard what a rebase wrote, resolutions included.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/chromium/src"
# Lists the files a rebase wrote, until make patches saves them or --abort
# discards them. apply_patches.sh won't touch the tree while it's there.
REBASE="$SRC/.git/fiber-rebase"

# Repositories nested in chromium/src that Fiber patches files in; the same
# list as apply_patches.sh.
NESTED=(third_party/ffmpeg third_party/devtools-frontend/src)

fail() { echo "error: $*" >&2; exit 1; }

if [[ "${1:-}" == --abort ]]; then
  [[ -f "$REBASE" ]] || fail "no rebase in progress"
  tail -n +2 "$REBASE" | while IFS=$'\t' read -r repo file; do
    git -C "$SRC/$repo" checkout -- "$file"
  done
  rm "$REBASE"
  echo "discarded the rebase: the files it wrote are Chromium's again"
  exit
fi

DRY_RUN=false
if [[ "${1:-}" == --dry-run ]]; then DRY_RUN=true; shift; fi
(( $# >= 1 )) || fail "usage: rebase_patches.sh [--dry-run] <from> [<to>] | --abort"
FROM="$1"
TO="${2:-$(tr -d '[:space:]' < "$ROOT/CHROMIUM_VERSION")}"
if ! $DRY_RUN && [[ -f "$REBASE" ]]; then
  fail "a rebase is already in progress: finish it with make patches, or" \
    "discard it with scripts/rebase_patches.sh --abort"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fetches a commit, by tag or hash, without its history.
have() {
  git -C "$1" cat-file -e "$2^{commit}" 2>/dev/null && return
  local ref="refs/tags/$2:refs/tags/$2"
  [[ "$2" =~ ^[0-9a-f]{40}$ ]] && ref="$2"
  git -C "$1" fetch --quiet --depth 1 --no-tags origin "$ref"
}
repo_of() {
  local r
  for r in "${NESTED[@]}"; do [[ "$1" == "$r/"* ]] && { echo "$r"; return; }; done
  echo .
}
lines() { [[ -z "$2" ]] || { echo "$1"; sed 's/^/  /' <<< "${2%$'\n'}"; }; }

have "$SRC" "$FROM"
have "$SRC" "$TO"
if ! $DRY_RUN; then
  [[ "$(git -C "$SRC" rev-parse HEAD)" == "$(git -C "$SRC" rev-parse "$TO^{commit}")" ]] ||
    fail "chromium/src isn't at $TO; run make sync"
  echo "$FROM $TO" > "$REBASE"
fi

echo "Rebasing patches/chromium/ from $FROM onto $TO"
conflicts="" deleted="" moved="" landed="" upstream=""
for repo in . "${NESTED[@]}"; do
  patches=()
  for patch in "$ROOT"/patches/chromium/*.patch; do
    file="$(sed -n '1s|^diff --git a/\(.*\) b/.*|\1|p' "$patch")"
    [[ "$(repo_of "$file")" == "$repo" ]] && patches+=("$patch")
  done
  (( ${#patches[@]} )) || continue

  dir="$SRC/$repo" prefix="" base="$FROM" theirs="$TO"
  if [[ "$repo" != . ]]; then
    prefix="$repo/"
    base="$(git -C "$SRC" rev-parse "$FROM:$repo")"
    theirs="$(git -C "$SRC" rev-parse "$TO:$repo")"
    have "$dir" "$base"
    have "$dir" "$theirs"
  fi

  # The patches as a tree on the release they were made against. Their paths
  # start from chromium/src, so a nested repository strips its own.
  export GIT_INDEX_FILE="$tmp/index"
  rm -f "$GIT_INDEX_FILE"
  git -C "$dir" read-tree "$base"
  git -C "$dir" apply --cached -p"$(( $(tr -cd / <<< "/$prefix" | wc -c) ))" \
    "${patches[@]}" || fail "the patches don't apply to $FROM; is that the" \
    "release they were made against?"
  fiber="$(git -C "$dir" write-tree)"
  unset GIT_INDEX_FILE

  status=0
  git -C "$dir" -c merge.conflictStyle=zdiff3 merge-tree --write-tree \
    --name-only --no-messages --merge-base="$base" "$theirs" "$fiber" \
    > "$tmp/merge" || status=$?
  (( status <= 1 )) || fail "git merge-tree failed in $repo"
  merged="$(head -1 "$tmp/merge")"

  # Where a patched file was deleted upstream, or moved and rewritten, there's
  # no file to merge into; the merge keeps Fiber's, which isn't written.
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if git -C "$dir" cat-file -e "$theirs:$file" 2>/dev/null; then
      conflicts+="$prefix$file"$'\n'
    else
      deleted+="$prefix$file"$'\n'
    fi
  done < <(tail -n +2 "$tmp/merge")

  before="$(git -C "$dir" diff --no-renames --name-only "$base" "$fiber")"
  after="$(git -C "$dir" diff --no-renames --name-only --diff-filter=M "$theirs" "$merged")"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    grep -qxF "$file" <<< "$after" && continue
    if git -C "$dir" cat-file -e "$theirs:$file" 2>/dev/null; then
      upstream+="$prefix$file"$'\n'
    elif ! grep -qxF "$prefix$file" <<< "$deleted"; then
      moved+="$prefix$file"$'\n'
    fi
  done <<< "$before"
  while IFS= read -r file; do
    [[ -n "$file" ]] && ! grep -qxF "$file" <<< "$before" && landed+="$prefix$file"$'\n'
  done <<< "$after"
  echo "  ${repo/#./chromium/src}: $(grep -c . <<< "$after") patched files"

  $DRY_RUN && continue
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$(git -C "$dir" rev-parse "$theirs^{commit}")" ]] ||
    fail "$repo isn't at $TO's revision of it; run make sync"
  [[ -z "$after" ]] || git -C "$dir" diff --quiet -- $after ||
    fail "$repo has edits to files the patches change; run make sync"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if grep -qxF "$prefix$file" <<< "$conflicts"; then
      git -C "$dir" cat-file blob "$merged:$file" | sed \
        -e "s/^<<<<<<< $theirs\$/<<<<<<< $TO/" \
        -e "s/^||||||| $base\$/||||||| $FROM/" \
        -e "s/^>>>>>>> $fiber\$/>>>>>>> Fiber/" > "$dir/$file"
    else
      git -C "$dir" cat-file blob "$merged:$file" > "$dir/$file"
    fi
    printf '%s\t%s\n' "$repo" "$file" >> "$REBASE"
  done <<< "$after"
done

lines "Conflicts, to resolve in chromium/src ($TO's lines, then $FROM's, then Fiber's):" "$conflicts"
lines "Deleted upstream, or moved and rewritten: port the patch to where its code went:" "$deleted"
lines "Moved upstream, their patches with them:" "$moved"
lines "Patched now, in their place:" "$landed"
lines "Already upstream, so their patches go:" "$upstream"

if [[ -n "$conflicts$deleted" ]]; then
  $DRY_RUN || echo "Then run make patches, or start over with scripts/rebase_patches.sh --abort."
  exit 1
fi
$DRY_RUN && exit
"$ROOT/scripts/update_patches.sh" > /dev/null
echo "Rebased: review git diff patches/"
