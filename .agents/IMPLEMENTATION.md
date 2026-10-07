# Fiber: implementation guide

A high-level map of how Fiber is built and why. The rules it follows are in
[PRINCIPLES.md](PRINCIPLES.md); detailed designs live in their own docs
([MEDIA.md](MEDIA.md), [PALETTE.md](PALETTE.md))
and in the code. Commands are in `README.md`.

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
| `ui/` | Swift | Windows, tabs, omnibar, command palette, prompts, design system. | Imports anything but the bridge and Apple frameworks. |

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
- **Snapshots come whole and often:** the omnibox's suggestions again as each
  favicon arrives or a provider answers, a tab's state as it loads. So `ui/`
  keeps the views it has and sets only what changed (setting an image or text
  redraws it), and a list that can be long makes views only for rows in sight.
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
- Chrome's in-tab pages stay, but read as Fiber's. `url_formatter` shows
  `chrome://` as `fiber://` and reads `fiber://` back as `chrome://`, so Chrome
  and extensions only ever see `chrome://` (`branding/url_scheme.h`). Chrome's
  product logos are Fiber's mark (`hooks/resource_bundle_delegate.mm`). A page
  loads `chrome://resources` from the renderer's own copy of Chrome's
  resources, so its logos point at `chrome://theme`'s, which the browser
  serves. Their favicons are ones Fiber picks, which its UI draws in the color of the
  text (`hooks/web_ui_favicons.mm`, `BuiltInPageFavicon.swift`). With no
  updater, the About page says nothing about updates.
- Fiber's defaults differ from Chrome's through `hooks/feature_overrides.cc`,
  `hooks/profile_pref_defaults.cc` and `hooks/local_state_pref_defaults.cc`,
  with the field trial testing config off (`args.gni`). The goal is no
  requests to Google the user didn't ask for, and no way into what Fiber
  doesn't have.
- Commands whose UI Fiber doesn't have yet are disabled for Fiber windows in
  Chrome's own command controller (`hooks/commands.cc`), so however one comes
  (the menu, the command palette, an extension), it doesn't reach views.
- For non-views UI, upstream's experimental `WebUIBrowserWindow`
  (`chrome/browser/ui/webui_browser/`) is the reference, and its
  `IsWebUIBrowserEnabled()` checks mark code in Chrome that assumes views.

## Features

Each surface Fiber replaces, and where it lives:

| Surface | Chrome integration | UI |
|---|---|---|
| Browser window and load progress, and the status bubble: the hovered link's URL in a glass capsule in the page's bottom-left corner, which moves to the bottom-right when the pointer comes near and shows a long URL whole once the pointer rests on its link | `browser/window/` | `BrowserWindowController.swift`, `StatusBubble.swift` |
| Tabs: a picker of the 15 most recent on the window's edge, and the tab overlay (⌘S): the rest of the tabs in order, in a panel as wide as the command palette's over the dimmed page, with the pins in rows of glass circles rising from its top, all a little above the middle of the window, and beside it the page's address (which opens the omnibar) and the extensions. Its arrow keys, Return and ⌘W move through, switch to and close the pins and tabs (see [Tabs and spaces](#tabs-and-spaces)); one picked is switched to at once, under the overlay as it closes, which plays its opening back, quicker, showing what it closed with until it's gone; the omnibar or command palette opening cuts that short. It keeps the keyboard until it closes, so a New Tab page that becomes active under it opens the omnibar only then; a tab opened in front (⌘T, a link from another app) closes it. A tab opened from the active one, in front of it or behind (a link on its page, ⌘-clicked or not, an extension, the omnibar; not a New Tab page, by Chrome's opener), shows in a notice in the window's top-right corner, below the find bar if it's open: a list like the picker's of the tab it opened from, which grows to take it in (and the next few opened behind the same tab), and goes after a moment unless the pointer is on it, or when swiped (or dragged) off to the right like a notification | `browser/window/`, `browser/pins/` | `TabPicker.swift`, `TabOverlay.swift`, `PinGrid.swift`, `TabList.swift`, `TabMenus.swift`, `OpenedTabNotice.swift` |
| Omnibox, as the omnibar, where Option-clicking part of the URL selects it and the rest, as does pressing Option and the number shown under that part | `browser/omnibox/` | `Omnibar.swift`, `SuggestionList.swift`, `PaletteView.swift`, `URLFieldEditor.swift` |
| Command palette, in place of Tab Search: every tab, found by name or page text, and commands (see [PALETTE.md](PALETTE.md)) | `browser/palette/` | `CommandPalette.swift`, `PaletteSearch.swift`, `PageTextIndex.swift` |
| Find in page, a bar in the window's top-right corner | `browser/find_bar/` | `FindBar.swift` |
| New Tab page | `browser/new_tab/` | `NewTabView.swift` |
| Incognito windows: dark, like Safari's Private Browsing, with a hand in the address and a New Tab page that says what Incognito keeps | `browser/window/`, `browser/new_tab/` | `BrowserWindowController.swift`, `TabOverlay.swift`, `NewTabView.swift` |
| JavaScript dialogs | `browser/dialogs/` | `JavaScriptDialog.swift` |
| Prompts, in glass bubbles over the page, which stays usable around them: leave site, downloads on quit, extension install and removal, site permissions, form resubmission, opening another app, a site's sign-in (HTTP auth), a site's files from an earlier visit (File System Access), and Chrome's `ui::DialogModel` dialogs (confirming a folder upload, File System Access's questions, Name Window, extensions' notices). A tab's shows while the tab is active, centered on a short page and a quarter of the way down a tall one; the window's own (downloads, extension notices, Name Window) shows over whichever tab is, ahead of the tab's. Each is a capsule with its icon at one end and its buttons at the other, growing into a rounded rectangle for fields, a list or more text; once its text runs past a few lines the buttons go under it, at the end, and beside fields they line up with them, one to a field when there are as many. Sites are named without http or https; a sign-in over HTTP says the connection isn't private. It opens from a circle around its icon as a wave like the tab overlay's runs across it. Its glass is light, or dark over a dark page, whatever the window's appearance (from a thumbnail of the page behind it as it shows): light glass reads over anything, dark glass only over dark. It takes the keyboard as it shows, unless something over the page has it, so Return and Escape answer it (their keys show on its buttons), and gives it back when the user clicks the page | `browser/dialogs/`, `browser/downloads/`, `browser/extensions/` | `PromptBubble.swift`, `Prompt.swift`, `DownloadsWait.swift` |
| Hold to quit (⌘Q), in place of Chrome's confirm-to-quit panel: the veil fills each window's page while the keys are held | `hooks/confirm_quit.mm` | `QuitConfirmation.swift`, `Veil.swift` |
| Dimming under the tab overlay, omnibar, command palette and veil: black over the window, and under the tab overlay more, pooled under its glass (the panel, each row of pins, the address and extensions) and blurred, so the glass sits on a dark backdrop and the page fades back in toward the window's edges. The pool is darker over a darker page, by how light a thumbnail of the page is, the middle counting most | `browser/window/page_thumbnail.mm` | `Dimming.swift` |
| Profile switcher, in place of Chrome's Profile Picker and avatar menu (Profiles › Switch Profile…, ⇧⌘M): the profiles turning slowly around a hub over the veiled page, making one, and making one from a Chrome profile (its bookmarks, history, passwords and cookies). Fiber's avatars stand in for Chrome's wherever Chrome draws one | `browser/profiles/`, `hooks/resource_bundle_delegate.mm` | `ProfileSwitcher.swift`, `ProfileSwitcherView.swift`, `ProfileAvatar.swift` |
| Page context menus | `browser/context_menu/` | `ContextMenu.swift` |
| Extensions' buttons (in the tab overlay), menu and popups | `browser/extensions/` | `Extensions.swift`, `ExtensionsMenu.swift` |
| Windows extensions open (`chrome.windows.create` popups), as bubbles over the page | `browser/extensions/fiber_extension_window.mm` | `ExtensionWindowBubble.swift` |
| Swiping between pages | `browser/swipe/` | `HistorySwipe.swift` |
| Key passthrough: the active tab's page gets ⌘S, ⌘P and ⌘L (see [Keyboard shortcuts](#keyboard-shortcuts)) | `browser/window/key_passthrough.mm` | `KeyPassthroughBubble.swift` |
| DevTools, docked at the bottom or right of the window. The window's controls lay out over the page as if it were the window, and hide while DevTools emulates a device. DevTools' dock menu offers neither left nor a window of its own (patches in `third_party/devtools-frontend`) | `hooks/devtools_dock.mm`, `browser/window/` | `BrowserWindowController.swift` |
| A page whose renderer crashed or was killed (Chrome's sad tab), drawn over it | `browser/window/fiber_sad_tab.mm` | `SadTabView.swift` |
| The page's scrollbar, clear of the tab picker | `renderer/hooks/` | |
| Native messaging hosts, found in Chrome's folders as well as Fiber's, since apps only register them with browsers they know | `hooks/native_messaging.cc` | |
| Media codecs | `media/` | |

Where Fiber has no replacement yet:

- **Chrome's UI, kept:** DevTools windows (for what can't dock, like
  workers and extensions), web app and picture-in-picture windows. Docked
  DevTools can't move into one: a page views has shown never draws in a Fiber
  window again (`RenderWidgetHostViewMac::SetParentUiLayer()`).
- **Refused, for the page:** passkeys, security keys and Sign in with Google
  (FedCM) fail; screen sharing and an extension's screen capture are refused;
  a site asking for a USB, HID, serial or Bluetooth device, or to choose a
  saved password, gets none; quiet permission requests (Chrome's location bar
  chip) are ignored (`hooks/permission_prompt.h`, `hooks/webauthn_dialog.h`,
  and patches marked `Fiber:` in Chrome's views code).
- **Not offered:** installing a page as an app; Save and fill on card forms;
  Task Manager, tab groups, split view and side panels
  (`hooks/commands.cc`); the profile switcher at startup
  (`hooks/local_state_pref_defaults.cc`), and signing in to a profile Chrome
  locks until then (`browser/profiles/profile_picker.cc`); Chrome's sharing
  hub, leaving the Share menu (`hooks/profile_pref_defaults.cc`); Payment
  Request, digital credentials, and Cast with the Presentation API
  (`hooks/feature_overrides.cc`, with most of their code cut by patches);
  Gemini in Chrome (Glic), off in `hooks/feature_overrides.cc`, with its pages
  cut.
- **Unanswered, or not shown:** offers to save an address, card or IBAN, or to
  ask for Touch ID before filling a card (`hooks/autofill_prompts.h`); the hung
  page dialog, Safety Tips and the low storage notice.
- **Missing:** extensions' keyboard shortcuts, site access requests,
  disabled-extension alert and side panels.
- **Still calling home:** the component updater, push messaging, autofill
  crowdsourcing and Google account checks.

## Keyboard shortcuts

The page with focus sees a key before the main menu, except for shortcuts the
browser keeps from it, which no page can swallow, even a hung one. The window
offers each key equivalent to
`FiberBrowserWindow::PerformReservedKeyEquivalent()` before its views see it
(where Chrome's own Mac windows reserve keys, in their `CommandDispatcher`).
While a page, DevTools or an extension window has focus, that runs the main
menu item itself for:

- Chrome's reserved commands (`IsReservedCommandOrKey()`): ⌘W, ⌘T, ⌘N, ⌘Q,
  ⇧⌘T, switching tabs.
- Fiber's ⌘S, ⌘P and ⌘L (Show Tabs, Command Palette, Open Location), unless
  the tab has key passthrough.

A disabled item's shortcut still goes to the page, as does every key while a
fullscreen page holds the keyboard lock. Other shortcuts (⌘F, ⌘R…) go to the
page first and reach the menu only if it doesn't use them
(`HandleKeyboardEvent()`).

**Key passthrough** (View › Key Passthrough, or the command palette) lets the
active tab's page and its DevTools have ⌘S, ⌘P and ⌘L, for web apps that use
them, like an editor's Save and Quick Open. It belongs to the tab and ends when
the tab goes to another site (`window/key_passthrough.mm`). Meanwhile a bubble
in the page's top-right corner, where extension windows' bubbles start (they
move below it), ends it with its ×, or when Escape is held for a second, as a
ring around its keyboard fills. A tap of Escape still goes to the page.

## Tabs and spaces

Each Fiber window is one Chrome `Browser`, and the UI shows its
`TabStripModel`, with the profile's pins above it.

Closing tabs doesn't close the window: when the user closes the last one (⌘W,
or from the tab overlay, picker or menu), a New Tab page opens in its place,
and closing a lone New Tab page does nothing but open the omnibar
(`FiberBrowserWindow::WillCloseTabs()`). Only ⇧⌘W, the close button or ⌘Q
close it. A page, an extension or a drag that takes the last tab still closes
the window, as Chrome does.

Arc-style spaces are coming. Chrome has no concept of them, so Fiber owns a
per-profile model alongside Chrome's. It lives in `browser/`, since it has to
react to what happens inside Chrome (extensions opening tabs, session restore)
and persist with the profile. So the bridge identifies tabs by stable ID,
never position, and the UI doesn't assume every tab has a live page. How
spaces map onto Chrome's `Browser` is still open.

Pins are its first part (`browser/pins/`). A pin is a URL the user keeps to
come back to, in the order they arranged it, which every window of the
profile shows whether or not it has the pin open:

- `PinStore` keeps a profile's pins (URL, title, last favicon) in its prefs.
  Incognito and Guest have none.
- A pin open in a window is a Chrome-pinned tab there, so extensions see
  `pinned: true`. `PinnedTabs` keeps each window's pinned tabs in step with
  the store: one tab per pin, in the pins' order. A tab Chrome pins (the Tab
  menu's Pin Tab, an extension) becomes a new pin's; unpinning a pin's tab
  unpins the page from every window. The tab strip can't change while it
  notifies, so reordering and unpinning wait for a posted task.
- Which pin a tab is the page of is `WebContents` user data, kept in its
  session's extra data, which patches carry through session rebuilds and
  closed-tab restore (`hooks/tab_extra_data.h`). A tab restored for a pin
  that's gone, or already open in its window, is unpinned.
- Chrome's own pinned-tab persistence (`PinnedTabService`, and pinned tabs
  reopened at startup) is cut: pins open only when clicked.

## Startup

Fiber's window shows before Chrome's startup is done. Chrome makes its first
browser only after loading local state, the profile and its services, which
on the main thread takes most of startup; its window then goes on screen at
the main loop's first idle, later still.

- **The startup window** (`hooks/startup_window.mm`). As soon as the process
  holds the process singleton (so it's the browser, not a launch handing its
  URLs to a running one), `ShowStartupWindow()` shows a Fiber window where the
  last startup's window went, with only the New Tab page's mark on its page,
  since that's usually what it turns out to be. The first normal,
  non-Incognito browser takes the window over rather than making one
  (`FiberBrowserWindow`'s constructor), and tells it what to show from then
  on, but the page, and the omnibar the browser opens over a New Tab page,
  don't show until AppKit has finished launching. Until then the New Tab page
  may be about to go: a link from another app is an Apple event, which
  arrives as AppKit finishes launching, and AppController then opens it in the
  New Tab page's place. Chrome starts up on the main thread, so keys typed
  meanwhile wait in the event queue, and reach the omnibar, which by then has
  the keyboard. Until Chrome shows the window it counts as hidden, as Chrome's
  startup expects. If no browser has taken it by the time AppKit has finished
  launching (Incognito by policy, say), it closes.
- **Only what shows is built.** The command palette is made the first time it
  opens, and the omnibar when the browser takes the startup window. The window
  is made at its final size so it's laid out once.
- **Off the main thread.** Until the browser's threads start, the main thread
  does nearly all of startup, much of it waiting on other processes. The crash
  reporter starts on a thread of its own just after the startup window (it
  launches a handler process and waits for it to answer), and the main thread
  waits for it only before the browser's threads start: child processes
  inherit its exception port as they launch (`hooks/crash_reporter.h`). As
  `ChromeMain()` starts, another thread gets the displays from the window
  server, which `NSApplication`'s init otherwise waits for
  (`hooks/startup_prefetch.cc`).
- **Cold starts** (`hooks/startup_prefetch.cc`). Startup runs code from all
  over the framework (in all, about half its code pages), which after a
  restart comes off the disk a page at a time. The browser process reads it
  in ahead on a background thread, as soon as `ChromeMain()` starts, at a
  priority whose reads give way to the main thread's.
- **Work nothing needs.** Chrome's first policy load asks whether the Mac is
  managed, which runs `/usr/bin/profiles` on the main thread, even with no
  policy to filter; Fiber's patch only asks when there is one. Out/Release
  strips local symbols: besides their size, `atexit()` looks up its caller
  with `dladdr()`, which scans the whole symbol table, and Chrome calls it at
  startup. Fitting a window to the screen (`setFrame:`, `isZoomed`) asks the
  window server, a few milliseconds each while the app starts, so the startup
  window isn't moved to where it already is, and `Show()` doesn't force a
  display of a window that's already on screen.

To measure: a launch through LaunchServices, as from the Dock, to the window
on screen (`CGWindowListCopyWindowInfo`), warm and with the app's files
evicted from the page cache (`msync(MS_INVALIDATE)` on each). On an M3
MacBook Air, from the launch to the window: 420 ms before all this and about
230 ms after (warm), 860 ms and 290 ms (cold). A freshly built app launches
some 20 ms slower for its first few dozen launches, while macOS vets it, so
measure a build once that's passed. Instruments' System Trace inflates child
process launches (`/usr/bin/profiles` looks like 90 ms instead of 10).
`xctrace record --launch` starts the copy of Fiber that LaunchServices finds
for its bundle ID, `/Applications/Fiber.app` if there is one, not the build it
names; record `--all-processes` and start the build yourself. Chrome's startup
tracing (`--trace-startup`) only starts after `PostEarlyInitialization()`, so
everything up to the startup window shows only in Instruments.

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
- `FiberSlowMotion` (the harness's `--slow-motion`) slows the UI's animations:
  AppKit's and Core Animation's through each browser window's layer clock, but
  SwiftUI's only if they take `.slowMotion`, and delays that wait on an
  animation only through `SlowMotion.duration(_:)`. New ones need the same.
- Fiber's version is `branding/VERSION`, shown with the Chromium release it's
  built on (`0.1.0c155.8059.12`); Chrome's internal version stays Chromium's
  (`branding/version.gni`). `branding/BRANDING` sets the product name and
  bundle ID, and `make icon` regenerates the app icon's sources.
- `.github/workflows/release.yml` publishes each push to `main` as the `tip`
  prerelease, and a `v<VERSION>` tag as that release and its Homebrew cask. It
  runs on a self-hosted runner that keeps its Chromium checkout and
  `out/Release` between runs, so a build is usually a relink.

## Upgrading

- **Chromium:** each Stable release, as `.claude/skills/upgrade-chromium`
  describes. `make sync` rebases the patches onto a new `CHROMIUM_VERSION`
  (`scripts/rebase_patches.sh`), leaving conflict markers where upstream changed
  what a patch changes.
- **macOS:** `ui/WindowFrame.swift` subclasses AppKit's private frame view to
  place the traffic lights, as Chrome does; check it on each release.

## Layout

```
CHROMIUM_VERSION     Chromium stable release we build against
Makefile             entry points (see README.md)
patches/chromium/    our edits to Chromium, one patch per file
scripts/             sync, patch, rebase, build, run, size
core/                → //fiber
  build/             GN args, Swift template and flags
  branding/          product name, version, app icon, fiber:// scheme
  browser/           C++ Chrome integration, one directory per feature
    hooks/           the functions patches call
  renderer/          hooks in Blink
  media/             Chromium's media stack on macOS's codecs
  bridge/            include/FiberBridge/*.h
  ui/                Sources/FiberUI, Sources/FiberUIHarness, Package.swift
chromium/            gclient checkout, not tracked
```
