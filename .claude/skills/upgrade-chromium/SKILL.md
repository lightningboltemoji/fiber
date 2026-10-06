---
name: upgrade-chromium
description: Upgrade Fiber to a newer Chromium release, point or milestone. Covers choosing the version, syncing, rebasing patches/chromium/ and resolving its conflicts, fixing //fiber against Chromium's changes, reviewing the release's commits against an inventory of what Fiber hooks, verifying, and committing. Use when asked to upgrade, update, bump or rebase Chromium, or to move CHROMIUM_VERSION.
---

# Upgrading Chromium

Fiber builds on a Chromium Stable release for Mac, pinned in `CHROMIUM_VERSION`.
Read `.agents/PRINCIPLES.md` and the Hooking Chromium section of
`.agents/IMPLEMENTATION.md` first: every resolution below keeps their rules.

- **Point releases** (155.0.8059.12 → 155.0.8059.26) are fixes on the same
  branch. The patches usually merge cleanly, though a fix can land beside a
  hook. Most of the time goes to the build.
- **Milestones** (155 → 156) come every four weeks, with a few conflicts,
  compile errors in `//fiber`, and new Chrome UI and features to hook or turn
  off.

`OLD` and `NEW` below are the two releases.

## 1. Choose the release

Take the newest on the Stable channel for Mac. Stable rolls out gradually, and
Fiber takes the newest release while it's still rolling out:

    curl -s 'https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions?pageSize=1'

Preview the rebase without changing the checkout (this fetches `NEW`):

    scripts/rebase_patches.sh --dry-run "$(cat CHROMIUM_VERSION)" NEW

## 2. Before syncing

- `git status` is clean, and running `make patches` leaves it clean, so
  `chromium/src` has no edits that aren't in a patch.
- For a milestone, run `make size` while `out/Default` is still built at `OLD`.
  The run after the upgrade then reports what moved since.

## 3. Sync

    echo NEW > CHROMIUM_VERSION
    make sync

Don't commit `CHROMIUM_VERSION` on its own. `make sync` reads the release the
patches were made against from the committed one, so the new version goes in
the same commit as the rebased patches.

`make sync` prints `fetching <dependency>` for each dependency that moved, and
fetches only those commits, so a point release syncs in minutes. If gclient
reports `STALL DETECTED`, it has fallen back to fetching a repository's whole
history (see `scripts/sync_chromium.sh`): stop it and find out why.

When the patches don't apply to `NEW` as they are, `make sync` rebases them
with `scripts/rebase_patches.sh`. Each patched file becomes a three-way merge
of `OLD`, `NEW`, and `OLD` with its patch. When every file merges cleanly, the
script rewrites the patches. Otherwise it lists what needs you:

- **Conflicts:** the file has conflict markers. `NEW`'s lines come first,
  then `||||||| OLD`'s, then `=======` Fiber's, ending at `>>>>>>> Fiber`.
- **Deleted upstream, or moved and rewritten:** the script wrote nothing for
  these. The old patch in `patches/chromium/` is all you have.
- **Moved upstream:** the patch followed the file. `make patches` renames the
  patch.
- **Already upstream:** the file now reads as the patch had it, so its patch
  goes away.

Until `make patches` saves the rebase, `make build` and `make sync` refuse to
run. To start over, `scripts/rebase_patches.sh --abort` discards the rebase,
including your resolutions, and then `make sync` runs it again.

## 4. Resolve

For each file, see what upstream did (`git -C chromium/src diff OLD NEW --
<file>`), then apply the patch's intent to `NEW`'s code. Each patch keeps its
`// Fiber:` comment (`# Fiber:` in GN) and has no logic of its own. A patch
is one of three kinds:

- **A hook** calls into `fiber::`. Keep it where Chrome now makes the same
  decision. If the decision moved (a function was split, a factory was
  added), follow it.
- **A cut** removes a registration, source file or pak so the linker drops
  it. Keep it removed. If upstream added something next to it, decide whether
  the addition belongs to the surface Fiber cut. If it does, cut it too, under
  the same comment. If you can't tell, keep it and flag it in your summary.
- **A relaxation** loosens an assumption of Chrome's views code. Check that the
  assumption still exists.

If a file is gone, find where its code went (`git -C chromium/src grep
<symbol> NEW`) and make the edit there. If Chromium itself removed something a
cut took out, drop the cut.

The files under `third_party/ffmpeg/chromium/config/`, and
`ffmpeg_generated.gni`, are generated. Their patches add the ADTS demuxer and
the AAC parser (`.agents/MEDIA.md`). If Chromium rolled ffmpeg, add those same
entries to the new files rather than merging them line by line. Files in the
nested repositories (ffmpeg, `third_party/devtools-frontend/src`) otherwise
resolve like any other.

Then run `make patches`, which refuses while conflict markers remain. Review
`git status patches/` and `git diff patches/`. You should be able to explain
every added or removed patch as a move or a dropped patch, and every patch you
resolved should read as you meant it.

## 5. Build

    make build

A new release rebuilds nearly everything, which takes hours for a milestone.
Errors in `//fiber` come from changes to Chromium's API. Fix them the way
Chrome's own callers changed in the same release (`git -C chromium/src grep`).
A new pure virtual method in an interface Fiber implements (`BrowserWindow`,
`LocationBar`…) needs either a real implementation or one that fails safe:
it cancels or denies, and never falls back to views. Fix an error in a patched
Chromium file there, then run `make patches`.

If the user leaves the build to CI, skip this step and the checks in step 7
that need a build, and say which ones you skipped. Note that the local
`out/Default` is then stale, and its next `make build` rebuilds most of
Chromium.

## 6. Review the release against what Fiber depends on

The rebase and the compiler only see the lines Fiber patches and the APIs it
calls. A release can also move a decision Fiber hooks to somewhere it doesn't,
or add something new of a kind Fiber replaces, cuts or turns off. Rather than
check a fixed list, take inventory of what Fiber depends on, then read the
release's commits against it.

**Take inventory** from the source, not from memory or a past upgrade: every
hunk in `patches/chromium/` (its `Fiber:` comment says why), `core/browser/`
(the Chrome interfaces it implements, the factories and observers it uses, and
`hooks/`, with its feature and pref overrides), and the docs
(`IMPLEMENTATION.md`'s Features and what has no replacement yet, and
`MEDIA.md`). Write two lists to a scratch file:

- **Touch points:** each place in Chrome that Fiber hooks, cuts, relaxes or
  relies on, as a file and symbol, with what Fiber does there.
- **Kinds:** what the touch points have in common. These are the kinds of
  Chrome behavior Fiber intervenes in, put generally enough to recognize a new
  one: "views UI that a page, command or extension can open", "requests to
  Google the user didn't ask for", "decoding a patent-pool codec".

Split the reading among subagents working in parallel, each writing its part
to the scratch directory:
- the patches,
- `core/browser/` in two halves,
- `hooks/` with `media/`, `renderer/`, `branding/` and the docs.

This is the one time all of Fiber is read at once, so also report anything
that contradicts the docs or `PRINCIPLES.md`, even where it has nothing to do
with the release.

Write the touch points' files to a watch file, one per line, with the
Chromium headers `core/` includes:

    git grep -hoE '#include "[^"]+\.h"' -- core | sed 's/#include "//; s/"$//' | grep -v '^fiber/' | sort -u

**List the commits** between the releases that touch code Fiber builds on Mac,
in batches by area:

    .claude/skills/upgrade-chromium/changes.py OLD NEW <dir> --watch <watch file>

A `*` marks a commit that touches a file Fiber patches or watches. A point
release is a single batch of a few hundred commits; a milestone is about a
dozen batches.

**Triage** each batch against the inventory and `.agents/PRINCIPLES.md`. For
a milestone, give each batch to its own subagent, in parallel. Flag:

- any marked commit whose change could move or bypass a touch point, or change
  what Fiber relies on there;
- any commit that adds or turns on something of a kind in the inventory;
- anything else that would break a rule in `PRINCIPLES.md` or `MEDIA.md`.

When a subject doesn't say enough, read the commit's message and diff:
`changes.py --show <hash> --watch <watch file>` shows only the hunks in watched
files, then names the commit's other files. Each flag gives the commit, what it changes, the
touch point or kind it affects, and why.

**Investigate** each flag in the new tree, and decide what it needs: a hook, a
cut, a feature or pref turned off, a fail-safe, or nothing. Make the change,
and keep the decision for the commit message (step 8). If a flag is of a kind
the docs don't describe yet, add it to `IMPLEMENTATION.md`.

## 7. Verify

- `make size`: what Fiber cut stays cut. `chrome/browser/ui/views` and the New
  Tab page's directories mustn't grow back. For media, check the decoders
  `.agents/MEDIA.md` lists as dead-stripped.
- Launch the dev build as described under The real app in
  `.agents/TESTING.md`. It should open a window and load a page with no crash
  or DCHECK on stderr.
- Run the media tests (`tests/media/README.md`).
- Ask the user to try the parts you can't drive: tabs, the tab overlay and
  pins, the omnibar, the command palette, the find bar, a JavaScript dialog, a
  permission prompt, installing an extension and opening its popup, docked
  DevTools, Incognito, the profile switcher, Chrome's pages (`fiber://settings`,
  history, downloads, extensions), and anything step 6 turned up.

## 8. Commit

When the user asks, make one commit, `chromium NEW`, with `CHROMIUM_VERSION`,
`patches/` and `core/` in it. In the message, record the decisions from steps
4 and 6 that the diff doesn't make plain: what was newly cut or turned off,
and what was kept because you weren't sure.

The app's version picks up `NEW` on its own (`core/branding/version.gni`).
Bumping `core/branding/VERSION` and tagging a release are the user's decisions.
A push to `main` makes CI sync and rebuild `out/Release` from scratch, which
takes hours.

When an upgrade teaches you something this skill doesn't cover, add it here.
