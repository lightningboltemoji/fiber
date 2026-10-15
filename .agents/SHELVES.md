# Fiber: shelves

Named lists of pages the user keeps to come back to ("Later", "Research"),
listed in the tab overlay beside the window's own tabs. Not quite spaces:
there's one set of live tabs (Home), and shelves are flat lists of kept pages,
like bookmarks that open as tabs. How it fits with the rest of the tabs is in
[Tabs and spaces](IMPLEMENTATION.md#tabs-and-spaces).

## What it does

- **The shelf bar**, under the tab overlay's panel at the left, opposite the
  downloads: a segment for Home (the window's tabs that aren't pins' or
  shelf pages'), one per shelf, and a + that adds one, ready to name. The
  overlay opens on the active tab's list. Left and Right switch lists from
  the rows, and the segments scroll across, fading at the edges, once they
  don't fit beside the downloads.
- **A shelf's list** shows its pages: open ones as their tabs are, the rest
  dimmed, their icons grey. A row's × closes the tab and keeps the page; on a
  page without a tab it's a trash can, which removes it, taking no click
  until the pointer has left it after closing the tab. Delete removes the
  selected page.
- **Dragging a row** onto a segment moves it there: a tab onto a shelf keeps
  its page there, a page onto another shelf moves it, and a page onto Home
  stops keeping it (its tab stays, or opens behind).
- **A page is kept as a pin is.** Its tab can wander; right-click offers Back
  to saved page and Replace with this page, and opening its URL (the omnibox,
  another app) goes to it. Move to and Remove are there too, and Home's tabs
  have Move to.
- **Deleting a shelf** (right-click its segment) hides it, and the + becomes
  Undo (also Edit › Undo) for five seconds before the browser hears of it, or
  until the overlay closes. Its open pages' tabs stay, as ordinary tabs.
- **The bar holds still** while the user acts on it: after a switch or a drop,
  the list grows and shrinks above it and scrolls past what fits, rather than
  pushing the bar down; closing a row holds the panel's top instead, as
  before (`PanelHold` in `TabOverlay.swift`). The overlay lays out afresh as
  it opens.
- **A list that scrolls** says how many rows are past its bottom edge, at the
  footer's left ("13 more").

## How it's kept

A shelf page is a pin with a shelf. `PinStore` keeps the shelves (ID, name)
and every pin, each with a `shelf_id` (empty for the pins themselves), in the
order their tabs take in the tab strip: the pins, then each shelf's pages in
the shelves' order. Its open tab is a Chrome-pinned tab, as a pin's is, so
everything that follows from pinning applies unchanged:

- which page a tab is persists through session restore and closed-tab
  restore (`hooks/tab_extra_data.h`);
- closing it goes back to the tab used last, ⌃Tab and ⌘1–9 skip it, and the
  window keeps a New Tab page when its last Home tab closes;
- opening its URL goes to it (`hooks/pin_urls.h`);
- extensions see it as `pinned: true`, and Chrome's Unpin Tab takes it off its
  shelf, as it unpins a pin.

`PinnedTabs` sends the UI the pins (`setPins:`) and the shelves with their
pages (`FiberShelves`), and does what the shelf actions ask
(`FiberShelvesActions`, implemented by the window's actions).

## Why not Chrome's tab groups

Tab groups model a run of open, unpinned tabs in one window. Saved tab groups
(`TabGroupSyncService`) back one with a list of URLs, but closing one of its
tabs removes that URL, closing its last deletes the group, and a group opens
all at once. Shelves need the opposite: each page open or not on its own, and
kept until removed. The service runs in Fiber regardless (Chrome's
`BrowserWindowFeatures` starts it), and saves any group an extension makes,
though Fiber's UI shows no groups.

## Not yet

Reordering shelves or pages by dragging, ⌘-number for shelves, undo for a
removed page, and finding closed pages in the command palette.
