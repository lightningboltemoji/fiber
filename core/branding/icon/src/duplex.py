"""Duplex, the Fiber app icon: an LC duplex fiber connector as a happy face.

The housing is the head, its latch curls up into a cowlick, and a ribbed boot
leads into the cord, which runs off the bottom of the tile. The whole connector
leans by TILT. mark() fades the cord out instead of cropping it.
"""

import numpy as np
from shapely import affinity
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

from common import SIZE, geom_to_d, grad, group, layer, svg, tapered, write_icon

HOUSING = "#3DEBDA"
BOOT = "#2CD3C6"
INK = "#0C173A"
TONGUE = "#FF6F91"
GROUND = grad("#2F6BFF", "#1747D9")
GROUND_DARK = grad("#14204A", "#070B1C")

CX = 512
HEAD = (226, 326, 798, 716)                 # x0, y0, x1, y1 of the housing
HEAD_RADIUS = 136
BOOT_FOOT = HEAD[3] + 140                   # where the boot ends and the cord begins
RIBS = (766, 810)                           # tops of the gaps across the boot
RIB_GAP = 18
CORD_WIDTH = 92
CORD_INSET = 24                             # how far up into the boot the cord starts
CORD_DRIFT = 60                             # how far right the cord wanders by the tile's edge
TILT = -7
PIVOT = (512, 600)

EYE_DX, EYE_Y = 114, 522                    # centres of the closed-eye arcs
EYE_RADIUS, EYE_WIDTH = 50, 34
EYE_SWEEP = (18, 162)                       # degrees, 0 to the right
MOUTH_TOP, MOUTH_HALF, MOUTH_DEPTH = 587, 48, 46


def lean(g):
    return affinity.rotate(g, TILT, origin=PIVOT)


def lean_point(p):
    return np.array(lean(Point(p)).coords[0])


def bezier(p0, p1, p2, p3, n=200):
    p0, p1, p2, p3 = map(np.asarray, (p0, p1, p2, p3))
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3


def stroke(pts, width):
    return LineString(pts).buffer(width / 2, quad_segs=32)


def head():
    """The housing, with the latch rising off its top and curling over to the
    right."""
    x0, y0, x1, y1 = HEAD
    r = HEAD_RADIUS
    housing = box(x0 + r, y0 + r, x1 - r, y1 - r).buffer(r, quad_segs=32)
    curl = bezier((CX + 30, y0 + 40), (CX + 26, y0 - 70), (CX + 70, y0 - 150), (CX + 170, y0 - 146))
    t = np.linspace(0, 1, len(curl))
    latch = tapered(curl, (92 + (40 - 92) * t) / 2, step=3)
    return housing.union(latch).buffer(22, quad_segs=24).buffer(-22, quad_segs=24)


def boot():
    top = HEAD[3] - 30
    taper = Polygon([(CX - 120, top), (CX + 120, top), (CX + 70, BOOT_FOOT), (CX - 70, BOOT_FOOT)])
    taper = taper.buffer(24).buffer(-24)
    for y in RIBS:
        taper = taper.difference(box(0, y, SIZE, y + RIB_GAP))
    return taper


def cord_path():
    """The cord's centreline, from inside the boot to past the tile's bottom,
    leaving along the boot's axis."""
    start = lean_point((CX, BOOT_FOOT - CORD_INSET))
    axis = lean_point((CX, BOOT_FOOT + 100)) - lean_point((CX, BOOT_FOOT))
    axis /= np.linalg.norm(axis)
    end = start + axis * 420 + [CORD_DRIFT, 0]
    return np.vstack([bezier(start, start + axis * 140, end - [0, 140], end), end + [0, 300]])


def cord():
    return stroke(cord_path(), CORD_WIDTH).difference(lean(box(0, 0, SIZE, BOOT_FOOT - CORD_INSET)))


def eyes():
    a = np.radians(np.linspace(*EYE_SWEEP, 90))
    arcs = [np.stack([CX + sx * EYE_DX + EYE_RADIUS * np.cos(a), EYE_Y - EYE_RADIUS * np.sin(a)], 1)
            for sx in (-1, 1)]
    return unary_union([stroke(p, EYE_WIDTH) for p in arcs])


def mouth():
    """An open laugh: a flat top lip over a round bottom, and the tongue in it."""
    t = np.linspace(0, np.pi, 80)
    bottom = np.stack([CX + MOUTH_HALF * np.cos(t), MOUTH_TOP + MOUTH_DEPTH * np.sin(t)], 1)
    lips = Polygon(np.vstack([[CX + MOUTH_HALF, MOUTH_TOP], bottom, [CX - MOUTH_HALF, MOUTH_TOP]]))
    lips = lips.buffer(-6).buffer(6)
    tongue = affinity.scale(Point(CX + 3, MOUTH_TOP + MOUTH_DEPTH + 2).buffer(34, quad_segs=32), 1, 0.6)
    return lips, tongue.intersection(lips.buffer(-5))


def mark():
    """The icon's glyph without its tile, as SVG for Fiber's UI to draw in one
    color: the face cut out of the housing, and the cord fading out a short
    way past the boot."""
    lips, _ = mouth()
    housing = lean(head().difference(eyes()).difference(lips))
    sleeve = lean(boot().difference(head().buffer(RIB_GAP)))
    reach = 260
    path = cord_path()
    start = path[0]
    lengths = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))])
    tail = path[np.searchsorted(lengths, reach + CORD_INSET)]
    line = stroke(path, CORD_WIDTH).intersection(Point(start).buffer(reach + CORD_INSET))
    line = line.difference(lean(box(0, 0, SIZE, BOOT_FOOT - CORD_INSET)))
    margin = 8
    x0, y0, x1, y1 = unary_union([housing, sleeve, line]).bounds
    view = f"{x0 - margin:.1f} {y0 - margin:.1f} {x1 - x0 + 2 * margin:.1f} {y1 - y0 + 2 * margin:.1f}"
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">\n'
        f'  <defs><linearGradient id="fade" gradientUnits="userSpaceOnUse" '
        f'x1="{start[0]:.1f}" y1="{start[1]:.1f}" x2="{tail[0]:.1f}" y2="{tail[1]:.1f}">'
        f'<stop offset="0.2" stop-opacity="1"/><stop offset="1" stop-opacity="0"/>'
        f"</linearGradient></defs>\n"
        f'  <path d="{geom_to_d(housing)}" fill="#000"/>\n'
        f'  <path d="{geom_to_d(sleeve)}" fill="#000"/>\n'
        f'  <path d="{geom_to_d(line)}" fill="url(#fade)"/>\n'
        "</svg>\n"
    )


def build(path):
    lips, tongue = mouth()
    housing = lean(head())
    sleeve = lean(boot()).difference(housing.buffer(2))
    # The face is painted on the housing: as glass of its own, each stroke
    # gets a specular rim, which is all that shows of it in Clear.
    assets = {
        "housing.svg": svg([(geom_to_d(housing), f'fill="{HOUSING}"'), (geom_to_d(lean(eyes())), f'fill="{INK}"'),
                            (geom_to_d(lean(lips)), f'fill="{INK}"'), (geom_to_d(lean(tongue)), f'fill="{TONGUE}"')]),
        "cord.svg": svg([(geom_to_d(cord()), f'fill="{HOUSING}"'), (geom_to_d(sleeve), f'fill="{BOOT}"')]),
    }
    groups = [
        group([layer("housing", "housing.svg")], shadow_opacity=0.5, translucency=0.1),
        group([layer("cord", "cord.svg")], shadow_opacity=0.4, translucency=0.15),
    ]
    return write_icon(path, assets, groups, fill=GROUND, fill_dark=GROUND_DARK)
