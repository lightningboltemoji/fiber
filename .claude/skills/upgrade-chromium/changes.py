#!/usr/bin/env python3
"""Lists the Chromium commits between two releases that touch code Fiber
builds, in batches to review, from Gitiles: the checkout has no history.

    changes.py OLD NEW OUT_DIR [--watch FILE]
    changes.py --show COMMIT [--watch FILE]

Each line of OUT_DIR/batch-NN.tsv is a commit: its hash, subject and paths.
Batches group commits by area. A `*` before the hash marks a commit that
touches a file Fiber patches, or one FILE lists (a path or directory per
line). --show prints a commit's message and diff, only the watched files'
with --watch.
"""

import argparse
import base64
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GITILES = "https://chromium.googlesource.com/chromium/src"
BATCH = 450
SHOWN_PATHS = 6

# Paths that never build into Fiber (other platforms, tests, translations,
# docs, tooling, third-party code it doesn't patch), and ones whose changes are
# only bookkeeping (version bumps, PGO profiles, string screenshots).
OUT_OF_SCOPE = re.compile(r"""
    (^|/)(android|ios|chromeos|ash|fuchsia|win|linux|lacros|ozone|wayland|x11)/
  | _(android|ios|chromeos|ash|fuchsia|win|linux)\.
  | ^(android_webview|clank|infra|docs|tools|testing)/
  | (^|/)(test|tests|test_support|testdata|test_data|fuzzers?|web_tests)/
  | _(unit|browser|interactive_ui|api|perf)?tests?\.
  | _test_(util|utils|helper|support)\.
  | \.test\.
  | \.(xtb|md)$|\.pgo\.txt$|\.png\.sha1$
  | (^|/)(OWNERS|DIR_METADATA|DEPS)$|^chrome/VERSION$|^internal$
  | ^third_party/(?!blink/|ffmpeg|devtools-frontend)
""", re.X)


def get(url):
    with urllib.request.urlopen(url) as response:
        return response.read()


def gitiles_json(url):
    return json.loads(get(url)[len(")]}'"):])


def log(old, new):
    base = f"{GITILES}/+log/{old}..{new}?format=JSON&n=500&name-status=1"
    url = base
    while url:
        page = gitiles_json(url)
        for commit in page["log"]:
            paths = {p for change in commit.get("tree_diff", [])
                     for p in (change.get("old_path"), change.get("new_path"))
                     if p and p != "/dev/null"}
            yield commit["commit"], commit["message"].splitlines()[0], sorted(paths)
        url = f"{base}&s={page['next']}" if "next" in page else None


def watched_paths(watch_file):
    paths = set()
    patches = os.path.join(ROOT, "patches", "chromium")
    for name in os.listdir(patches):
        with open(os.path.join(patches, name)) as f:
            match = re.match(r"diff --git a/(\S+) ", f.readline())
            if match:
                paths.add(match.group(1))
    if watch_file:
        with open(watch_file) as f:
            paths.update(line.strip().rstrip("/") for line in f if line.strip())
    return paths | {stem(p) for p in paths}


# A watched file also watches the files beside it that differ only in
# extension, so foo.h covers foo.cc and foo.mm.
def stem(path):
    return os.path.splitext(path)[0]


def is_watched(path, watched):
    parts = path.split("/")
    return stem(path) in watched or any(
        "/".join(parts[:i]) in watched for i in range(1, len(parts) + 1))


def write_batches(old, new, out_dir, watch_file):
    watched = watched_paths(watch_file)
    commits = []
    total = 0
    for sha, subject, paths in log(old, new):
        total += 1
        paths = [p for p in paths if not OUT_OF_SCOPE.search(p)]
        if paths:
            commits.append((sha[:12], subject, paths,
                            any(is_watched(p, watched) for p in paths)))
    # By area, so each batch is a coherent part of Chromium.
    commits.sort(key=lambda c: (c[2][0].split("/")[:3], c[2][0]))
    os.makedirs(out_dir, exist_ok=True)
    batches = [commits[i:i + BATCH] for i in range(0, len(commits), BATCH)]
    for n, batch in enumerate(batches, 1):
        with open(os.path.join(out_dir, f"batch-{n:02}.tsv"), "w") as f:
            for sha, subject, paths, mark in batch:
                shown = " ".join(paths[:SHOWN_PATHS])
                if len(paths) > SHOWN_PATHS:
                    shown += f" (+{len(paths) - SHOWN_PATHS})"
                f.write(f"{'*' if mark else ' '}{sha}\t{subject}\t{shown}\n")
    marked = sum(c[3] for c in commits)
    print(f"{total} commits from {old} to {new}; {len(commits)} touch code Fiber "
          f"builds, {marked} of them a file it patches or watches; "
          f"{len(batches)} batches in {out_dir}")


def show(sha, watch_file):
    commit = gitiles_json(f"{GITILES}/+/{sha}?format=JSON")
    sys.stdout.write(commit["message"] + "\n")
    diff = base64.b64decode(get(f"{GITILES}/+/{sha}%5E%21/?format=TEXT")).decode(
        "utf-8", "replace")
    if not watch_file:
        sys.stdout.write(diff)
        return
    watched = watched_paths(watch_file)
    others = []
    for chunk in re.split(r"^(?=diff --git )", diff, flags=re.M):
        match = re.match(r"diff --git a/(\S+) ", chunk)
        if not match:
            continue
        if is_watched(match.group(1), watched):
            sys.stdout.write(chunk)
        else:
            others.append(match.group(1))
    if others:
        sys.stdout.write("\nAlso changed, not watched: " + " ".join(others) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--show", metavar="COMMIT")
    parser.add_argument("--watch", metavar="FILE")
    parser.add_argument("range", nargs="*", metavar="OLD NEW OUT_DIR")
    args = parser.parse_args()
    if args.show:
        show(args.show, args.watch)
    elif len(args.range) == 3:
        write_batches(*args.range, args.watch)
    else:
        parser.error("give OLD NEW OUT_DIR, or --show COMMIT")


if __name__ == "__main__":
    main()
