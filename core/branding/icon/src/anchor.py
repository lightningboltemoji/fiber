"""Anchor - the Fiber app icon.

A spider's attachment disc, abstracted. Where a spider fixes its dragline to a
surface, it spins a fan of piriform fibrils set in cement that dries into a
membrane. Here the dragline runs in off the left edge and flares into a hub,
seven fibrils fan out ahead of it (mirrored about its heading), each ending in
a cement pad, and webbing spans the fibrils in shallow scallops. Each part is
its own Liquid Glass group, front to back:

    dragline - the lead fiber and the hub it flares into
    fibrils  - the fan and its pads
    web      - the membrane between the fibrils

The fan's bounding box (dragline excluded) sits on the tile's centre, 8px low.
"""

import math

import numpy as np
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

from common import geom_to_d, grad, group, layer, svg, tapered, write_icon

SILK = "#1D5BFF"
WEB = "#BCD0FF"
GROUND = grad("#FFFFFF", "#E2E7EF")

HUB = np.array([495.5, 526.5])
HEADING = math.radians(25.08)            # the dragline's direction of travel, into the hub
SPREAD = math.radians(250)               # the fan, mirrored about the heading
FIBRILS = 7
LENGTH = 360
WIDTH = (19, 9)                          # fibril radius at the hub and at the pad
PAD = 25
WEB_REACH = 0.8                          # webbing corners, as a fraction of fibril length
WEB_DEPTH = 0.3                          # how far each scallop dips toward the hub


def unit(a):
    return np.array([math.cos(a), math.sin(a)])


def bezier(p0, p1, p2, p3, n):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3


def dragline():
    """Runs in from well past the edge and trumpets out where it's cemented down."""
    start = HUB - unit(HEADING) * 900
    p = bezier(start, start * 0.55 + HUB * 0.45 + [0, -24], HUB - 0.2 * (HUB - start), HUB, 160)
    t = np.linspace(0, 1, len(p))
    flare = np.clip((t - 0.7) / 0.3, 0, 1) ** 2
    return tapered(p, 20 + 26 * flare, step=3).union(Point(HUB).buffer(36, quad_segs=32))


def fan():
    """The fibrils with their pads, and the points the webbing hangs from."""
    strands, pads, corners = [], [], []
    t = np.linspace(0, 1, 90)
    for a in HEADING + np.linspace(-SPREAD / 2, SPREAD / 2, FIBRILS):
        pts = HUB + np.outer(t * LENGTH, unit(a))
        strands.append(tapered(pts, WIDTH[0] + (WIDTH[1] - WIDTH[0]) * t ** 0.8, step=3))
        pads.append(Point(pts[-1]).buffer(PAD, quad_segs=32))
        corners.append(pts[int((len(pts) - 1) * WEB_REACH)])
    # soften the crotches where the fibrils leave the hub
    return unary_union(strands).buffer(5).buffer(-5).union(unary_union(pads)), corners


def web(corners):
    """Membrane from the hub out to the corners, each span a concave scallop."""
    ring = [HUB]
    t = np.linspace(0, 1, 24)[:-1, None]
    for a, b in zip(corners, corners[1:]):
        ctrl = HUB + ((a + b) / 2 - HUB) * (1 - WEB_DEPTH)
        ring.extend((1 - t) ** 2 * a + 2 * (1 - t) * t * ctrl + t ** 2 * b)
    ring.append(corners[-1])
    return Polygon(ring).buffer(0).buffer(-14).buffer(14)


def build(path):
    fibrils, corners = fan()
    assets = {
        "dragline.svg": svg([(geom_to_d(dragline()), f'fill="{SILK}"')]),
        "fibrils.svg": svg([(geom_to_d(fibrils), f'fill="{SILK}"')]),
        "web.svg": svg([(geom_to_d(web(corners)), f'fill="{WEB}"')]),
    }
    groups = [
        group([layer("dragline", "dragline.svg")], shadow_opacity=0.55, translucency=0.1),
        group([layer("fibrils", "fibrils.svg", opacity=0.96)], shadow_opacity=0.4, translucency=0.15),
        group([layer("web", "web.svg", opacity=0.9)], shadow_opacity=0.25, translucency=0.45),
    ]
    return write_icon(path, assets, groups, fill=GROUND)
