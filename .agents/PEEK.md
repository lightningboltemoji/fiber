# Fiber: peek

A link that would open a new tab opens over the current one instead, as a
peek: the new page in a card over the page it came from, whose edges show
around it, blurred. The user closes it to go back where they were, or expands
it into a tab of its own. Until then the two are one tab as far as the tab
overlay is concerned. Arc's Peek and Zen's Glance do much the same. How it
fits with the rest of the tabs is in
[Tabs and spaces](IMPLEMENTATION.md#tabs-and-spaces).

## What it does

- **Which links.** A link the page opens in a new tab (`target=_blank`, or
  `window.open()` from a click) peeks. A tab the user asks for stays a tab:
  ⌘-click, a middle click, Open Link in New Tab, the omnibar. So does a popup
  a page sizes (`window.open()` with features, as sign-in flows use), which
  is a window of its own for now. And nothing peeks:
  - from a peek: its links open tabs, with the opened-tab notice, as today,
    rather than a peek three pages deep;
  - while the window has a split, whose right page shows beside every tab:
    a peek would put three pages on screen.
- **How it looks.** The peek's page fills a card inset from the page area,
  as much on every side, rounded like the page, over the page it came from, which fills the page
  area behind it, blurred and a little darkened, so its edges bleed in around
  the card. Two round glass buttons, Close and Expand, sit at the card's
  top-right, in the margin beside it, clear of what the window puts over the
  active page (the load progress, find bar and notices, which go over the
  card, as they go over a split's side). The card grows from the pointer, on
  a spring like the downloads list's, as the page behind blurs.
- **Closing it** (Close, a click on the page behind, ⌘W, Escape, the page
  closing itself) closes its tab, and the page it came from is back as it was, with
  the keyboard, as the card goes, a snapshot of its page shrinking a little
  and fading. ⇧⌘T brings the peek back, as a peek.
- **Expanding it** makes it an ordinary tab, still active, right after the
  page it came from, as a link opened in front would be: the card grows to
  fill the page area as the page behind goes. Nothing changes for Chrome or
  extensions, which saw a tab all along.
- **The pair holds.** Going to another tab leaves the peek where it is, and
  going back to the page it came from (picking it, ⌃Tab, ⌘1–9, a tab closing)
  shows it again, over that page, at once.
- **The tab overlay shows the page it came from.** The row, its number and
  the selection are the lower tab's, and so is a pin's dot: the pair is one
  tab there, with the peek's favicon tucked into the corner of the lower
  tab's icon. The peek has no row of its own, and closing the pair's row
  closes both. The command palette lists it as a tab, since the user may look
  for it by its title, and picking it shows it peeking.
- **The page follows the peek.** What acts on a page acts on the one in
  front: the keyboard, the omnibar and the address, find, reload, back and
  forward, zoom, key passthrough, DevTools, a page's prompts, the window's
  title, and extensions' buttons.
- **Splits.** No peek opens while the window has a split. Making a split while
  the window has peeks expands them first, so the right page goes beside what
  was a peek and is a tab by then.
- **After a restart**, a peek comes back as a peek, over the page it came
  from, and active if it was.
- **Nothing else changes.** The opened-tab notice doesn't show for a peek;
  a page a peek opens shows it, with the peek's row as the tab it came from.
  A peek doesn't count as one of the window's tabs: closing it never leaves
  a New Tab page in its place.

## How it's built

### A real tab, active in Chrome

The peek is an ordinary tab in the window's `TabStripModel`, opened by Chrome
as it would be without Fiber, with the lower tab as its opener, and it's the
active tab while it shows. Fiber only marks the two as a pair and shows them
differently, as with the split. Nothing of Chrome's is replaced, so there's
nothing for `make size` to check.

- As a tab, extensions see it (`tabs.onCreated`, its `openerTabId`), session
  restore and ⇧⌘T keep it, and a page's ties to its opener (`window.opener`,
  `postMessage`, `window.close()`) work.
- Active, it's what Chrome acts on: the keyboard, ⌘F, ⌘R, DevTools, prompts,
  downloads, an extension's `activeTab`. With the lower tab active instead,
  all of that would act on a page the user can't see.
- A page kept out of the tab strip would be invisible to extensions and to
  everything Chrome keys to tabs.

### Deciding

`hooks/new_contents.h`. A tab's page opening a window (`target=_blank`, with or without `noopener`,
or `window.open()`) goes through `BrowserWebContentsDelegate::AddNewContents()`
with its disposition and whether it came from a gesture. The omnibar,
extensions, and modified clicks on ordinary links don't: they come through
`OpenURLFromTab()` or `Navigate()` directly. A patch in `AddNewContents()`
calls a Fiber hook, which marks the new page as a peek of `source` before
Chrome inserts it, if:

- the disposition is a foreground tab, and the user made a gesture
  (`user_gesture`; `chrome::AddWebContents()` passes it on as
  `original_user_gesture`, setting `user_gesture` itself to true);
- `source` is the active tab of a normal Fiber window with no split, and
  isn't a peek and has none.

`LinkOpeningFromGesture()`, which Chrome already calls just before inserting
such a tab, and which Fiber leaves empty, would need no patch. But it gets only
the disposition, which can't tell a page's link from the omnibar or a
modified click.

One case the hook can't tell either: ⇧⌘-click on a `target=_blank` link,
which the renderer turns into the same foreground tab, peeks. ⇧⌘-click on an
ordinary link comes through `OpenURLFromTab()` and stays a tab.

### The pair

`peek/tab_peek.h`.

- Both tabs keep a token they share, in `WebContents` user data that
  `hooks/tab_extra_data.h` saves in each tab's session and closed-tab history,
  as it does a tab's pin (`sessions/tab_extra_data.h` puts the two together).
  The token pairs them, not their places: the user moves tabs around, and a
  peek can't always be next to a pin's tab, which is among the pinned ones.
  Each peek gets a fresh token, which its lower tab keeps after it closes, for
  ⇧⌘T, until the next peek over it.
- A tab that arrives with a token (a restore, ⇧⌘T) pairs with the window's tab
  that shares it, if that tab has no peek. Otherwise, or with no tab to pair
  with, it's an ordinary tab and drops the token.
- Whatever separates them makes the peek an ordinary tab where it is, as if
  expanded: its lower tab closing or leaving the window, the peek leaving it
  or being pinned, or the window getting a split.
- `Peeks()` reports the pairs as they'll be once settled, and
  `SettlePeeks()` makes them so a task after each change to the tab strip,
  with the split (`FiberBrowserWindow::Settle()`).
- Moving the lower tab doesn't move its peek. Expanding puts it after the
  lower tab.

### The active tab means two things

Chrome's active tab is the peek. To the user, the tab they're on is the one
under it. Most of the window's code means Chrome's, and keeps it. What means
the user's goes through `peek/tab_peek.h`, which maps a peek to its lower tab
and back:

- the tab overlay's selected row and the pins' dots, which the window maps
  from the `FiberPeek`s sent beside the split
  (`updateOverlayTabs(_:activeTabID:)`);
- ⌃Tab and ⌘1–9 (`pins/tab_sequence.h`), which skip peeks and count from a
  peek's lower tab;
- activating a tab that has a peek, which activates the peek: at once from
  Fiber's own UI (`SelectTab()`, ⌃Tab, and `OpenPin()` as its rearranging
  settles), and a task later when Chrome or an extension activates the lower
  tab (`Settle()`), the UI being told the pair as it will be meanwhile, as it
  is a split;
- the opened-tab notice, which a peek doesn't show;
- the window's last tab (`WillCloseTabs()`, `KeepTab()`): a peek doesn't
  count as one, so closing one never leaves a New Tab page in its place.

The split already maps Chrome's tabs to what the user sees
(`split/tab_split.h`), and the peek's mapping (`UserTab()`, `ShownTab()`) sits
beside it rather than in every caller. The rest of `browser/` means Chrome's
active tab.

### Closing goes back

When a tab closes, Chrome prefers a tab it opened, then another tab its opener
opened, and only then the opener itself
(`TabStripModel::DetermineNewSelectedIndex()`). Fiber's hook
(`hooks/tab_strip_selection.h`) gets a say only after that. So closing a peek
could land on a tab it ⌘-clicked open, or on one its lower page opened
earlier. A peek always goes back to its lower tab, so a second hook ahead of
Chrome's openers (`TabToReturnToAfterClosing()`) decides for a peek, leaving
every other tab to them as before. The first, past them, passes over peeks
as it does pins' tabs.

Closing the pair's row closes the peek, then its lower tab, so ⇧⌘T brings
back the lower tab, and again, the peek over it.

### The window

`FiberPeek` (the lower tab's ID, the peek's, and while one of them is active,
both their pages' views) comes in `setPeeks:`, after `setSplit:`. The
`activeTabID` of `setTabs:activeTabID:` stays the peek's: it's what's in
front, and its prompts are the ones that show. The window already has two
panes, which trade roles without moving their pages (`setContentsView(_:)`),
since a page moved out of the window hides and shows again:

- The pane holding the peek's page is the card, above the other one, with
  `PeekBackdrop` between them (the panes' order follows their roles,
  `orderPageViews(lower:)`). The other holds the lower page across the page
  area, blurred (`ViewBlur`, which the veil uses too), and the backdrop
  darkens it and takes its clicks and scrolls, closing the peek on a click.
  The load progress and status bubble are part of the active page's pane,
  so they move with the card; the find bar, notices and prompts go over it.
- As a peek and its lower tab trade places as the active tab (opening one,
  ⇧⌘T, a tab switch landing on the lower tab), the browser sends the peeks
  before the new active page, so the UI has both pages in its panes first.
- Expanding grows the active pane to fill the page area, the lower page staying
  under it until it's covered.
- Closing makes the lower tab active. Its page is already in the other pane, so
  the panes trade roles as they do in a split. The card goes as a snapshot of
  the page (`willClosePeekWithID:snapshot:`), which the browser takes before
  it closes the tab as the user asked, since the page goes with its tab and
  can go blank as it unloads. A page that closes itself goes without one.
- A swipe between pages moves the card, not the page behind it
  (`HistorySwipe`).
- Session restore hides each tab it restores in the background after the
  window may have put its page on screen, so the window shows the pages it
  has beside the active one again (`RevealPagesBeside()`), a split's too.

Expanding is `expandPeekWithTabID:`. Closing is `closeTabWithID:`, which on a
lower tab closes its peek too. The harness's `MockBrowser` has peeks (its
`--peek`, and Peek in its controls), for working on the look.

## Open questions

- **A shortcut to expand.** It would be one pages don't get (see
  [Keyboard shortcuts](IMPLEMENTATION.md#keyboard-shortcuts)), so it can't be
  one they use, like ⌘Return (send in Slack, Gmail and GitHub). Maybe none,
  with Expand Peek in the Tab menu.
- **Back on a peek's first page** (⌘[, or a swipe) could close it, the swipe
  sliding the card away to show the page behind as if it were the page
  before. Safari closes a tab opened from a link the same way.
- **The address in the tab overlay** is the peek's, since the omnibar acts on
  the peek, while the selected row is the lower tab's. The alternative is to
  show the lower tab's address, with the omnibar still acting on the peek.
- **How the card sits:** for now, inset 50pt all round, narrowing to 20pt as
  the page area's shorter side goes from 1000pt to 480pt, as narrow as a
  window gets (`PeekLayout`), with
  the buttons centered in the right margin, shrinking from 32pt to 22pt as it
  narrows below 40pt, which leaves them about 5pt over the card's edge in the
  narrowest, and the traffic lights over the card's corner. Easiest to tune
  in the harness.
- **Escape** goes to the peek's page first. One it doesn't use closes the
  peek. One it does (a keydown listener on its way, `preventDefault()` or
  not, as `renderer/page_keys.h` has Blink count it, or Blink's own, closing
  a `<dialog>`) leaves the peek, and the window says, as for ⌘W on a lone New
  Tab page, that another closes it; one while that's up closes the peek
  without reaching the page (`FiberBrowserWindow::PreHandleKeyboardEvent()`,
  `PressAgainNotice.swift`). Not with key passthrough, which holding Escape
  ends. A page with a keydown listener for its shortcuts, as many apps have,
  takes two presses.
- **⇧⌘T after closing the pair's row** takes two presses, the tab and then
  its peek. One press for both would need closed-tab history to keep them as
  one entry, as it does a split.
- **Hover on the page behind:** the backdrop takes its clicks and scrolls, but
  whether its links still show in the status bubble as the pointer passes
  over them is untested.
- **Sign-in popups** as peeks, later. `AddNewContents()` sees them too, as
  `kNewPopup`.
