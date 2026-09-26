#!/usr/bin/env bash
# Fetch (or re-sync) the Chromium checkout in ./chromium at the tag pinned in
# CHROMIUM_VERSION, then apply Fiber's patches. History is shallow: only the
# pinned revision is downloaded.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/CHROMIUM_VERSION")"

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

# Un-apply our patches so the checkout can move cleanly.
if [[ -d src/.git ]]; then
  "$ROOT/scripts/apply_patches.sh" --revert
fi

echo "Syncing Chromium $VERSION"
# gclient shallow-fetches the tag and checks out FETCH_HEAD (detached HEAD).
gclient sync --nohooks --no-history -D --revision "src@refs/tags/$VERSION"
gclient runhooks

"$ROOT/scripts/apply_patches.sh"
