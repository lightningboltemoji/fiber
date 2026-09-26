"""Geometry + Icon Composer export helpers for the Fiber app icon.

Everything is authored on Icon Composer's 1024x1024 canvas (SVG y-down).
"""

import json
import math
import os
import shutil
import subprocess

import numpy as np
import shapely
from shapely.geometry import MultiPolygon, Point, Polygon
from shapely.ops import unary_union

SIZE = 1024
ICTOOL = ("/Applications/Xcode.app/Contents/Applications/Icon Composer.app"
          "/Contents/Executables/ictool")


# ---------------------------------------------------------------- strokes

def resample(pts, widths, step):
    """Uniformly resample a polyline (and its widths) by arc length."""
    pts = np.asarray(pts, float)
    widths = np.asarray(widths, float)
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    if s[-1] < 1e-6:
        return pts[:1], widths[:1]
    n = max(2, int(math.ceil(s[-1] / step)) + 1)
    t = np.linspace(0, s[-1], n)
    x = np.interp(t, s, pts[:, 0])
    y = np.interp(t, s, pts[:, 1])
    return np.stack([x, y], 1), np.interp(t, s, widths)


def tapered(pts, radii, step=4.0, res=12):
    """Union of convex hulls of consecutive circles = smooth tapered stroke."""
    pts, radii = resample(pts, radii, step)
    if len(pts) == 1:
        return Point(pts[0]).buffer(radii[0], res)
    circles = shapely.buffer(shapely.points(pts), radii, quad_segs=res)
    hulls = shapely.convex_hull(
        shapely.geometrycollections(np.stack([circles[:-1], circles[1:]], 1)))
    return unary_union(hulls)


# ---------------------------------------------------------------- svg

def _ring_d(coords, prec=1):
    c = np.asarray(coords)
    if len(c) < 3:
        return ""
    fmt = f"{{:.{prec}f}}"
    # after M, further coordinate pairs are implicit linetos
    body = " ".join(fmt.format(x) + " " + fmt.format(y) for x, y in c[:-1])
    return "M" + body + "Z"


def geom_to_d(geom, simplify=0.25):
    if geom.is_empty:
        return ""
    g = geom.simplify(simplify, preserve_topology=True) if simplify else geom
    polys = g.geoms if isinstance(g, MultiPolygon) else [g]
    out = []
    for p in polys:
        if p.is_empty or not isinstance(p, Polygon):
            continue
        out.append(_ring_d(p.exterior.coords))
        out.extend(_ring_d(r.coords) for r in p.interiors)
    return " ".join(x for x in out if x)


def svg(paths, defs=""):
    """paths: list of (d, attrs) where attrs is a raw attribute string."""
    body = "\n".join(f'  <path d="{d}" {a}/>' for d, a in paths if d)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
            f'viewBox="0 0 {SIZE} {SIZE}">\n'
            + (f"  <defs>{defs}</defs>\n" if defs else "") + body + "\n</svg>\n")


# ---------------------------------------------------------------- icon.json

def srgb(hexstr, alpha=1.0):
    h = hexstr.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},{alpha:.5f}"


def grad(top, bottom):
    return {"linear-gradient": [srgb(top), srgb(bottom)]}


def layer(name, image, glass=True, opacity=1.0):
    return {"blend-mode": "normal", "glass": glass, "hidden": False,
            "image-name": image, "name": name,
            "position": {"scale": 1, "translation-in-points": [0, 0]}, "opacity": opacity}


def group(layers, shadow="neutral", shadow_opacity=0.5, translucency=None,
          specular=True, lighting="individual", blur=None, opacity=1.0):
    return {"blend-mode": "normal", "blur-material": blur, "hidden": False,
            "layers": layers, "lighting": lighting, "opacity": opacity,
            "shadow": {"kind": shadow, "opacity": shadow_opacity},
            "specular": specular,
            "translucency": {"enabled": translucency is not None,
                             "value": 0.5 if translucency is None else translucency}}


def write_icon(path, assets, groups, fill, fill_dark="system-dark"):
    """Write an .icon bundle. assets: {filename: svg_text}; groups front-to-back."""
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(os.path.join(path, "Assets"))
    for fn, text in assets.items():
        with open(os.path.join(path, "Assets", fn), "w") as f:
            f.write(text)
    doc = {"fill-specializations": [{"value": fill},
                                    {"appearance": "dark", "value": fill_dark}],
           "groups": groups,
           "supported-platforms": {"squares": ["macOS"]}}
    with open(os.path.join(path, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)
    return path


def render(icon_path, out_png, rendition="Default", size=1024):
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    subprocess.run([ICTOOL, icon_path, "--export-image", "--output-file", out_png,
                    "--platform", "macOS", "--rendition", rendition,
                    "--width", str(size), "--height", str(size), "--scale", "1"],
                   check=True, capture_output=True)
    return out_png
