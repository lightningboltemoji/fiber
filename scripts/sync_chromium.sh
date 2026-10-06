#!/usr/bin/env bash
# Fetch (or re-sync) the Chromium checkout in ./chromium at the tag pinned in
# CHROMIUM_VERSION, then apply Fiber's patches, rebasing them onto it if they
# don't apply. History is shallow: only the pinned revision is downloaded.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/CHROMIUM_VERSION")"
# The release the patches were made against: CHROMIUM_VERSION as committed,
# since an upgrade commits the new one with the rebased patches.
FROM="$(git -C "$ROOT" show HEAD:CHROMIUM_VERSION 2>/dev/null | tr -d '[:space:]')" || true

if [[ ! -d "$ROOT/depot_tools" ]]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$ROOT/depot_tools"
fi
export PATH="$ROOT/depot_tools:$PATH"

mkdir -p "$ROOT/chromium"
cd "$ROOT/chromium"

# ~100GB of regenerable files; keep them out of Time Machine.
tmutil addexclusion "$ROOT/chromium" 2>/dev/null || true

if [[ ! -f .gclient ]]; then
  cat > .gclient <<'EOF'
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
EOF
fi

# Fetches, without history, what the dependencies checked out under <dir> are
# pinned to at <rev> and don't have, and then what those pin in turn.
fetch_deps() {
  local dir="$1" rev="$2" missing path sha
  missing="$(git -C "$dir" ls-tree -r "$rev" | awk '$2 == "commit" { print $4, $3 }' |
    while read -r path sha; do
      if [[ -e "$dir/$path/.git" ]] &&
          ! git -C "$dir/$path" cat-file -e "$sha^{commit}" 2>/dev/null; then
        echo "$dir/$path $sha"
      fi
    done)"
  [[ -n "$missing" ]] || return 0
  xargs -P 8 -n 2 sh -c 'echo "fetching $0" &&
    git -C "$0" fetch --quiet --depth 1 --no-tags origin "$1"' <<< "$missing"
  while read -r path sha; do fetch_deps "$path" "$sha"; done <<< "$missing"
}

echo "Syncing Chromium $VERSION"
revision="refs/tags/$VERSION"
if [[ -d src/.git ]]; then
  # Un-apply our patches so the checkout can move cleanly.
  "$ROOT/scripts/apply_patches.sh" --revert
  # gclient keeps a first checkout shallow (--no-history), but to update one
  # it fetches all of a repository's history for any revision that isn't a
  # commit it has. So everything it will check out is fetched first.
  git -C src cat-file -e "$revision^{commit}" 2>/dev/null ||
    git -C src fetch --quiet --depth 1 --no-tags origin "$revision:$revision"
  fetch_deps src "$revision"
  revision="$(git -C src rev-parse "$revision^{commit}")"
fi
gclient sync --nohooks --no-history -D --revision "src@$revision"
gclient runhooks

if git -C src apply --check "$ROOT"/patches/chromium/*.patch 2>/dev/null ||
    [[ -z "$FROM" || "$FROM" == "$VERSION" ]]; then
  "$ROOT/scripts/apply_patches.sh"
else
  "$ROOT/scripts/rebase_patches.sh" "$FROM" "$VERSION"
fi
