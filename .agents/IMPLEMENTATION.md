# Fiber: implementation guide

A high-level map of how Fiber is built and why. Detailed designs for individual
areas live in their own docs; this one should stay short enough to read in a few
minutes.

## What Fiber is

A Chromium-based browser for macOS with its own native UI. We fork Chromium's
`//chrome` layer rather than embed a web engine, because full Chrome extension
support is a hard requirement (CEF rules that out: extensions only work in its
Chrome-style windows, which show Chrome's own UI).

## Principles

- **Chrome is the engine and the model.** Every Fiber window is a Chrome
  `Browser`, so anything in Chrome that opens or manages windows and tabs (menus,
  links from other apps, session restore, extensions) lands in Fiber's UI.
- **You should never see Chromium's UI.** We replace Chrome's views UI; we don't
  restyle it. A Chrome surface without a native replacement yet fails safe
  (cancels or denies, never grants) instead of falling back to views. The
  exception is Chrome's in-tab pages (`chrome://settings`, history, downloads,
  extensions), which stay.
- **All visible UI is Swift.** AppKit for the window shell and anything that
  needs precise control, SwiftUI for the rest.
- **Keep the Chromium diff small.** Patches are hooks; the logic lives in
  `//fiber`. We rebase onto each Chromium stable release (see
  `CHROMIUM_VERSION`).
- **macOS 26 and later only.**

## Layers

```
chrome/ content/ components/
        ▲   patches call fiber:: hooks
//fiber/browser   C++    Chrome integration
        │
        ▼
//fiber/bridge    ObjC   the contract (headers only)
        ▲
        │
//fiber/ui        Swift  everything the user sees
```

| Layer | Language | Does | Never |
|---|---|---|---|
| `browser/` | C++ (`.mm` only where it calls the bridge) | Implements Chrome's interfaces (`BrowserWindow`, `LocationBar`, dialog views…), watches Chrome's models, and owns Fiber's own per-profile models. | Creates or lays out views. |
| `bridge/` | Objective-C headers | Declares the protocols and immutable value types the other two layers talk through. | Mentions C++ or Chromium. |
| `ui/` | Swift | Windows, toolbar, tabs, omnibox, dialogs, design system. | Imports anything except the bridge and Apple frameworks. |

`browser/` is only there because Chrome's extension points are C++ classes with
virtual methods, and Swift can't subclass C++ classes. It translates between
Chrome and the bridge and nothing else. Expect every feature to need three
parts: a C++ adapter, bridge types, and Swift UI.

### Across the bridge

- **Chrome → UI:** `browser/` pushes snapshots of state (immutable values keyed
  by stable IDs), which `ui/` keeps in `@Observable` models.
- **UI → Chrome:** `ui/` sends intents (navigate, close tab, run command)
  through actions protocols that `browser/` implements.
- **Values and IDs cross, never pointers.** Swift never holds a C++ object. A
  tab's web contents crosses as an opaque `NSView`.
- **Main thread only** (`NS_SWIFT_UI_ACTOR`). On macOS, Chrome's UI thread is the
  main thread.
- **C++ owns the UI objects.** When a C++ owner is destroyed, its actions object
  turns into a no-op.
- **C++ gets Swift objects through factories** declared in bridge headers and
  implemented in Swift (`@objc @implementation`), so `browser/` never imports a
  Swift-generated header. Value types are declared and implemented the same
  way, which keeps the bridge headers only. Don't give bridge properties custom
  getters (`getter=isFoo`): the compiler doesn't check them against the Swift
  implementation, and the mismatch is a crash at runtime.
- **Menu commands go through the window.** It forwards actions that nothing in
  its responder chain handles to its actions object, which is how Chrome's main
  menu (`-commandDispatch:`) reaches the key window's `Browser`.

## Hooking Chromium

- Edits to Chromium files live in `patches/chromium/`, one patch per file.
- A patch either calls a `fiber::` function in `browser/hooks/`, relaxes a
  views assumption (for example, a `CHECK` that a views-only controller exists),
  or points the build at Fiber's pieces (the Swift tool, the app icon). Each
  change is marked `// Fiber:` (`# Fiber:` in GN) and contains no logic of its
  own.
- The usual pattern: find the factory where Chrome creates a views UI and have it
  return Fiber's implementation instead. `BrowserWindow::CreateBrowserWindow()`
  and the JavaScript dialog factory already work this way.
- Reference for non-views UI: upstream's experimental `WebUIBrowserWindow`
  (`chrome/browser/ui/webui_browser/`). Its `IsWebUIBrowserEnabled()` checks
  mark code in Chrome that assumes views.
- Chrome's native Cocoa pieces (app delegate, main menu, context menus) stay
  Chrome's. We hook them rather than replace them.

## Tabs and spaces

Today each Fiber window is one Chrome `Browser`, and its `TabStripModel` holds
the window's tabs.

Arc-style spaces are coming. Chrome has no concept of them, so Fiber will need
its own per-profile model (spaces, pinned entries that may not have a live page,
archived tabs) that sits alongside Chrome's. That model lives in `browser/`,
not Swift, because it has to react to things that happen inside Chrome
(extensions opening tabs, links opening in new tabs, session restore) and
persist with the profile. The UI renders Fiber's model, not `TabStripModel`
directly.

So from the start:
- the bridge identifies tabs by stable ID, never by position in the tab strip;
- the UI doesn't assume every tab has a live page.

Still open: how spaces map onto Chrome's `Browser` and `TabStripModel`.

## Branding and the app icon

`core/branding/BRANDING` sets the product name, bundle ID, and company;
`core/build/args.gni` points the build at it.

The app icon, "Anchor", abstracts a spider's attachment disc: where a spider
fixes its dragline to a surface, it spins a fan of piriform fibrils set in a
cement membrane. The dragline runs in off the left edge and flares into a hub,
seven fibrils fan out ahead of it (mirrored about its heading), each ending in
a pad, and webbing spans them in shallow scallops. Blue silk on a white ground;
each part is its own Liquid Glass group (dragline on top, fibrils, then web).
`core/branding/icon/src/anchor.py` pins the design as constants: the hub
position, the dragline's heading, the fan's spread, fibril count, length, and
widths, and the colors. The fan's own bounding box, dragline excluded, sits on
the tile's center.

`make icon` runs `core/branding/icon/build.py` with `uv run` (the script
declares its dependencies inline), which rewrites, in `core/branding/icon/`:
- `AppIcon.icon`, the Icon Composer document;
- `Assets.xcassets`, the badge Chrome's `Info.plist` puts on document icons
  (`UTTypeIconBadgeName`);
- `renders/` (gitignored): `ictool` output (Xcode's Icon Composer renderer) for every
  appearance at 1024px, a 256–16px ramp, and `preview.png` with all of it on one
  sheet.

The build compiles the first two with `actool` (`//fiber/branding:app_icon`),
and a patch to `chrome/BUILD.gn` bundles the resulting `Assets.car` and
`app.icns` in place of Chromium's, in the app and in the alert helpers that show
its notifications. Chromium checks in a precompiled icon to keep Xcode tools out
of its build; Fiber already needs them for Swift.

## Build

- `core/` is symlinked into the Chromium tree as `//fiber`, and one
  `scripts/build_chromium.sh` builds everything, Swift included. The
  `Makefile` is the front door (`make build`, `make run`, `make harness`…).
- Two out dirs. `out/Default` is the component build for development: fast
  incremental links, but its app only runs from there. `out/Release` is
  self-contained (one framework, DCHECKs off); `make dist` copies its
  `Fiber.app` to `dist/` and zips it, and `make install` puts it in
  `/Applications`. The binaries carry only the linker's ad-hoc signatures;
  signing for distribution will go through Chromium's `sign_chrome.py` with a
  Developer ID.
- Swift is compiled by GN. Chromium's Apple toolchain already has a Swift tool
  (Chrome for iOS uses it) that is disabled on macOS by a single check. One
  patch enables it, and `core/build/` holds Fiber's Swift template
  (`fiber_swift_source_set` in `swift.gni`) and flags (macOS 26 target, Swift 6
  language mode). It uses Xcode's `swiftc`.
- macOS 26: `args.gni` sets `mac_min_system_version` to 26.0, which is the app's
  `LSMinimumSystemVersion` and the Swift target. Chromium's C++ still compiles
  against Chromium's `mac_deployment_target` (13.0); raising that would turn up
  deprecations all over Chromium, and C++ calling newer APIs still needs
  `@available`. The linker rejects objects built for a newer macOS than the image
  it's linking, so everything that links Swift (`libchrome_dll`, the app and its
  helpers) is linked for 26.0, through a config (`//fiber/build:swift_link`)
  that Swift targets pass to their dependents.
- swiftc's module cache is kept between builds (`swift_keep_intermediate_files`).
  A one-line Swift change rebuilds and relinks in about 11 seconds.
- `ui/Package.swift` compiles the same sources with SwiftPM so Xcode can open
  them. That gives us previews, editor tooling, and `FiberUIHarness`, which runs
  the UI against a mock browser without building Chromium
  (`swift run --package-path core/ui FiberUIHarness`). If `ui/` builds under
  SwiftPM, it doesn't depend on Chromium. SwiftPM sees the bridge through
  `ui/Sources/FiberBridge`, a symlink to `bridge/include`.
- GN compiles each Swift module as one unit. If UI rebuilds get slow, split
  `ui/` into more modules.

## Layout

```
CHROMIUM_VERSION     Chromium stable release we build against
Makefile             entry points: build, run, harness, icon, dist, install
patches/chromium/    our edits to Chromium, one patch per file
scripts/             sync, patch, build, run
core/                → //fiber
  build/             GN args (args.gni), Swift template (swift.gni) and flags
  branding/          product name, bundle ID; BUILD.gn compiles the app icon
    icon/            the icon's generator, AppIcon.icon, Assets.xcassets, renders
  browser/           C++ Chrome integration
    hooks/           the functions patches call
    window/          BrowserWindow implementation and its stubs
    dialogs/         dialogs Chrome shows for a tab (JavaScript dialogs)
    …                one directory per feature (tabs, omnibox, downloads, extensions…)
  bridge/            include/FiberBridge/*.h + include/module.modulemap
  ui/
    BUILD.gn         built by GN into the app
    Package.swift    the same sources, built by SwiftPM for Xcode
    Sources/FiberUI/
    Sources/FiberUIHarness/
    Sources/FiberBridge → ../../bridge/include
chromium/            gclient checkout, not tracked
dist/                make dist output, not tracked
```

## Status

The layers, build, and layout above are in place. Swift builds in GN and links
into the component build. The window (toolbar, location field, load progress,
status bubble) and the JavaScript dialogs are Swift behind the bridge, with the
same behavior as the Objective-C++ they replaced, and `FiberUIHarness` runs them
against a mock browser. Two things aren't yet as described:

- The window applies the snapshots it's pushed straight to its AppKit views;
  `@Observable` models arrive with the first SwiftUI surface.
- Only the active tab's state crosses the bridge (`FiberPageState`). Tabs, keyed
  by stable IDs, come with the tab strip.

Next: features.
