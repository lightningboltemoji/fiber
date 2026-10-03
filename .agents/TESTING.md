# Fiber: testing

How to check a UI change by eye, and how to catch UI that shows for only a
frame or two. None of it touches the keyboard or mouse, since the installed
Fiber is usually running alongside, often frontmost.

## Never send keystrokes

`osascript` keystrokes go to the frontmost app, which is often the installed
Fiber rather than the build under test, so ⌘S, ⌘T or Esc land there. Drive the
build with a temporary hook in its code instead, and remove it afterwards.

## The harness

`FiberUIHarness` runs `core/ui` against a mock browser (`make harness`). Its
launch flags, which open states like the command palette or an Incognito
window, are listed at the top of `FiberUIHarness/main.swift`.

1. `swift build --package-path core/ui --product FiberUIHarness`, then start
   the binary from `--show-bin-path` in the background, in a subshell
   (`(… &)`): started with a bare `&` from an agent's shell, it runs but never
   gets its windows.
2. Find its window with a small Swift script over `CGWindowListCopyWindowInfo`:
   owner name `FiberUIHarness`, layer 0. (JXA can't unwrap the window list.)
3. `screencapture -x -o -l <window ID>`. Crop with `CGImage.cropping(to:)` in
   Swift; `sips` crops from an unexpected origin. While the screen is locked,
   every capture fails ("could not create image from window").

- **Its controls:** a panel beside the window last used (View › Harness
  Controls, ⇧⌘H, if closed) sets that window's tabs and the profile's pins,
  shows a location prompt over its page, and plays animations slower. It
  floats (layer 3), so step 2 still finds only browser windows.
- **States without a flag** (omnibar open): a temporary hook after
  `NSApp.activate()` in `main.swift`, e.g. `openLocation(nil)`.
- **Keys and clicks:** from the same hook, made with `NSEvent.keyEvent` or
  `mouseEvent` and sent with the window's `sendEvent(_:)`, so they go through
  its real key bindings and hit testing. Post a click's mouse-up first
  (`NSApp.postEvent`), for a button's tracking loop to end on. Menu shortcuts
  don't reach a background app's menu; call their actions instead.
- **Light appearance:** pass `-NSRequiresAquaSystemAppearance YES`; the system
  is usually dark.
- **Hover** can't be driven from outside: the harness stays in the background
  while another app is frontmost, and SwiftUI only tracks hover in the active
  app, so even mouse events posted to its process do nothing. Set the hover
  state from a hook (a model's `hoveredID`). An inactive harness also dims
  glass buttons and drops prominent tints.
- **Animations:** `--slow-motion 10`, with captures about 0.45 s apart
  (`CGWindowListCreateImage` is unavailable). Open what animates from a
  delayed hook, once the window has settled.
- **Vibrant text:** sample pixels with `NSBitmapImageRep` to tell it apart
  from flat gray on glass.

## The real app

Run the dev build on a throwaway profile:

    chromium/src/out/Default/Fiber.app/Contents/MacOS/Fiber \
      --user-data-dir=<temp dir> --no-first-run --no-default-browser-check \
      --use-mock-keychain [--incognito] [url]

- GUI launches need the Bash sandbox off.
- Find its window by `kCGWindowOwnerPID`, since the installed Fiber has the
  same name, and kill only that PID. Take its largest window: Chrome also owns
  a hidden 500×500 one and several 39pt-high ones.
- Capture again a few seconds later before concluding anything: an overlay
  (the profile switcher) can show after the first capture.
- **Driving it:** a temporary hook in `BrowserWindowController.init`, gated on
  a `FIBER_TEST_*` environment variable and the first window only. Run a
  Chrome command with
  `(actions as AnyObject).perform(Selector(("commandDispatch:")), with: item)`,
  where `item.tag` is its `IDC_` value, or a main menu item with
  `menu.performActionForItem(at:)`. For the tab overlay, a delayed
  `toggleTabOverlay()`.
- **Light appearance:** a temporary
  `NSApp.appearance = NSAppearance(named: .aqua)` in the same place. Don't pass
  `-NSRequiresAquaSystemAppearance YES`: Chrome opens `YES` as a URL.

## Measuring lag

Typed keys that don't show right away mean the main thread is busy.

- **A heavy profile:** a throwaway one whose `History`, `Favicons` and
  `Bookmarks` are filled in with SQLite and JSON while the build isn't
  running: 100k+ URLs, with a favicon per host, since favicons arriving drive
  most of the omnibar's updates.
- **Typing:** a temporary hook that sends key events on a timer (one every
  80 ms), logging how late each is handled, and a 4 ms repeating timer whose
  gaps are stalls.
- **Where the time goes:** `xcrun xctrace record --template 'Time Profiler'
  --attach <pid>`, then `xctrace export` its `time-profile` table and sum the
  main thread's samples by frame.
- The command palette with `--tabs 300` in a release build of the harness
  (`swift build -c release`).

## Catching a one-frame flash

Screen recordings (`screencapture -v`, 40–60 fps) can miss a window that shows
for a frame or two, and show nothing at all when another process draws its
content (an `NSRemoteView`).

- **Which window:** poll `CGWindowListCopyWindowInfo` every ~0.5 ms from a
  small Swift tool, logging every owner's windows as they come and go, with
  layer and size. It catches windows that last 12 ms.
- **Reproducing it:** some only show on the real profile (no
  `--user-data-dir`), launched through LaunchServices (`open`, as from the
  Dock). Ask before running a build on the real profile.
- **What opened it:** for one of Fiber's own windows, a temporary probe in the
  dev build: poll `NSApp.windows` on a 1 ms timer, and swizzle
  `-[NSWindow orderWindow:relativeTo:]` to log `Thread.callStackSymbols` for
  high-level windows, to a file.

A known cause: AppKit offers one-time-code AutoFill
(`NSAutoFillHeuristicController`) on a text field without a `contentType`, as
another process's popup. Give each field an explicit `contentType`; the
`NSAutoFillHeuristicControllerEnabled` default Chromium sets is gone as of
macOS 26.2.
