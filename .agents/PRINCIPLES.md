# Fiber: principles

Fiber is a Chromium-based browser for macOS with its own native UI. These are
the rules the rest follows from. How it's built is in
[IMPLEMENTATION.md](IMPLEMENTATION.md).

- **Chrome is the engine and the model.** Every Fiber window is a Chrome
  `Browser`, so anything in Chrome that opens or manages windows and tabs (menus,
  links from other apps, session restore, extensions) lands in Fiber's UI.
- **Full extension support.** It's why we fork `//chrome` instead of embedding
  an engine, so Fiber's replacements keep working with what extensions change
  (their New Tab pages, the tabs and windows APIs).
- **Replace, don't cover.** When Fiber replaces a Chrome surface, Chrome's
  version stops existing: it doesn't load, run or render behind Fiber's. Hook
  where Chrome decides what exists (a factory, a URL), not where it draws.
  A fake leaks, because everything in Chrome that knows about the hidden thing
  still acts on it.
- **Replaced code leaves the binary.** Make Chrome's version unreachable,
  rather than hooking in ahead of it and falling through, so the linker drops
  it. Check with `make size`; don't assume.
- **You should never see Chromium's UI.** A Chrome surface without a native
  replacement yet fails safe (cancels or denies, never grants) instead of
  falling back to views. The exception is Chrome's in-tab pages
  (`chrome://settings`, history, downloads, extensions), which stay.
- **All visible UI is Swift.** AppKit for the window shell and anything that
  needs precise control, SwiftUI for the rest.
- **Keep the Chromium diff small.** Patches are hooks or cuts; the logic lives
  in `//fiber`. We rebase onto each Chromium stable release.
- **Fix the pattern, not the symptom.** It's early. If something needs a
  workaround to behave, question the approach before adding the workaround.
- **macOS 26 and later only.**
