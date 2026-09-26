#!/usr/bin/env python3
"""Reports what Chrome's layer of Fiber costs, by source directory, and how
much of it the linker leaves out.

Relinks the //chrome library (the framework binary in out/Release, or
libchrome_dll.dylib in a component build) into a scratch directory with a
linker map, then attributes the map's symbols to the directories their objects
were compiled from: what's linked, and what -dead_strip removed. Also
attributes the resource packs to the .grd files they come from.

In a component build (out/Default), Content, Blink, V8 and //ui/views are
libraries of their own, which keep everything, so only Chrome's layer is
measured; out/Release links everything into the one framework.

Each run is saved, and the next run reports what moved since. So: run it,
make a change, rebuild, run it again.

    scripts/size.py [--out Default] [path ...]

Paths (source directories, like chrome/browser/ui/views) are reported along
with the watched ones below.
"""

import argparse
import os
import re
import shlex
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "chromium", "src")

# What Fiber replaces, or has replaced, and so expects to shrink.
WATCHED = [
    "chrome/browser/ui/views",
    "chrome/browser/ui/webui/new_tab_page",
    "chrome/browser/resources/new_tab_page",
    "fiber",
]

SOURCE_EXTENSIONS = (".cc", ".mm", ".c", ".cpp", ".m", ".S", ".s", ".swift", ".rs")
PAKS = ["resources.pak", "chrome_100_percent.pak", "chrome_200_percent.pak"]
# Moves smaller than this aren't reported.
MIN_DELTA = 4096
# Of the directory column.
WIDTH = 52


def unescape_ninja(token):
    return re.sub(r"\$(.)", r"\1", token)


def split_ninja(line):
    """Splits a ninja line into tokens on unescaped spaces, unescaping them."""
    return [unescape_ninja(t) for t in re.split(r"(?<!\$) ", line) if t]


def find_link(out):
    """The build statement that links //chrome's library: its output, its
    explicit inputs, and its variables."""
    names = ["chrome_dll.ninja", "chrome_framework_shared_library.ninja"]
    for name in names:
        path = os.path.join(out, "obj", "chrome", name)
        if not os.path.exists(path):
            continue
        with open(path) as f:
            lines = f.read().split("\n")
        for i, line in enumerate(lines):
            if not line.startswith("build ") or ": solink " not in line:
                continue
            outputs, rest = re.split(r"(?<!\$): solink ", line[len("build "):], maxsplit=1)
            inputs = re.split(r" \|\|? ", rest, maxsplit=1)[0]
            variables = {}
            for var in lines[i + 1:]:
                if not var.startswith("  "):
                    break
                key, _, value = var.strip().partition(" =")
                variables[key] = value.strip()
            return split_ninja(outputs)[0], split_ninja(inputs), variables
    sys.exit(f"no link step for //chrome in {out}; is it configured?")


def relink_with_map(out, scratch):
    """Links //chrome's library again, into `scratch`, writing a linker map.
    Returns the map's path."""
    output, inputs, variables = find_link(out)
    if not os.path.exists(os.path.join(out, output)):
        sys.exit(f"{output} isn't built; run `make build` first")
    ninja = os.path.join(SRC, "third_party", "ninja", "ninja")
    command = subprocess.run(
        [ninja, "-C", out, "-t", "commands", "-s", output],
        check=True, capture_output=True, text=True,
    ).stdout.strip()

    # The response file ninja writes for the link, and deletes after (this
    # rule's rspfile_content).
    rsp = os.path.join(scratch, "link.rsp")
    with open(rsp, "w") as f:
        f.write(" ".join(shlex.quote(i) for i in inputs))
        for key in ["frameworks", "swiftmodules", "solibs", "libs"]:
            f.write(" " + unescape_ninja(variables.get(key, "")))

    binary = os.path.join(scratch, os.path.basename(output))
    map_path = os.path.join(scratch, "link.map")
    replacements = {
        f'-o "{output}"': f'-o "{binary}" -Wl,-map,"{map_path}"',
        f'"@{output}.rsp"': f'"@{rsp}"',
        f'tocname,"{output}.TOC"': f'tocname,"{binary}.TOC"',
    }
    for old, new in replacements.items():
        if command.count(old) != 1:
            sys.exit(f"unexpected link command for {output}: no {old}")
        command = command.replace(old, new)
    print(f"linking {output} with a map…", file=sys.stderr)
    subprocess.run(command, shell=True, cwd=out, check=True)
    return os.path.basename(output), map_path


class SourceDirs:
    """Maps object files to the directories of the sources they were compiled
    from. GN puts a target's objects in obj/<dir>/<target>/<path in dir>.o."""

    def __init__(self, out):
        self.roots = [SRC, os.path.join(out, "gen")]
        self.listings = {}

    def _has_source(self, directory, stem):
        for root in self.roots:
            path = os.path.join(root, directory)
            if path not in self.listings:
                try:
                    self.listings[path] = set(os.listdir(path))
                except OSError:
                    self.listings[path] = set()
            if any(stem + ext in self.listings[path] for ext in SOURCE_EXTENSIONS):
                return True
        return False

    def __call__(self, obj):
        if obj.startswith("local_rustc_sysroot/"):
            return "(rust std)"
        # An archive (a static library, or a Rust library) member.
        archive = re.match(r"(.*)\.(a|rlib)\(.*\)$", obj)
        if archive:
            obj = archive.group(1)
            return os.path.dirname(obj[len("obj/"):]) if obj.startswith("obj/") else obj
        if not obj.startswith("obj/"):
            return f"({obj})"
        parts = obj[len("obj/"):].split("/")
        stem = os.path.splitext(parts[-1])[0]
        for k in range(len(parts) - 2, 0, -1):
            directory = "/".join(parts[:k] + parts[k + 1:-1])
            if self._has_source(directory, stem):
                return directory
        return "/".join(parts[:-2])


def read_map(map_path, source_dir):
    """Sizes by source directory: {dir: [linked, stripped]}."""
    files = {}
    sizes = {}
    section = None
    with open(map_path, errors="replace") as f:
        for line in f:
            if line.startswith("#"):
                # Section names end in a colon; the lines after them name
                # the columns.
                if line.rstrip().endswith(":"):
                    section = line
                continue
            if section.startswith("# Object files"):
                index, _, path = line.partition("]")
                files[int(index.strip("[ "))] = source_dir(path.strip())
            elif section.startswith("# Symbols") or section.startswith("# Dead Stripped"):
                fields = line.split("\t")
                size = int(fields[1], 16)
                index = int(fields[2][1:fields[2].index("]")])
                entry = sizes.setdefault(files[index], [0, 0])
                entry[0 if section.startswith("# Symbols") else 1] += size
    return sizes


def read_paks(out):
    """Resource pack sizes by the directory of the .grd each resource comes
    from: {dir: [size, 0]}."""
    sizes = {}
    for name in PAKS:
        pak = os.path.join(out, "gen", "repack", name)
        grds = {}
        with open(pak + ".info") as f:
            for line in f:
                _, resource_id, grd = line.strip().split(",")
                grds[int(resource_id)] = grd
        with open(pak, "rb") as f:
            data = f.read()
        version, _, count, _ = struct.unpack_from("<IB3xHH", data)
        if version != 5:
            sys.exit(f"{name}: unsupported pak version {version}")
        entries = [struct.unpack_from("<HI", data, 12 + 6 * i) for i in range(count + 1)]
        for (resource_id, start), (_, end) in zip(entries, entries[1:]):
            grd = grds.get(resource_id, "(unknown)")
            grd = re.sub(r"^(\.\./\.\./|gen/)", "", grd)
            entry = sizes.setdefault(os.path.dirname(grd), [0, 0])
            entry[0] += end - start
    return sizes


def total(sizes, prefix):
    linked = stripped = 0
    for directory, (a, b) in sizes.items():
        if not prefix or directory == prefix or directory.startswith(prefix + "/"):
            linked += a
            stripped += b
    return linked, stripped


def by_depth(sizes, depth):
    grouped = {}
    for directory, (a, b) in sizes.items():
        key = "/".join(directory.split("/")[:depth])
        entry = grouped.setdefault(key, [0, 0])
        entry[0] += a
        entry[1] += b
    return grouped


def mb(size, sign=""):
    """A size in MB, or in KB under 0.1 MB."""
    if abs(size) < 1e5:
        return f"{size / 1e3:{sign}8.0f} KB"
    return f"{size / 1e6:{sign}8.2f} MB"


def signed_mb(size):
    return mb(size, sign="+")


def load(path):
    sizes = {}
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                directory, a, b = line.rstrip("\n").split("\t")
                sizes[directory] = [int(a), int(b)]
    return sizes


def save(path, sizes):
    with open(path, "w") as f:
        for directory, (a, b) in sorted(sizes.items()):
            f.write(f"{directory}\t{a}\t{b}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", default="Default")
    parser.add_argument("--depth", type=int, default=3)
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()

    out = os.path.join(SRC, "out", args.out)
    scratch = os.path.join(out, "size")
    os.makedirs(scratch, exist_ok=True)

    binary, map_path = relink_with_map(out, scratch)
    code = read_map(map_path, SourceDirs(out))
    resources = read_paks(out)

    code_path = os.path.join(scratch, "code.tsv")
    resources_path = os.path.join(scratch, "resources.tsv")
    previous_code = load(code_path)
    previous_resources = load(resources_path)
    save(code_path, code)
    save(resources_path, resources)

    linked, stripped = total(code, "")
    print(f"\n{binary} (out/{args.out}): {mb(linked).strip()} of code and data "
          f"linked, {mb(stripped).strip()} dead-stripped")
    if args.out != "Release":
        print("  Chrome's layer only: in a component build, Content, Blink, V8 and\n"
              "  //ui/views are libraries of their own, which keep everything.")
    print(f"Resource packs ({', '.join(PAKS)}): {mb(total(resources, '')[0]).strip()}")

    def row(path, linked, stripped, resource):
        print(f"  {path:{WIDTH}}{mb(linked)}{mb(stripped)}{mb(resource)}")

    print(f"\n{'':{WIDTH + 2}}{'linked':>11}{'stripped':>11}{'resources':>11}")
    print("Watched")
    for path in WATCHED + args.paths:
        row(path, *total(code, path), total(resources, path)[0])

    print(f"Largest (depth {args.depth})")
    grouped = by_depth(code, args.depth)
    grouped_resources = by_depth(resources, args.depth)
    for key in grouped_resources:
        grouped.setdefault(key, [0, 0])
    largest = sorted(
        grouped.items(),
        key=lambda e: -(e[1][0] + grouped_resources.get(e[0], [0])[0]))
    for directory, (a, b) in largest[:args.top]:
        row(directory, a, b, grouped_resources.get(directory, [0])[0])

    for label, before, after in [
        ("Code", previous_code, code),
        ("Resources", previous_resources, resources),
    ]:
        if not before:
            continue
        moves = []
        for directory in set(before) | set(after):
            delta = after.get(directory, [0, 0])[0] - before.get(directory, [0, 0])[0]
            if abs(delta) >= MIN_DELTA:
                moves.append((delta, directory))
        if not moves:
            print(f"\n{label}: nothing moved since the last run")
            continue
        net = total(after, "")[0] - total(before, "")[0]
        print(f"\n{label} since the last run: {signed_mb(net).strip()}")
        for delta, directory in sorted(moves, key=lambda m: -abs(m[0]))[:args.top]:
            print(f"  {directory:{WIDTH}}{signed_mb(delta)}")


if __name__ == "__main__":
    main()
