#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "numpy>=2",
#     "pillow>=11",
#     "shapely>=2",
# ]
# ///
"""Regenerate the Fiber app icon and its preview renders.

Writes AppIcon.icon (the icon), Assets.xcassets (the badge Chrome's Info.plist
puts on document icons), and renders/. //fiber/branding:app_icon compiles the
first two into the app.

    uv run core/branding/icon/build.py
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "src"))

from PIL import Image, ImageDraw, ImageFont  # noqa: E402

import anchor  # noqa: E402
from common import render  # noqa: E402

APPEARANCES = ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"]
SMALL = [256, 128, 64, 32, 16]
TILE, PAD = 300, 24
# The document badge, at 1x and 2x (see UTTypeIconBadgeName in Chrome's
# app-Info.plist).
BADGE = {"icon_256x256.png": 256, "icon_256x256@2x.png": 512}


def font(size):
    for f in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def main():
    icon = anchor.build(os.path.join(HERE, "AppIcon.icon"))
    out = os.path.join(HERE, "renders")
    big = [render(icon, os.path.join(out, f"{a}.png"), a, 1024) for a in APPEARANCES]
    small = [render(icon, os.path.join(out, f"Default@{s}.png"), "Default", s) for s in SMALL]

    catalog = os.path.join(HERE, "Assets.xcassets")
    for name, size in BADGE.items():
        render(icon, os.path.join(catalog, "Icon.iconset", name), "Default", size)
    with open(os.path.join(catalog, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

    # preview: every appearance on the top row, the size ramp underneath
    W = PAD + len(APPEARANCES) * (TILE + PAD)
    H = 40 + TILE + PAD + 40 + max(SMALL) + PAD
    sheet = Image.new("RGB", (W, H), (242, 241, 238))
    d = ImageDraw.Draw(sheet)
    f = font(16)
    for k, (name, p) in enumerate(zip(APPEARANCES, big)):
        x = PAD + k * (TILE + PAD)
        d.text((x + 4, 12), name, fill=(90, 90, 90), font=f)
        im = Image.open(p).convert("RGBA").resize((TILE, TILE), Image.LANCZOS)
        sheet.paste(im, (x, 40), im)
    y = 40 + TILE + PAD
    x = PAD
    for s, p in zip(SMALL, small):
        d.text((x + 4, y + 8), f"{s}px", fill=(90, 90, 90), font=f)
        im = Image.open(p).convert("RGBA")
        sheet.paste(im, (x, y + 40 + (max(SMALL) - s) // 2), im)
        x += max(s, 48) + PAD
    sheet.save(os.path.join(out, "preview.png"))
    print(icon)
    print(os.path.join(out, "preview.png"))


if __name__ == "__main__":
    main()
