# Fiber

A Chromium-based browser for macOS with its own native UI.

## Layout

| Path | What |
|---|---|
| `CHROMIUM_VERSION` | Chromium release tag we build against (a stable release). |
| `core/` | Fiber's own browser code. Linked into the Chromium tree as `//fiber`. |
| `patches/chromium/` | Our edits to Chromium files, one patch per file. |
| `scripts/` | Sync, patch, build, and run helpers. |
| `chromium/` | gclient checkout (`chromium/src`), not tracked. |
| `depot_tools/` | Chromium's tooling, not tracked. |

## Workflow

```sh
scripts/sync_chromium.sh    # fetch Chromium at CHROMIUM_VERSION (~31GB), apply patches
scripts/build_chromium.sh   # configure out/Default and build (first build: hours)
scripts/run.sh [url]        # launch with a dev profile in chromium/dev-profile
```

After editing a file under `chromium/src`, run `scripts/update_patches.sh` to regenerate `patches/chromium/`. Put new code in `core/` rather than adding files to the Chromium tree.

Requirements: Xcode with the Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`), ~100GB free disk. Exclude `chromium/` from Spotlight (System Settings → Spotlight → Search Privacy).
