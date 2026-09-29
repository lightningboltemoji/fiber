# Fiber: implementation guide

A high-level map of how Fiber is built and why. The rules it follows are in
[PRINCIPLES.md](PRINCIPLES.md); detailed designs live in their own docs
([MEDIA.md](MEDIA.md), [PALETTE.md](PALETTE.md)) and in the code. Commands
are in `README.md`.

Fiber forks Chromium's `//chrome` layer rather than embedding a web engine,
because full Chrome extension support is a hard requirement. (CEF rules that
out: extensions only work in its Chrome-style windows, which show Chrome's UI.)

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
| `browser/` | C++ (`.mm` where it calls the bridge) | Implements Chrome's interfaces (`BrowserWindow`, `LocationBar`, dialog views…), watches Chrome's models, owns Fiber's own per-profile models. | Creates or lays out views. |
| `bridge/` | Objective-C headers | Declares the protocols and immutable value types the other two talk through. | Mentions C++ or Chromium. |
| `ui/` | Swift | Windows, toolbar, tabs, omnibar, command palette, prompts, design system. | Imports anything but the bridge and Apple frameworks. |

`browser/` exists only because Chrome's extension points are C++ classes with
virtual methods, which Swift can't subclass. It translates between Chrome and
the bridge and nothing else, so a feature usually has three parts: a C++
adapter, bridge types, and Swift UI.

Two directories sit outside the three layers, each linked into the part of
Chromium it hooks and depending on nothing that part couldn't:

- `renderer/`: the few hooks Fiber puts in Blink. It can't reach the UI; the
  constants the two share note where the other side is.
- `media/`: H.264, HEVC and AAC with macOS doing all the decoding and encoding,
  and Fiber's code only parsing and passing data through. See
  [MEDIA.md](MEDIA.md).

### Across the bridge

- **Chrome → UI:** `browser/` pushes snapshots (immutable values keyed by
  stable IDs), which `ui/` keeps in `@Observable` models. So far only the tabs
  have one; the rest of the window applies snapshots straight to its views.
- **UI → Chrome:** `ui/` sends intents (navigate, close tab, run command)
  through actions protocols that `browser/` implements.
- **Values and IDs cross, never pointers.** Swift never holds a C++ object; a
  tab's web contents crosses as an opaque `NSView`.
- **Main thread only** (`NS_SWIFT_UI_ACTOR`), which on macOS is Chrome's UI
  thread.
- **C++ owns the UI objects.** When a C++ owner is destroyed, its actions
  object becomes a no-op.
- **C++ gets Swift objects through factories** declared in bridge headers and
  implemented in Swift (`@objc @implementation`), so `browser/` never imports a
  Swift-generated header. Don't give bridge properties custom getters
  (`getter=isFoo`): nothing checks them against the Swift side, and a mismatch
  crashes at runtime.
- **Menu commands go through the window**, which forwards what its responder
  chain doesn't handle to its actions object. That's how Chrome's main menu
  reaches the key window's `Browser`.

## Hooking Chromium

- Edits to Chromium live in `patches/chromium/`, one patch per file, named for
  its path in `chromium/src`, and regenerated from the tree by `make patches`.
  Each change is marked `// Fiber:` (`# Fiber:` in GN) and has no logic of its
  own: it calls a `fiber::` hook, relaxes a views assumption, or points the
  build at Fiber's pieces.
- Hook where Chrome decides what exists (the factory for a views UI, the WebUI
  registration for a page) and return Fiber's implementation. Then cut Chrome's
  (its registration, the fall-through, its resources in `chrome_paks.gni`) so
  the linker drops it, and confirm with `make size`.
- Chrome's own Cocoa pieces (app delegate, main menu) stay Chrome's; Fiber
  hooks them rather than replacing them.
- Fiber's defaults differ from Chrome's through `hooks/feature_overrides.cc`
  and `hooks/profile_pref_defaults.cc`, with the field trial testing config
  off (`args.gni`). The goal is no requests to Google the user didn't ask for.
- For non-views UI, upstream's experimental `WebUIBrowserWindow`
  (`chrome/browser/ui/webui_browser/`) is the reference, and its
  `IsWebUIBrowserEnabled()` checks mark code in Chrome that assumes views.

## Features

Each surface Fiber replaces, and where it lives:

| Surface | Chrome integration | UI |
|---|---|---|
| Browser window, toolbar, status bubble, load progress | `browser/window/` | `BrowserWindowController.swift`, `Toolbar.swift` |
| Tabs (picker on the window's edge, sidebar with the toolbar) | `browser/window/` | `TabPicker.swift`, `TabSidebar.swift` |
| Omnibox, as the omnibar | `browser/omnibox/` | `Omnibar.swift`, `SuggestionList.swift`, `PaletteView.swift` |
| Command palette, in place of Tab Search: every tab, found by name or page text, and commands (see [PALETTE.md](PALETTE.md)) | `browser/palette/` | `CommandPalette.swift`, `PaletteSearch.swift`, `PageTextIndex.swift` |
| New Tab page | `browser/new_tab/` | `NewTabView.swift` |
| JavaScript dialogs | `browser/dialogs/` | `JavaScriptDialog.swift` |
| Prompts over the veiled page: leave site, hold to quit, downloads on quit, extension install and removal, site permissions, form resubmission, opening another app, a site's sign-in (HTTP auth) | `browser/dialogs/`, `hooks/confirm_quit.mm`, `browser/downloads/`, `browser/extensions/` | `Veil.swift`, `VeilPrompt.swift`, `Prompt.swift` |
| Page context menus | `browser/context_menu/` | `ContextMenu.swift` |
| Extensions toolbar, menu and popups | `browser/extensions/` | `Extensions.swift`, `ExtensionsMenu.swift` |
| Windows extensions open (`chrome.windows.create` popups), as bubbles over the page | `browser/extensions/fiber_extension_window.mm` | `ExtensionWindowBubble.swift` |
| Swiping between pages | `browser/swipe/` | `HistorySwipe.swift` |
| The page's scrollbar, clear of the tab picker | `renderer/hooks/` | |
| Media codecs | `media/` | |

Where Fiber has no replacement yet: DevTools, web app and picture-in-picture
windows keep Chrome's UI; quiet permission requests (Chrome's location bar
chip) are ignored, passkey and security key requests and Sign in with Google
(FedCM) fail, screen sharing is refused, offers to save an address, card or
IBAN go unanswered, and the hung page dialog doesn't show
(`hooks/permission_prompt.h`, `hooks/webauthn_dialog.h`,
`hooks/autofill_prompts.h`); extensions' keyboard shortcuts, site access
requests, disabled-extension alert and side panels are missing; and the
component updater, push messaging, autofill crowdsourcing and Google account
checks still call home.

## Tabs and spaces

Today each Fiber window is one Chrome `Browser`, and the UI shows its
`TabStripModel` directly.

Arc-style spaces are coming. Chrome has no concept of them, so Fiber will own a
per-profile model (spaces, pinned entries without a live page, archived tabs)
alongside Chrome's. It lives in `browser/`, since it has to react to what
happens inside Chrome (extensions opening tabs, session restore) and persist
with the profile, and the UI will render it instead of `TabStripModel`. So
already the bridge identifies tabs by stable ID, never position, and the UI
doesn't assume every tab has a live page. How spaces map onto Chrome's
`Browser` is still open.

## Build

- `core/` is symlinked into the Chromium tree as `//fiber`, and
  `scripts/build_chromium.sh` builds everything, Swift included, behind the
  `Makefile`.
- `out/Default` is the component build for development (fast links, but its
  app only runs from there). `out/Release` is self-contained; `make dist` and
  `make install` ship its `Fiber.app`.
- GN compiles Swift with Chromium's Apple toolchain, whose Swift tool one patch
  enables on macOS; `core/build/` holds the template and flags. Swift targets
  macOS 26, while Chromium's C++ keeps its own deployment target.
- `ui/Package.swift` builds the same sources with SwiftPM, for Xcode and for
  `FiberUIHarness`, which runs the UI against a mock browser (`make harness`).
  If `ui/` builds there, it doesn't depend on Chromium.
- Fiber's version is `branding/VERSION`, shown with the Chromium release it's
  built on (`0.1.0c155.8059.12`); Chrome's internal version stays Chromium's
  (`branding/version.gni`). `branding/BRANDING` sets the product name and
  bundle ID, and `make icon` regenerates the app icon's sources.
- `.github/workflows/release.yml` publishes each push to `main` as the `tip`
  prerelease, and a `v<VERSION>` tag as that release and its Homebrew cask. It
  runs on a self-hosted runner that keeps its Chromium checkout and
  `out/Release` between runs, so a build is usually a relink.

## Upgrading

- **Chromium:** each stable release, bump `CHROMIUM_VERSION`, `make sync`, fix
  the patches that no longer apply, and rerun `make size` to check that what
  Fiber cut is still gone.
- **macOS:** `ui/WindowFrame.swift` subclasses AppKit's private frame view to
  place the traffic lights, as Chrome does; check it on each release.

## Layout

```
CHROMIUM_VERSION     Chromium stable release we build against
Makefile             entry points (see README.md)
patches/chromium/    our edits to Chromium, one patch per file
scripts/             sync, patch, build, run, size
core/                → //fiber
  build/             GN args, Swift template and flags
  branding/          product name, version, app icon
  browser/           C++ Chrome integration, one directory per feature
    hooks/           the functions patches call
  renderer/          hooks in Blink
  media/             Chromium's media stack on macOS's codecs
  bridge/            include/FiberBridge/*.h
  ui/                Sources/FiberUI, Sources/FiberUIHarness, Package.swift
chromium/            gclient checkout, not tracked
```
