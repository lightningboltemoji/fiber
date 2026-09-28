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

See [PRINCIPLES.md](PRINCIPLES.md). In short: Chrome is the engine and the
model, Fiber replaces its UI (for real, not by covering it) in Swift, and the
Chromium diff stays small.

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
| `ui/` | Swift | Windows, toolbar, tab picker, command palette, dialogs, design system. | Imports anything except the bridge and Apple frameworks. |

`renderer/` is the exception to the three layers: the few hooks Fiber puts in
Blink, which runs in the renderer, away from the rest. It's linked into Blink's
core, so it depends on nothing Blink couldn't (`//ui/gfx`), and it can't talk
to the UI; what it shares with the UI is a constant or two, each noting where
the other side is.

`media/` is the same kind of exception, for Chromium's media stack: each of its
targets is linked into the part of Chromium it hooks (`//media`, the GPU
process's VideoToolbox decoder, the renderer's Web Audio), and depends on
nothing that part couldn't. Fiber plays H.264, HEVC and AAC, but macOS does all
of their decoding and encoding; Fiber's code only parses and passes data
through, as Firefox does on macOS. `args.gni` builds Chromium's MP4 and HLS
parsing (`proprietary_codecs`) without ffmpeg's H.264 and AAC decoders or
OpenH264, and `media/video/` takes the place of Chromium's H.264 and HEVC
decoders, which run each standard's decoded picture buffer before handing
VideoToolbox the frames. See [MEDIA.md](MEDIA.md).

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

- Edits to Chromium files live in `patches/chromium/`, one patch per file,
  named for its path in `chromium/src`. That includes the few in repositories
  nested there (`third_party/ffmpeg`), which the patch scripts list.
- A patch either calls a `fiber::` function in `browser/hooks/`, relaxes a
  views assumption (for example, a `CHECK` that a views-only controller exists),
  or points the build at Fiber's pieces (the Swift tool, the app icon). Each
  change is marked `// Fiber:` (`# Fiber:` in GN) and contains no logic of its
  own.
- The usual pattern: find where Chrome decides what exists (the factory for a
  views UI, the URL rewrite or WebUI registration for a page) and have it
  return Fiber's implementation instead. `BrowserWindow::CreateBrowserWindow()`
  and the JavaScript dialog factory work this way, but still fall through to
  Chrome's views; the New Tab page (`fiber::AddWebUIConfigs()`) replaces
  Chrome's outright.
- Cut what Fiber replaces, so the linker drops it: take out its registration
  (or the fall-through branch), and its resources from `chrome/chrome_paks.gni`.
  `make size` (`scripts/size.py`) relinks the //chrome library with a linker
  map and reports its size by source directory, what dead-stripping removed,
  and what moved since the last run.
- Where Fiber's defaults differ from Chrome's: feature overrides in
  `hooks/feature_overrides.cc` (below command-line flags, above field trials)
  and profile pref defaults in `hooks/profile_pref_defaults.cc` (the user can
  still change them in `chrome://settings`). `args.gni` turns off the field
  trial testing config, which unbranded builds otherwise apply, so features
  start from Chromium's shipped defaults. The goal is no requests to Google the
  user didn't ask for; so far that holds for the omnibox (see those files and
  `hooks/omnibox_providers.cc`), while the component updater, push messaging
  (GCM), autofill crowdsourcing, and Google account checks still call home.
- Reference for non-views UI: upstream's experimental `WebUIBrowserWindow`
  (`chrome/browser/ui/webui_browser/`). Its `IsWebUIBrowserEnabled()` checks
  mark code in Chrome that assumes views.
- Chrome's native Cocoa pieces (app delegate, main menu) stay Chrome's. We
  hook them rather than replace them. Pages' context menus keep Chrome's model
  and commands but not its menu (see Status).

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
- Two versions. Fiber's is `branding/VERSION` (`0.1.0`), and the app shows it
  with the Chromium release it's built on, `0.1.0c155.8059.12`
  (`branding/version.gni`): in Finder (`CFBundleShortVersionString`), on
  Settings › About and on `chrome://version`, and in `make dist`'s zip name.
  Chrome itself keeps Chromium's version (`chrome/VERSION`), since the
  User-Agent, extensions' `minimum_chrome_version` and the framework's
  `Versions/` directory depend on it, and so do the framework's and the
  helpers' `Info.plist`s. The app's `CFBundleVersion`, which Launch Services
  and updaters compare, is Fiber's version alone, so every release bumps it,
  even one that only takes a new Chromium. Tag releases `v<VERSION>`.
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
  that Swift targets pass to their dependents. The same config tells lld to
  skip SwiftUI's auto-link of `CoreAudioTypes`, a headers-only framework that
  Chromium's `--strict-auto-link` would otherwise fail on.
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
scripts/             sync, patch, build, run, size
core/                → //fiber
  build/             GN args (args.gni), Swift template (swift.gni) and flags
  branding/          product name, bundle ID, version; BUILD.gn compiles the app icon
    icon/            the icon's generator, AppIcon.icon, Assets.xcassets, renders
  browser/           C++ Chrome integration
    hooks/           the functions patches call
    window/          BrowserWindow implementation and its stubs
    context_menu/    pages' context menus
    dialogs/         JavaScript dialogs, tab-modal and app-modal (beforeunload), prompts
    extensions/      the toolbar's extensions, their popups, adding and removing them
    downloads/       waiting for downloads before quitting or closing
    swipe/           swiping between pages, and the snapshots it shows
    new_tab/         chrome://newtab, Fiber's New Tab page
    …                one directory per feature (tabs, omnibox, downloads, extensions…)
  renderer/          hooks in Blink (hooks/)
  media/             Chromium's media stack, with macOS's codecs (MEDIA.md)
    hooks/           the functions media patches call
    video/           H.264 and HEVC for Chromium's VideoToolbox decoder
    aac/             AAC's AudioSpecificConfig, as AudioToolbox is given it
    web_audio/       Web Audio's AAC, decoded in the GPU process
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
into the component build, and `FiberUIHarness` runs the UI against a mock
browser.

The page fills the whole window, title bar included, and the browser's
controls float over it in Liquid Glass, mostly out of sight:

- **Toolbar** (`ui/Toolbar.swift`), hidden until View > Show Toolbar
  (Command-S; Save Page As moves to Shift-Command-S). A row of capsules level
  with the traffic lights: the traffic lights' own, an address capsule
  (back/forward, the page's address, reload), and one for extensions (see
  below) and, for now, a placeholder for menus. Buttons with an icon are
  circles, and the address a capsule. The traffic lights
  otherwise stay hidden (and take no clicks).
  `browser/window/fiber_main_menu.mm` adds the menu item
  to Chrome's main menu; the window handles `-toggleToolbarShown:`.
  The tab sidebar (`ui/TabSidebar.swift`) shows and hides with the toolbar:
  the tab picker's panel (see below), kept open below the toolbar's right
  end, as tall as its tabs down to the window's bottom, and scrolling past
  that with the active tab kept in view. Clicking a tab selects it. Meanwhile
  the gutter doesn't open the picker.
- **Command palette** (`ui/CommandPalette.swift`): Command-L (Chrome's Focus
  Location, so new tabs open it too) or clicking the toolbar's address opens a
  glass panel over the dimmed page, with the page's full URL selected. Nothing
  else edits the address. It's Chrome's omnibox with the palette as its view
  (`browser/omnibox/`, `bridge/FiberOmnibox.h`): the window's `LocationBar`
  owns an `OmniboxController` with Chrome's `ChromeOmniboxClient`, the way
  upstream's `WebUILocationBar` does, so autocomplete, inline autocompletion,
  keyword mode (extensions' `chrome.omnibox` included), Switch to Tab, and
  opening a match (Option-Return for a new tab, Command-Return for one in the
  background) are all Chrome's. `FiberOmniboxView` mirrors the edit model's
  text and selection to the field and reports the user's edits back;
  `FiberOmniboxPopupView` sends the results as `FiberSuggestion`s, listed by
  `ui/SuggestionList.swift`. Closing the palette discards the edit.
  Suggestions are the user's own (history, bookmarks, open tabs, keywords):
  Fiber leaves out the providers that only work with Google
  (`hooks/omnibox_providers.cc`), and search suggestions from the search
  engine are off by default. It's meant
  to grow into a Raycast-like home for Fiber's commands.
- **New Tab page** (`ui/NewTabView.swift`): a plain page with Fiber's mark
  (`ui/FiberMark.swift`, generated from the icon's geometry by `make icon`).
  `chrome://newtab` is Fiber's own WebUI (`browser/new_tab/`): Chrome no longer
  rewrites it to its New Tab page, whose WebUIs and resources are cut. The page
  is empty and in the window's background color, and the window draws the rest
  over it, so the frame Chrome holds while navigating away looks the same.
  An extension's New Tab page still replaces it.
  Switching to a tab restores its focus as Chrome's views window does, which
  on the New Tab page means the command palette.
- **Tab picker** (`ui/TabPicker.swift`, drawn by `TabPickerView.swift`, with
  the list in `TabList.swift`, which the tab sidebar shares): the
  page stops 8pt short of the window's right edge, and that gutter
  (`ui/PageGutter.swift`, which shows the page as the top of a stack of tabs)
  is the picker's handle: hovering anywhere along it opens a panel listing
  the tabs, placed so the active tab is level with the pointer, which comes
  out of the gutter like a drop of glass that stretches out and spreads into
  the panel; dragging it moves the window. Scrolling moves the panel under the pointer like a picker
  wheel, and lifting off selects the tab that settles there; clicking selects
  too. AppKit takes all the input; SwiftUI draws, over an `@Observable` model.
  The page's own scrollbar (its main frame's, when overlay scrollbars are on)
  sits 4pt in from the page's edge and stops short of its rounded corners
  (`renderer/hooks/page_scrollbar.cc`, from Blink's
  `PaintLayerScrollableArea::RectForVerticalScrollbar()`, so it paints,
  hit-tests and composites there).
- **The veil** (`ui/Veil.swift`): when a window waits on the user, its page
  blurs and the window darkens, and what it's waiting for shows over it
  (`ui/VeilPrompt.swift`: an icon, a title, a message, glass buttons; Return
  and Escape press the default and cancel buttons, and the window's clicks,
  keys and menu shortcuts go nowhere else). The blur is a filter on the page
  area, not a backdrop, which would darken toward the window's edges.
  `bridge/FiberPrompt.h` (`dialogs/prompt.mm`, `ui/Prompt.swift`) is the
  general case, for Chrome's dialogs that are words and buttons: a prompt
  another takes the place of, or whose window closes, ends unanswered.
  - *Holding Command-Q to quit* (Warn Before Quitting, `ui/QuitConfirmation.swift`,
    `hooks/confirm_quit.mm`): the veil falls over every window while the key
    is held and drains off when it's let go; another press fills it from
    there. Once it's full the windows fade out. Chrome's
    `ConfirmQuitPanelController`, and its quit on a double press, are cut.
  - *Leave site?*: every page's beforeunload prompt (closing a tab or window,
    navigating, reloading, quitting), with the site's name. Chrome shows these
    through its app-modal dialog factory, which Fiber replaces
    (`dialogs/fiber_app_modal_dialog_view.mm`); a quit brings each asking
    window back in turn. Chrome's Cocoa app-modal dialog is cut.
  - *Quitting when downloads finish* (`downloads/downloads_wait.mm`): quitting
    with downloads in progress lists them with their progress, to cancel or
    resume each; the quit goes ahead once they're done, or at once with Quit
    Now, and Continue Browsing (Escape) calls it off. Chrome's alert is cut.
    Closing the last Incognito window with downloads waits the same way.
  - *Adding and removing extensions* (`extensions/extension_install_dialog.mm`,
    `extensions/extension_uninstall_dialog.mm`, `hooks/extension_dialogs.mm`):
    Chrome's install prompt ("Add “uBlock Origin Lite”?" and what it can do,
    from the Web Store or `chrome://extensions`; also re-enabling one that
    asks for more, and `chrome.permissions.request()`), a notice once it's
    added (with Pin to Toolbar), and the confirmation before removing one.
    Adding takes a click, not Return, and the button waits half a second, as
    Chrome's does. Each is asked in the window it's for, or the profile's last
    active one, or answered no. Chrome's views dialogs for all three are cut.
- **Context menus** (`context_menu/fiber_render_view_context_menu.mm`,
  `ui/ContextMenu.swift`): right-clicking a page shows a native menu built
  from Chrome's (`RenderViewContextMenu`, which decides what's in it and runs
  each command, extensions' items included), with only the items Fiber lists:
  what's particular to what was clicked (a link, an image, video, selected or
  edited text) and View Page Source and Inspect. Back, Reload, Print and
  Google's services (Cast, Translate, Lens, Send to Your Devices…) are left
  out, and so is anything a new Chromium release adds until it's listed.
  AppKit adds its own (Services, Speech, AutoFill) as it does to any text
  view's menu. DevTools windows keep Chrome's Cocoa menu.
- **Extensions** (`extensions/`, `bridge/FiberExtensions.h`,
  `ui/Extensions.swift`, `ui/ExtensionsMenu.swift`): the toolbar's last
  capsule has a puzzle piece that opens the extensions menu (a popover
  listing every extension, a pin for each, and Manage Extensions), and the
  buttons of pinned extensions beside it, each with its icon and badge, dimmed
  where it can't run. Clicking one runs it; right-clicking shows its menu
  (Chrome's `ExtensionContextMenuModel`, through the context menu bridge:
  Options, Unpin, Remove, Inspect Popup…). A popup is the extension's page
  (`ExtensionViewHost`) in a popover from its button, or the puzzle piece if
  it isn't pinned, sized as the page asks, closing on a click away, Escape or
  `window.close()`. The model is Chrome's, as on Android: per window,
  `FiberExtensionsToolbar` owns an `ExtensionsToolbarViewModel`, registered
  as the window's `ExtensionsContainer` (which `chrome.action.openPopup()` and
  the like look up), with a `FiberExtensionActionDelegate` for each
  extension's `ExtensionActionViewModel`; pins are Chrome's
  (`ToolbarActionsModel`, the `extensions.pinned_extensions` pref). Icons
  come without Chrome's badge, which the UI draws. Not yet: extensions'
  keyboard shortcuts (`commands`; Chrome's registry is views-only), site
  access requests, the disabled-extension alert, and side panels.
- **Swiping between pages** (`swipe/fiber_history_swiper.mm`,
  `ui/HistorySwipe.swift`): as in Safari, the page follows the fingers like a
  sheet of paper, over (going back) or under (forward) the page it's going to.
  AppKit tracks the fingers (`-[NSEvent trackSwipeEventWithOptions:…]`, for
  trackpads as well as the Magic Mouse), but not the landing: its call often
  goes back from a swipe slowed near the end, so on letting go the UI lands it
  if it would coast past halfway, and springs it there itself. A scroll only becomes a swipe once the page passes it up, as in
  Chrome. The page it's going to shows as it last looked
  (`swipe/page_snapshots.mm`: each page is captured as it's left, within a
  memory budget) until it draws. Chrome's arrows (`HistoryOverlayController`)
  stay in the binary only for installed web apps' windows, which still use
  Chrome's swiper.

The page gets clicks under the title bar but never moves the window (a
one-line patch to Chromium's web view, which otherwise asks to be draggable
there); the capsules do. AppKit has no public API to move the traffic lights,
so `ui/WindowFrame.swift` subclasses its private frame view the way Chrome's
own windows do (`BrowserWindowFrame`); check it still works on each macOS
release. Tabs cross the bridge as `FiberTabState` snapshots keyed by Chrome's
tab handle; there's no close button, so Command-W (Chrome's Close Tab) closes
them. The load progress bar (shown only once a load has taken half a second),
status bubble, JavaScript dialogs and context menus are Swift behind the bridge too. `make harness` runs all of it against the mock browser (right-click a page or a link for a context menu);
`swift run --package-path core/ui FiberUIHarness --tabs 20` starts with 20
tabs, `--ask-before-leaving` makes its pages ask before they're left, and
`--downloads 4` gives a quit downloads to wait for. Its pages swipe too, and
View > Simulate Swipe Back (Command-[) plays one without a trackpad. It has
made-up extensions (one pinned, with a count that climbs), and View >
Simulate Extension Install (Command-E) plays adding one.
Not yet as described:

- The rest of the window applies the snapshots it's pushed straight to its
  AppKit views; only the tab picker has a model.
- The tab picker shows `TabStripModel` directly; Fiber's own tab model comes with
  spaces.

Next: features.
