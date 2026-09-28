#!/usr/bin/env python3
"""Puts Fiber's version on an Info.plist in place of Chromium's.

CFBundleShortVersionString (what Finder shows) gets the full version, Fiber's
with the Chromium release in it; CFBundleVersion (what Launch Services compares)
gets Fiber's alone. See version.gni.
"""

import argparse
import plistlib
import re
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Fiber's, from VERSION")
    parser.add_argument("--version-full", required=True)
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args()

    # Launch Services compares CFBundleVersion as integers.
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        sys.exit(f"core/branding/VERSION: {args.version!r} isn't MAJOR.MINOR.PATCH")

    with open(args.input, "rb") as f:
        plist = plistlib.load(f)
    plist["CFBundleShortVersionString"] = args.version_full
    plist["CFBundleVersion"] = args.version
    with open(args.output, "wb") as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_XML)


if __name__ == "__main__":
    main()
