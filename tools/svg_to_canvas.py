#!/usr/bin/env python3
"""Turn an SVG icon into polygons a QML Canvas can draw.

A package ships one .lisp and one .qml, so an icon cannot be a file, and
neither route that would take the path data as it stands is safe: QtQuick.Shapes
is absent from VESC Tool's own QML, and an SVG data URI needs the qsvg image
plugin to be in the APK. Canvas is already proven here, so the curves are
flattened, thinned to the tolerance the icon is actually drawn at, and written
out as a unit-box coordinate list.

The two lamps in ui.qml came out of tools/icons with

  tools/svg_to_canvas.py tools/icons/engine.svg --extent 24 --tol 0.12 --per-line 7
"""

import argparse
import math
import re
import sys
import xml.etree.ElementTree as ET

NUM = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")
CMD = re.compile(r"([MmLlHhVvCcSsQqTtAaZz])")


def parse_transform(text):
    """The composed 2x3 matrix of one transform attribute, outermost first."""
    m = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", text or ""):
        v = [float(n) for n in NUM.findall(args)]
        if name == "translate":
            t = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == "scale":
            t = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == "matrix":
            t = tuple(v[:6])
        elif name == "rotate":
            a = math.radians(v[0])
            c, s = math.cos(a), math.sin(a)
            t = (c, s, -s, c, 0, 0)
            if len(v) > 2:
                t = mul(mul((1, 0, 0, 1, v[1], v[2]), t), (1, 0, 0, 1, -v[1], -v[2]))
        else:
            raise SystemExit(f"svg_to_canvas: unsupported transform {name}")
        m = mul(m, t)
    return m


def mul(a, b):
    return (a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
            a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
            a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5])


def apply(m, p):
    return (m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5])


def bezier(p0, p1, p2, p3, out, steps):
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u * u * u * p0[0] + 3 * u * u * t * p1[0]
                    + 3 * u * t * t * p2[0] + t * t * t * p3[0],
                    u * u * u * p0[1] + 3 * u * u * t * p1[1]
                    + 3 * u * t * t * p2[1] + t * t * t * p3[1]))


def steps_for(p0, p1, p2, p3):
    d = (abs(p1[0] - p0[0]) + abs(p1[1] - p0[1]) + abs(p2[0] - p1[0])
         + abs(p2[1] - p1[1]) + abs(p3[0] - p2[0]) + abs(p3[1] - p2[1]))
    return max(2, min(48, int(math.sqrt(d) * 1.6)))


def arc(p0, rx, ry, rot, large, sweep, p1, out):
    """Endpoint to centre parametrisation, F.6.5 of the SVG spec."""
    if p0 == p1 or rx == 0 or ry == 0:
        out.append(p1)
        return
    rx, ry = abs(rx), abs(ry)
    a = math.radians(rot)
    cs, sn = math.cos(a), math.sin(a)
    dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1, y1 = cs * dx + sn * dy, -sn * dx + cs * dy
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    k = math.sqrt(max(0.0, num / den))
    if large == sweep:
        k = -k
    cx1, cy1 = k * rx * y1 / ry, -k * ry * x1 / rx
    cx = cs * cx1 - sn * cy1 + (p0[0] + p1[0]) / 2
    cy = sn * cx1 + cs * cy1 + (p0[1] + p1[1]) / 2
    t0 = math.atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
    t1 = math.atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx)
    d = t1 - t0
    if not sweep and d > 0:
        d -= 2 * math.pi
    elif sweep and d < 0:
        d += 2 * math.pi
    n = max(2, int(abs(d) / (math.pi / 24)))
    for i in range(1, n + 1):
        t = t0 + d * i / n
        px, py = rx * math.cos(t), ry * math.sin(t)
        out.append((cs * px - sn * py + cx, sn * px + cs * py + cy))


def flatten(d):
    """Every subpath of a path's d attribute, as a list of points."""
    tokens = [t for t in CMD.split(d) if t.strip()]
    subs, cur = [], []
    pos = start = (0.0, 0.0)
    prev_c = prev_q = None
    cmd = None
    i = 0
    while i < len(tokens):
        if CMD.fullmatch(tokens[i]):
            cmd = tokens[i]
            i += 1
            if cmd in "Zz":
                if len(cur) > 2:
                    subs.append(cur)
                cur, pos = [], start
                continue
            args = [float(n) for n in NUM.findall(tokens[i])] if i < len(tokens) else []
            i += 1
        else:
            args = [float(n) for n in NUM.findall(tokens[i])]
            i += 1
        rel = cmd.islower()
        up = cmd.upper()
        need = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7}[up]
        for j in range(0, len(args) - need + 1, need):
            a = args[j:j + need]
            if up == "M":
                p = (pos[0] + a[0], pos[1] + a[1]) if rel else (a[0], a[1])
                if len(cur) > 2:
                    subs.append(cur)
                cur, pos, start = [p], p, p
                cmd = "l" if rel else "L"  # a run after moveto is lineto
                prev_c = prev_q = None
                continue
            if up in "LHV":
                if up == "L":
                    p = (pos[0] + a[0], pos[1] + a[1]) if rel else (a[0], a[1])
                elif up == "H":
                    p = (pos[0] + a[0], pos[1]) if rel else (a[0], pos[1])
                else:
                    p = (pos[0], pos[1] + a[0]) if rel else (pos[0], a[0])
                cur.append(p)
                prev_c = prev_q = None
            elif up in "CS":
                if up == "C":
                    c1 = (pos[0] + a[0], pos[1] + a[1]) if rel else (a[0], a[1])
                    c2 = (pos[0] + a[2], pos[1] + a[3]) if rel else (a[2], a[3])
                    p = (pos[0] + a[4], pos[1] + a[5]) if rel else (a[4], a[5])
                else:
                    c1 = (2 * pos[0] - prev_c[0], 2 * pos[1] - prev_c[1]) if prev_c else pos
                    c2 = (pos[0] + a[0], pos[1] + a[1]) if rel else (a[0], a[1])
                    p = (pos[0] + a[2], pos[1] + a[3]) if rel else (a[2], a[3])
                bezier(pos, c1, c2, p, cur, steps_for(pos, c1, c2, p))
                prev_c, prev_q = c2, None
            elif up in "QT":
                if up == "Q":
                    q = (pos[0] + a[0], pos[1] + a[1]) if rel else (a[0], a[1])
                    p = (pos[0] + a[2], pos[1] + a[3]) if rel else (a[2], a[3])
                else:
                    q = (2 * pos[0] - prev_q[0], 2 * pos[1] - prev_q[1]) if prev_q else pos
                    p = (pos[0] + a[0], pos[1] + a[1]) if rel else (a[0], a[1])
                c1 = (pos[0] + 2 / 3 * (q[0] - pos[0]), pos[1] + 2 / 3 * (q[1] - pos[1]))
                c2 = (p[0] + 2 / 3 * (q[0] - p[0]), p[1] + 2 / 3 * (q[1] - p[1]))
                bezier(pos, c1, c2, p, cur, steps_for(pos, c1, c2, p))
                prev_q, prev_c = q, None
            else:
                p = (pos[0] + a[5], pos[1] + a[6]) if rel else (a[5], a[6])
                arc(pos, a[0], a[1], a[2], a[3] != 0, a[4] != 0, p, cur)
                prev_c = prev_q = None
            pos = cur[-1]
    if len(cur) > 2:
        subs.append(cur)
    return subs


sys.setrecursionlimit(20000)


def rdp(pts, tol):
    if len(pts) < 3:
        return pts
    x0, y0 = pts[0]
    x1, y1 = pts[-1]
    dx, dy = x1 - x0, y1 - y0
    n = math.hypot(dx, dy)
    worst, at = -1.0, 0
    for i in range(1, len(pts) - 1):
        px, py = pts[i]
        if n == 0:
            dist = math.hypot(px - x0, py - y0)
        else:
            dist = abs(dy * px - dx * py + x1 * y0 - y1 * x0) / n
        if dist > worst:
            worst, at = dist, i
    if worst <= tol:
        return [pts[0], pts[-1]]
    return rdp(pts[:at + 1], tol)[:-1] + rdp(pts[at:], tol)


def simplify_closed(pts, tol):
    """A ring has no natural ends, so it is split at its two extreme points -
    keeping either as a corner, which walking from an arbitrary start would not."""
    if len(pts) < 4:
        return pts
    lo = min(range(len(pts)), key=lambda i: (pts[i][1], pts[i][0]))
    pts = pts[lo:] + pts[:lo]
    hi = max(range(len(pts)), key=lambda i: (pts[i][1], pts[i][0]))
    out = rdp(pts[:hi + 1], tol)[:-1] + rdp(pts[hi:] + [pts[0]], tol)[:-1]
    return out


def load(path):
    tree = ET.parse(path)
    root = tree.getroot()
    subs = []

    def walk(node, m):
        m = mul(m, parse_transform(node.get("transform")))
        tag = node.tag.split("}")[-1]
        if tag == "path" and node.get("d"):
            for s in flatten(node.get("d")):
                subs.append([apply(m, p) for p in s])
        for kid in node:
            walk(kid, m)

    walk(root, (1.0, 0.0, 0.0, 1.0, 0.0, 0.0))
    if not subs:
        raise SystemExit(f"svg_to_canvas: no path in {path}")
    return subs


def signed_area(s):
    return sum(s[i][0] * s[(i + 1) % len(s)][1] - s[(i + 1) % len(s)][0] * s[i][1]
               for i in range(len(s))) / 2


def inside(p, s):
    hit = False
    for i in range(len(s)):
        (x0, y0), (x1, y1) = s[i], s[(i + 1) % len(s)]
        if (y0 > p[1]) != (y1 > p[1]) and p[0] < (x1 - x0) * (p[1] - y0) / (y1 - y0) + x0:
            hit = not hit
    return hit


def orient(subs):
    """A cut out must wind against the ring holding it, or the plain nonzero fill
    the Canvas does by default would paint over it instead of through it."""
    for i, s in enumerate(subs):
        depth = sum(1 for j, o in enumerate(subs) if j != i and inside(s[0], o))
        want = -1 if depth % 2 else 1
        if math.copysign(1, signed_area(s)) != math.copysign(1, want):
            subs[i] = s[::-1]
    return subs


def normalise(subs):
    """Into a unit box, aspect kept, centred - so the QML side only needs an extent."""
    xs = [p[0] for s in subs for p in s]
    ys = [p[1] for s in subs for p in s]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    k = 1.0 / max(w, h)
    ox = (1 - w * k) / 2 - min(xs) * k
    oy = (1 - h * k) / 2 - min(ys) * k
    return [[(p[0] * k + ox, p[1] * k + oy) for p in s] for s in subs]


def emit(subs, per_line):
    out = []
    for s in subs:
        flat = [f"{v:.4f}".rstrip("0").rstrip(".") or "0" for p in s for v in p]
        rows = [", ".join(flat[i:i + per_line * 2])
                for i in range(0, len(flat), per_line * 2)]
        out.append("[" + ",\n     ".join(rows) + "]")
    return "[" + ",\n    ".join(out) + "]"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("svg")
    ap.add_argument("--extent", type=float, default=24.0,
                    help="px the icon is drawn at, so the tolerance means something")
    ap.add_argument("--tol", type=float, default=0.12, help="allowed error in px")
    ap.add_argument("--per-line", type=int, default=6)
    a = ap.parse_args()

    subs = normalise(load(a.svg))
    raw = sum(len(s) for s in subs)
    subs = orient([simplify_closed(s, a.tol / a.extent) for s in subs])
    kept = sum(len(s) for s in subs)
    print(f"svg_to_canvas: {len(subs)} subpaths, {raw} -> {kept} points",
          file=sys.stderr)
    print(emit(subs, a.per_line))


if __name__ == "__main__":
    main()
