#!/usr/bin/env bash
# Configure (first run only) and build Fiber into chromium/src/out/<dir>.
# Usage: [JOBS=n] scripts/build_chromium.sh [out_dir_name] [target]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="out/${1:-Default}"
TARGET="${2:-chrome}"
# Below the 15-core default: heavy C++ (chrome/browser, blink, v8) peaks ~1 GB
# per compile, and 15 of those plus siso itself crowd 24 GB of RAM.
JOBS="${JOBS:-12}"
export PATH="$ROOT/depot_tools:$PATH"

# Hold off idle sleep until this script exits (lid-close still sleeps).
caffeinate -i -w $$ &

# ANGLE compiles Metal shaders; since Xcode 26 the Metal compiler is a separate download.
if ! xcrun metal --version >/dev/null 2>&1; then
  echo "error: Metal toolchain missing. Run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

cd "$ROOT/chromium/src"

# Fiber's own args (core/build/args.gni), then a fast-iteration dev config:
# release codegen (DCHECKs stay on by default in non-official builds), many
# small dylibs for quick incremental links, and no debug symbols. Edit
# $OUT/args.gn afterwards and re-run to change the local part.
if [[ ! -f "$OUT/args.gn" ]]; then
  gn gen "$OUT" --args='
    import("//fiber/build/args.gni")
    is_debug = false
    is_component_build = true
    symbol_level = 0
    blink_symbol_level = 0
    v8_symbol_level = 0
  '
fi

# Each Blink generate_bindings action spawns a cpu_count() multiprocessing pool
# (~230 MB per worker) and all 11 become ready at once; at full -j that's 20+ GB
# and it panicked the machine. Run them two at a time first (no-op when current).
autoninja -C "$OUT" -j 2 third_party/blink/renderer/bindings:generate_bindings_all

autoninja -C "$OUT" -j "$JOBS" "$TARGET"
