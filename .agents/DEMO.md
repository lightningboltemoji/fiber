# Fiber: the demo video

How the demo videos are made, so they can be made again whenever the UI
changes. A tape says what happens in Fiber, the director plays it on the real
app and records the take, and the studio cuts takes into a video with a
moving camera. The camera keys off markers the tape leaves, not off pixels, so
after a UI change a new take and a new render are all it takes.

```
demo/
  tapes/      what happens, a command a line (readme.tape)
  director/   plays a tape on Fiber and records the take (Swift)
  sites/      the made-up web the tapes browse, a folder per host
  takes/      recorded takes (not tracked)
  studio/     cuts takes into videos (Remotion); src/cuts/ has one per video
```

```sh
make demo                 # record demo/tapes/readme.tape, then render demo/studio/out/readme.mp4
make demo-take TAPE=…     # just record (APP=… for another build than out/Release)
make demo-render CUT=…    # just render (CRF=… for a smaller file; 18 by default)
make demo-studio          # preview the cuts in a browser, to tune the camera
```

## Recording a take

A take takes over the Mac while it records. The director brings Fiber to the
front through AX and sends real input, posted where the hardware's goes, so
Fiber can't tell it from a person's (hover, key bindings and hold-to-quit all
behave as they do for one). It needs:

- **Fiber frontmost the whole time.** An inactive window dims its glass, so a
  step that finds Fiber in the background stops the take. Moving the mouse
  or pressing a key stops it too: the director's events carry a tag, and
  anything without it is a person's.
- **No window manager.** One that tiles or snaps windows fights the director
  over the window's frame; the director gives up after a few tries rather
  than flicker.
- **Accessibility and Screen Recording** for the terminal it runs from.

Each take starts from nothing in `demo/takes/<tape>/`:

- **The profile.** `Visit` pages load in a launch of their own, for history,
  which quits as the Dock's Quit does: a SIGTERM exits without writing
  history. `Pin`s go into `Preferences` (`fiber.pins`), each with its site's
  `favicon.svg` as its icon.
- **The sites** are served from `demo/sites` on localhost, over HTTP and
  HTTPS, and `--host-resolver-rules` sends every host there, so a take never
  touches the network. The certificate is made for the take and trusted by its
  public key (`--ignore-certificate-errors-spki-list`), as in Chrome's Web
  Page Replay. `.app` and `.dev` are on Chrome's HTTPS-only list, so tapes
  use `https://`.
- **The recording** is ScreenCaptureKit's, of the window alone without its
  shadow, at its pixel size: `take.mov` (HEVC, only the frames that changed,
  each at its host time), `window.png` (the window as the take starts, whose
  transparent corners the studio masks with) and `timeline.json` (markers,
  steps, keys and the pointer, in seconds from the first frame and window
  points). The pointer is in the picture unless the tape says `Cursor hidden`.

The app is `out/Release`'s by default: DCHECKs off, as people get it.

## Tapes

Settings come first; then the steps, one to a line. Steps before `Record`
set the scene and aren't recorded. `#` starts a comment.

| Setting | |
|---|---|
| `Window 1600x1000` | The window's size in points, centered on the main display |
| `Visit URL…` | Pages in history before the take |
| `Pin URL "title"` | A pin |
| `Open URL…` | The window's tabs as Fiber starts; the first is active |
| `Pointer @X,Y` | Where the pointer waits as the take starts (outside the window is fine) |
| `Cursor hidden` | Leaves the pointer out of the picture |
| `Seed N` | Varies the typing rhythm and the pointer's paths, which are otherwise the same every take |
| `Fps N` | The most frames a second to record (60) |
| `App PATH` | Another build, from the repo's root |

| Step | |
|---|---|
| `Sleep 1.2s` | |
| `Type "text" [90ms]` | Types a key at a time, about that far apart |
| `Key cmd+s [down …]` | Presses each in turn |
| `Hold cmd+q 2s` | |
| `Move TARGET [700ms]` | Moves the pointer to its middle along a slight arc |
| `Click [TARGET]` | Moves there first if given |
| `Scroll 600 [1.2s]` | Scrolls the page under the pointer, down for positive, as a trackpad does |
| `Wait title "text"`, `Wait TARGET`, `Wait gone TARGET`, `Wait load` | Each takes a timeout, 10s by default |
| `Mark NAME [TARGET]` | Notes the time, and where TARGET is (the window if none), for the camera |
| `Tree` | Writes the window's accessibility tree to `tree-<line>.txt` in the take |
| `Record` | Starts recording |

A target is `window`, a point or rect in window points from the top left
(`@X,Y`, `@X,Y,W,H`), an element of Fiber's UI by role and a label its
title, description or value contains (`AXButton "Hum"`, `AXButton "Allow" #3`
for the third), an element of the active page by CSS selector
(`page "#nearby"`, found over DevTools), or one of the names for Fiber's UI:
`omnibar`, `palette`, `results` (their suggestions), `picker`, `overlay` (the
tab overlay's tabs) and `pins`. To find what to target, put `Tree` where it's
needed and play the tape with `--rehearse`, which records nothing:

```sh
swift run --package-path demo/director director demo/tapes/readme.tape --rehearse
```

Searches of the tree skip pages' contents (`AXWebArea`), which Chrome makes
accessible once AX asks about the window.

## The studio

A cut is a Remotion composition in `demo/studio/src/cuts/`, listed in
`cuts/index.ts`: the tapes whose takes it uses, its size and length, and what
it draws. Its pieces:

- **`Take`**: the take's window where the camera sees it. Shots are keyed to
  the take (seconds, a marker, or a step's start or end by its line) and
  frame the window, a marker's rect, several markers' together, or a rect, so
  that it fills `fill` of the picture, tilted in 3D. Moves ease `smooth`,
  `gentle`, `crash`, `whip`, `spring` or `linear`, and zooms go about the one
  point that stays put, so a crash zoom heads straight in. `drift` keeps
  pushing in slowly once a move settles. Fast moves are blurred in renders
  (not the preview): the window is drawn at several instants across half a
  frame and averaged.
- **`Keys`** shows the take's shortcuts as keycaps; **`Caption`**, **`Title`**
  and **`Backdrop`** are the words and what's behind the window.
- `brand.ts` takes the app icon from `core/branding/icon`, so a render uses
  the icon `make icon` last built.

A render takes about 8 seconds a second of video at 1080p60.
`smoke.tape` and its cut check the whole pipeline in a few seconds:
`make demo TAPE=smoke`. The README's video can only play
inline on GitHub from an upload: drop `out/readme.mp4` into the README's
editor on github.com and use the `user-attachments` URL it gives. A free plan
takes videos up to 10 MB, which `make demo-render CRF=25` fits.

## The sites

Each folder of `demo/sites` is a host: `wayfarer.travel/lisbon/index.html`
is `https://wayfarer.travel/lisbon/`. They're made up (brands, people, the
Lisbon trip they share, "today" being Wednesday, October 14) and work offline:
no outside requests, only macOS's own fonts, imagery in CSS and SVG, and a
`favicon.svg` each. Titles are short and distinct, as tabs show them, and
pages keep clear of the window's top center (the omnibar) and right edge (the
tab picker). Text the command palette should find has to be on the page.
