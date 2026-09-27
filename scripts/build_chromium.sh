#!/usr/bin/env bash
# Configure (first run only) and build Fiber into chromium/src/out/<dir>.
# Usage: [JOBS=n] scripts/build_chromium.sh [out_dir_name] [target]
#   out/Release is the self-contained build `make app` packages; any other out
#   dir gets the dev config.
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

# Apply what changed in patches/chromium/ (a pull, say) since the last build.
"$ROOT/scripts/apply_patches.sh"

cd "$ROOT/chromium/src"

# Fiber's own args (core/build/args.gni), then the local config. Both use
# release codegen and no debug symbols. The dev config is a component build:
# many small dylibs for quick incremental links, and DCHECKs on (the default in
# non-official builds). out/Release puts everything in the one framework, so
# the app runs outside the out dir, turns DCHECKs off, since a failed one
# crashes the browser, and strips symbols, which are over 40% of an unstripped
# binary (the linker keeps an unstripped copy beside it, <name>.unstripped).
# Edit $OUT/args.gn afterwards and re-run to change the local part.
if [[ ! -f "$OUT/args.gn" ]]; then
  if [[ "$OUT" == out/Release ]]; then
    config='
    is_component_build = false
    dcheck_always_on = false
    enable_stripping = true'
  else
    config='
    is_component_build = true'
  fi
  gn gen "$OUT" --args="
    import(\"//fiber/build/args.gni\")
    is_debug = false$config
    symbol_level = 0
    blink_symbol_level = 0
    v8_symbol_level = 0
  "
fi

# Each Blink generate_bindings action spawns a cpu_count() multiprocessing pool
# (~230 MB per worker) and all 11 become ready at once; at full -j that's 20+ GB
# and it panicked the machine. Run them two at a time first (no-op when current).
autoninja -C "$OUT" -j 2 third_party/blink/renderer/bindings:generate_bindings_all

autoninja -C "$OUT" -j "$JOBS" "$TARGET"

# Bump the bundle's mtime, as Xcode does after every build. Ninja only rewrites
# files inside Fiber.app, so the bundle keeps the mtime of its first build, and
# LaunchServices and the Dock treat that as the key for their cached app icon:
# without this, a changed icon never reaches the Dock.
if [[ -d "$OUT/Fiber.app" ]]; then
  touch "$OUT/Fiber.app"
fi
