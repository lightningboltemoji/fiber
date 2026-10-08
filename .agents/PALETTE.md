# Fiber: command palette

How the command palette (Command-P) finds tabs and commands: what it lists,
how it ranks them, and where the pieces are. The omnibar (Command-L) is
separate: it's Chrome's omnibox, scoped to the tab. The palette works across
the browser.

## What it does

- **Before the user types**, it lists every tab in the profile's windows:
  the current tab first, then the rest, most recently used first. The second
  row starts selected, so Command-P then Return goes back to the last tab.
- **As they type**, it lists tabs and commands whose names (titles, URLs)
  match. Below them, under "Found in pages", it lists tabs whose page text
  has the query, each with the words around the match.
- **Return** switches to a tab (bringing its window forward), or switches to
  it and selects the match in the page, or runs a command.
- **Commands** are New Tab, Print… and Key Passthrough (`FiberCommand`,
  which `browser/` maps to Chrome's command IDs, but for Key Passthrough,
  which is Fiber's own).
- **Windows to bring back**, as they type: the windows the user closed
  (Chrome's recently closed) and earlier sessions (see
  [Sessions](IMPLEMENTATION.md#sessions)), each listed once. By the page of
  it that matched, beside "Closed window" or "Earlier session", but not by
  pages open now, since the open tab is the one wanted; or as a whole, named
  by its pages, for words like "closed window" and "previous session".
  Return reopens a closed window on that page, or a session's windows.
- **Opening it**: View > Command Palette (Command-P), which the window
  handles (`FiberWindowMenuActions`). Pages never see Command-P, unless their
  tab has key passthrough (see [IMPLEMENTATION.md](IMPLEMENTATION.md#keyboard-shortcuts)).
  Chrome's Search Tabs command opens the palette too.
- **Print** moves to Option-Command-P and goes straight to macOS's print
  panel (`kPrintPreviewDisabled` defaults to true in
  `hooks/profile_pref_defaults.cc`), so Print Using System Dialog is gone.

## Pieces

| | Where | Does |
|---|---|---|
| `browser/` | `palette/tab_index_source.mm` | One per profile, made with its first window: sends the tabs of all its windows to the index, coalesced, and keeps a `PageText` for each. Sends the windows it can bring back too, and brings them back. |
| | `palette/page_text.cc` | Reads a tab's page text (`content_extraction::GetInnerText`): a second after it loads, two after it changes its URL itself, when the user leaves the tab, and when the palette opens on it. Finds a match in the page with Chrome's find in page, then stops, keeping the selection. |
| bridge | `FiberTabIndex.h`, `FiberRestorable.h`, `FiberWindow.h` | The index the profile's windows share, and what it can bring back; the window's palette actions. |
| `ui/` | `TabIndex.swift` | The index: the tabs, their text in a `PageTextIndex`, and the windows it can bring back. |
| | `PaletteSearch.swift`, `TextMatching.swift` | Matching names, and ranking. |
| | `PageTextIndex.swift` | Pages' text: passages, an index by word, BM25, snippets. |
| | `CommandPalette.swift`, `PaletteResultList.swift` | The palette and its rows. |
| | `PaletteView.swift` | The glass panel, field and footer, shared with the omnibar. |

Page text is untrusted, and Chromium's rule is not to parse it in the
browser process in an unsafe language. So `browser/` only cuts it to 64 KiB
and passes it on; Swift, which is memory safe, does everything else. That
also means all of the ranking runs in the harness and in tests, without
Chromium.

Page text lives in memory only. It's dropped when the tab navigates away from
the page (until the next page is read) or closes. A tab restored from a
session but not yet loaded has none.

## Ranking

The query is split into words, case, accents and width folded away (so
"cafe" finds "Café"). The last word is "open" while the user is still typing
it, with no space after it.

### Names

Titles, URLs and commands are short, and typed a few letters at a time, so
they're matched like a fuzzy finder, word by word. Each word of the query
takes its best match in any field:

| Match | Quality |
|---|---|
| Exact word | 1.0 |
| Start of a word | 0.9 |
| Start of a camel case part ("hub" in GitHub) | 0.8 |
| Inside a word, in a script without spaces (Chinese, Japanese, Korean) | 0.8 |
| Starts of consecutive words or parts ("nyt", "gh", "newyork") | 0.75 |
| One typo, or two in words of 7 letters or more | 0.65, 0.5 |
| Inside a word, 3 letters or more | 0.4 |

Typos are optimal string alignment distance (a swap of neighbors counts as
one), and must keep the first letter (or swap it with the second). An open
word matches the start of a longer word with typos, but can't drop letters
below five: "rmen" isn't allowed to mean "ren…".

Fields weigh 1.0 (title, command name), 0.9 (host), 0.85 (a command's other
names, like "PDF" for Print), 0.6 (path), 0.5 (scheme, shown for non-web
pages) and 0.3 (top level domain). "www." and the query and fragment don't
count.

A result's score is the mean of its words' (quality × weight), plus:

- 0.1 if the first word matches the first word of the title or site;
- 0.1 if the words match in order, side by side, in one field (0.05 apart);
- 0.1 × the share of the title's words matched ("Print" beats "Print CSS");
- up to 0.05 for recency, halving every 6 hours (commands get 0.03), as of
  when a window closed or a session ended;
- −0.05 for the current tab, which is rarely the one wanted;
- −0.1 for a closed window or earlier session, below an open tab.

Commands need every word to match at least as well as two typos; a few
letters inside a word don't make one. So do the words that find a closed
window or session by what it is.

### Page text

Pages are long, so their text is searched with BM25, a classic ranking
function for documents (k1 = 1.2, b = 0.75), over passages rather than whole
pages:

- **Passages** are the page's lines (inner text has a line per block),
  gathered up to about 100 words; longer lines are split. A passage is small
  enough that words in the same one are near each other, and the best one is
  the snippet.
- **Each word of the query expands** to the indexed words it could mean:
  itself (1.0), words it starts (0.9 while open, 0.7 after, as a crude stem),
  words containing it in scripts without spaces (0.8), and likely typos
  (0.65, 0.5). Typos are only tried when the pages have the word as typed,
  or words it starts, in fewer than three passages: most words that look
  like typos of others aren't.
- **A tab is listed** if one passage has every query word its name didn't
  match. Words its name did match count half there. The tab's score is its
  best passage's, times up to 1.3 for query words side by side in it, times
  up to 1.5 for how well its name matched.
- **The snippet** is about 28 words from that passage around the most
  matches, from the start of the line if it's near, with line breaks shown
  as " · ".
- **Selecting the match** finds the run of matched words in the snippet with
  the most of the query's, grown by words on the same line until the page
  has it once.

### Tiers

Results are sorted by tier, then score:

1. Names that match every word strongly (quality 0.75 or better somewhere).
2. Names that match every word, but some only weakly (typos, inside words).
3. Found in pages.

Tiers keep the scores apart: fuzzy name scores and BM25 scores mean
different things, and never have to be weighed against each other. They
also keep the list steady as the user types. Names are ranked on the main
thread at once; page text is searched on a queue of its own and its results
arrive after, always below, so nothing above them moves.

## Tuning

`PaletteSearchTests` in `core/ui/Tests` has queries and what should come
first for them, against a realistic set of tabs; add one whenever a query
ranks wrong. `swift test --package-path core/ui` runs them.
`make harness` runs the palette against made-up sites with page text
(`FiberUIHarness/MockPages.swift`): `--tabs 20` opens them all, and
`--palette QUERY` opens the palette with a query typed.

## Not yet

- Remembering which result the user picked for a query, and ranking it
  higher next time, as Chrome's shortcuts provider does.
- Closing tabs from the list; more commands, perhaps from the main menu.
- Chrome's Tab Search page is cut (its WebUI config and paks), but its
  interface binders aren't (`chrome_browser_interface_binders_webui_parts_desktop.cc`),
  which keep its handlers in the binary. Print preview is off but still built
  in (the pref can turn it back on); cutting it is
  `enable_print_preview = false`. Check both with `make size`.
