"""
Military building styles, vehicles and projectiles.
Vehicles face -Y; footprint styles follow civil.py conventions.
"""

import math

from .geo import Model, Part, place
from .civil import G, plinth, tank, tree, lamp, bush


def tints(p):
    if p.get("eastern") or p.get("tint") == "eastern":
        return "east", "east_d"
    if p.get("european") or p.get("tint") == "european":
        return "euro", "euro_d"
    if p.get("tint") == "sand":
        return "sand", "tan"
    if p.get("tint") == "dark":
        return "gunmetal", "charcoal"
    return "olive", "olive_d"


def fence(part: Part, W, D, z=G, color="grey", gap_front=0.0):
    posts = []
    for i in range(int(W // 3) + 1):
        x = -W / 2 + 0.4 + i * (W - 0.8) / max(1, int(W // 3))
        posts += [(x, -D / 2 + 0.4), (x, D / 2 - 0.4)]
    for i in range(int(D // 3) + 1):
        y = -D / 2 + 0.4 + i * (D - 0.8) / max(1, int(D // 3))
        posts += [(-W / 2 + 0.4, y), (W / 2 - 0.4, y)]
    for (x, y) in posts:
        if gap_front and abs(x) < gap_front and y < 0:
            continue
        part.box(0.15, 0.15, 1.8, x, y, z, color, bevel=0.02)
    for y in (-D / 2 + 0.4, D / 2 - 0.4):
        if gap_front and y < 0:
            for sx in (-1, 1):
                seg = (W / 2 - 0.4 - gap_front)
                part.box(seg, 0.06, 0.08, sx * (gap_front + seg / 2), y, z + 1.5, color, bevel=0.0)
        else:
            part.box(W - 0.8, 0.06, 0.08, 0, y, z + 1.5, color, bevel=0.0)
    for x in (-W / 2 + 0.4, W / 2 - 0.4):
        part.box(0.06, D - 0.8, 0.08, x, 0, z + 1.5, color, bevel=0.0)


def dish(part: Part, x, y, z, r, tilt=35, color="white", rz=0):
    part.cyl(0.25, 1.6, x, y, z, "steel", seg=6)
    part.cyl(r, 0.35, x, y, z + 1.6 + r * 0.4, color, seg=16, r2=r * 0.35, rx=-tilt, rz=rz)


# ----------------------------------------------------------------- research
def research_lab(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    bw, bd = W * 0.78, D * 0.5
    by = -D * 0.12
    b.box(bw, bd, 6.4, 0, by, G, "white", bevel=0.2)
    b.box(bw + 0.3, bd + 0.3, 0.6, 0, by, G + 6.4, "teal", bevel=0.1)
    L.box(bw - 1.2, 0.2, 3.4, 0, by - bd / 2 - 0.05, G + 1.4, "glass_l", bevel=0.04)
    for i in range(5):
        b.box(0.25, 0.3, 4.6, -bw / 2 + 0.6 + i * (bw - 1.2) / 4, by - bd / 2 - 0.12, G + 0.8, "white", bevel=0.04)
    # observatory dome with slit
    b.cyl(2.8, 1.2, W * 0.16, by, G + 7.0, "offwhite", seg=18)
    b.dome(2.8, W * 0.16, by, G + 8.2, "alu", seg=18, rings=5)
    b.box(0.7, 2.8, 2.2, W * 0.16, by - 1.4, G + 8.6, "charcoal", bevel=0.05, rx=-25)
    # solar + antenna
    for i in range(3):
        b.box(2.6, 1.6, 0.12, -W * 0.18, by + 0.4 - i * 1.8 + 1.8, G + 7.3, "navy", bevel=0.03, rx=-20, center=True)
    b.cyl(0.12, 6, -W * 0.33, by + bd / 4, G + 7.0, "steel", seg=6)
    L.sphere(0.2, -W * 0.33, by + bd / 4, G + 13.1, "red", subd=1)
    b.box(W * 0.8, D * 0.26, 0.06, 0, D * 0.3, G, "grass", bevel=0.02)
    tree(b, -W * 0.28, D * 0.3, 0.8, kind=2)
    tree(b, W * 0.28, D * 0.3, 0.8, kind=0)


def university(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    by = D * 0.08
    bw, bd = W * 0.86, D * 0.5
    b.box(bw, bd, 9.0, 0, by, G, "cream", bevel=0.18)
    b.box(bw + 0.3, bd + 0.3, 0.6, 0, by, G + 9.0, "beige", bevel=0.1)
    L.window_grid(bw, bd, 0, by, G + 0.8, 2, 4.0, win_w=1.3, gap=1.1, color="glass")
    # portico: steps, columns, pediment
    py = by - bd / 2 - 1.8
    b.box(W * 0.42, 4.0, 0.4, 0, py + 0.6, G, "concrete_l", bevel=0.08)
    b.box(W * 0.4, 3.6, 0.4, 0, py + 0.6, G + 0.4, "offwhite", bevel=0.08)
    for i in range(6):
        b.cyl(0.42, 7.6, -W * 0.17 + i * W * 0.068, py, G + 0.8, "white", seg=10)
    b.box(W * 0.42, 3.8, 0.7, 0, py + 0.6, G + 8.4, "white", bevel=0.1)
    b.prism([(-W * 0.21, 0), (W * 0.21, 0), (0, 2.4)], 3.8, "y", 0, py + 0.6, G + 9.1, "offwhite")
    # dome
    b.cyl(3.4, 2.0, 0, by + 1.0, G + 9.6, "cream", seg=20)
    b.dome(3.4, 0, by + 1.0, G + 11.6, "teal", seg=20, rings=6)
    b.cyl(0.25, 1.6, 0, by + 1.0, G + 14.9, "brass", seg=6)
    for x in (-W * 0.36, W * 0.36):
        tree(b, x, -D * 0.38, 0.8, kind=1)


def mil_research(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete")
    fence(b, W, D, gap_front=3.0)
    by = -D * 0.1
    bw, bd = W * 0.66, D * 0.46
    b.box(bw, bd, 5.4, -W * 0.06, by, G, "olive_l", bevel=0.2)
    # sloped bunker berm
    b.prism([(-bd / 2 - 1.6, 0), (bd / 2 + 1.6, 0), (bd / 2, 3.2), (-bd / 2, 3.2)], bw + 0.4, "x", -W * 0.06, by, G, "grass")
    b.box(bw + 0.4, bd + 0.4, 0.6, -W * 0.06, by, G + 5.4, "olive_d", bevel=0.1)
    b.box(5.0, 0.3, 3.8, -W * 0.06, by - bd / 2 - 1.7, G, "gunmetal", bevel=0.08)
    for i in range(6):
        b.box(5.0, 0.32, 0.08, -W * 0.06, by - bd / 2 - 1.75, G + 0.5 + i * 0.55, "olive_d", bevel=0.0)
    L.box(4.0, 0.25, 0.5, -W * 0.06, by - bd / 2 - 1.9, G + 4.2, "glow", bevel=0.03)
    dish(b, W * 0.3, D * 0.28, G, 2.6, 40, "white", rz=20)
    dish(b, -W * 0.25, D * 0.3, G, 1.8, 30, "alu", rz=-30)
    b.cyl(0.18, 18, W * 0.33, -D * 0.3, G, "steel", seg=6)
    for z in (6, 12):
        b.box(1.6, 0.12, 0.12, W * 0.33, -D * 0.3, G + z, "steel", bevel=0.0)
    L.sphere(0.25, W * 0.33, -D * 0.3, G + 18.2, "red", subd=1)


# ----------------------------------------------------------------- support
def depot(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "asphalt", "concrete")
    by = D * 0.16
    bw, bd = W - 1.2, D * 0.56
    b.box(bw, bd, 6.0, 0, by, G, "olive_l", bevel=0.18)
    b.prism([(-bd / 2 - 0.4, 0), (bd / 2 + 0.4, 0), (0, 1.8)], bw + 0.4, "x", 0, by, G + 6.0, "olive_d")
    bays = 4
    for i in range(bays):
        x = -bw / 2 + (i + 0.5) * bw / bays
        b.box(bw / bays - 0.8, 0.2, 4.6, x, by - bd / 2 - 0.05, G, "gunmetal", bevel=0.05)
        b.box(bw / bays - 0.6, 0.3, 0.3, x, by - bd / 2 - 0.1, G + 4.7, "amber", bevel=0.04)
        L.box(0.6, 0.3, 0.3, x, by - bd / 2 - 0.2, G + 5.3, "glow", bevel=0.03)
    for i in range(5):
        b.box(0.2, D * 0.3, 0.04, -W / 2 + 2 + i * 3, -D * 0.3, G, "line", bevel=0.0)
    b.box(1.0, 1.0, 1.8, W / 2 - 1.2, -D / 2 + 1.2, G, "red", bevel=0.1)


def radar(m: Model, W, D, p):
    b = m.body
    plinth(m, W, D, "concrete")
    b.box(3.2, 3.2, 3.0, 0, 0, G, "olive_l", bevel=0.15)
    # lattice tower
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.between((sx * 1.3, sy * 1.3, G + 3.0), (sx * 0.5, sy * 0.5, G + 11.0), 0.14, "steel", seg=6)
    for z in (5.5, 8.5):
        k = 1.3 - (z - 3.0) / 8.0 * 0.8
        b.box(k * 2 + 0.2, 0.1, 0.1, 0, -k, G + z, "steel", bevel=0.0)
        b.box(k * 2 + 0.2, 0.1, 0.1, 0, k, G + z, "steel", bevel=0.0)
        b.box(0.1, k * 2 + 0.2, 0.1, -k, 0, G + z, "steel", bevel=0.0)
        b.box(0.1, k * 2 + 0.2, 0.1, k, 0, G + z, "steel", bevel=0.0)
    b.box(1.6, 1.6, 0.5, 0, 0, G + 11.0, "gunmetal", bevel=0.1)
    d = m.part("Dish", pivot=(0, 0, G + 11.5))
    d.cyl(0.4, 0.8, 0, 0, G + 11.5, "gunmetal", seg=8)
    d.box(7.6, 0.4, 2.6, 0, 0.3, G + 12.0, "white", bevel=0.15, rx=-14)
    d.box(7.8, 0.25, 0.25, 0, 0.6, G + 12.0, "steel", bevel=0.03)
    for i in range(6):
        d.box(0.12, 0.45, 2.4, -3.2 + i * 1.28, 0.2, G + 12.1, "alu", bevel=0.0, rx=-14)
    m.marker("Spin", (0, 0, G + 11.5))


# -------------------------------------------------------------- air defense
def ciws(m: Model, W, D, p):
    b, L = m.body, m.lights
    col, dark = tints(p)
    plinth(m, W, D, "concrete")
    b.cyl(W * 0.42, 0.5, 0, 0, G, "concrete_l", seg=16, bevel=0.08)
    b.cyl(1.2, 1.8, 0, 0, G + 0.5, col, seg=12)
    b.box(2.2, 2.4, 1.6, 0, 0.1, G + 2.3, col, bevel=0.25)
    b.cyl(0.95, 2.0, 0, 0.5, G + 3.9, "white", seg=14)
    b.dome(0.95, 0, 0.5, G + 5.9, "white", seg=14, rings=4)
    # gatling barrels
    for k in range(6):
        a = 2 * math.pi * k / 6
        b.cyl(0.08, 3.2, math.cos(a) * 0.25, -1.1, G + 3.0 + math.sin(a) * 0.25, "gunmetal", seg=5, rx=90)
    b.cyl(0.38, 0.8, 0, -1.1, G + 3.0, dark, seg=10, rx=90)
    L.box(0.4, 0.2, 0.3, 0.7, -1.15, G + 3.5, "red", bevel=0.03)
    b.box(0.6, 0.6, 1.2, -W / 2 + 0.6, -D / 2 + 0.6, G, "olive_d", bevel=0.05)


def truck_chassis(part: Part, length, col, dark, x=0.0, y=0.0, axles=None, cab=True, width=3.2):
    """Military truck chassis facing -Y; returns z of the bed top."""
    z = G
    part.box(width - 0.4, length, 0.7, x, y, z + 1.0, dark, bevel=0.1)
    if cab:
        cy = y - length / 2 + 1.5
        part.box(width, 2.8, 2.4, x, cy, z + 1.3, col, bevel=0.3)
        part.box(width - 0.3, 0.2, 0.9, x, cy - 1.45, z + 2.6, "glass_d", bevel=0.03)
        part.box(width + 0.1, 0.5, 0.5, x, cy - 1.4, z + 0.9, dark, bevel=0.08)
    n = axles or max(2, int(length // 2.6))
    start = y - length / 2 + 1.5
    span = length - 2.6
    for i in range(n):
        wy = start + (span * i / (n - 1) if n > 1 else 0)
        for sx in (-1, 1):
            _wheel(part, x + sx * (width / 2 - 0.1), wy, z + 0.78, 0.78, 0.6)
    return z + 1.7


def _wheel(part: Part, x, y, zc, r, w):
    # cylinder axis along X, centred on (x, y, zc)
    part.cyl(r, w, x - w / 2, y, zc, "tire", seg=12, ry=90)
    part.cyl(r * 0.5, w + 0.06, x - w / 2 - 0.03, y, zc, "gunmetal", seg=8, ry=90)


def sam(m: Model, W, D, p):
    b, L = m.body, m.lights
    col, dark = tints(p)
    plinth(m, W, D, "concrete")
    count = 2 if p.get("large") else 1
    length = D * 0.72
    for i in range(count):
        x = -W * 0.14 if count == 1 else (-W * 0.3 + i * W * 0.32)
        bed = truck_chassis(b, length, col, dark, x=x)
        # raised tube pack
        pivot_y = length * 0.3
        b.box(1.0, 1.0, 1.4, x, pivot_y, bed, dark, bevel=0.1)
        for tx in (-0.65, 0.65):
            for tz in (0.0, 1.2):
                b.box(1.15, length * 0.62, 1.15, x + tx, pivot_y - length * 0.18, bed + 1.6 + tz, col, bevel=0.15, rx=48, center=True)
        b.box(2.8, 0.2, 2.6, x, pivot_y - length * 0.42, bed + 3.3, "gunmetal", bevel=0.05, rx=48, center=True)
    # radar truck
    rx = W * 0.3
    bed = truck_chassis(b, D * 0.5, col, dark, x=rx, width=2.8)
    b.box(2.4, 0.4, 3.4, rx, D * 0.08, bed + 0.6, "white", bevel=0.15, rx=-18)
    for i in range(4):
        b.box(0.1, 0.42, 3.2, rx - 0.9 + i * 0.6, D * 0.08 - 0.05, bed + 0.7, "alu", bevel=0.0, rx=-18)
    b.box(1.6, 1.2, 1.0, W * 0.38, -D * 0.38, G, "gunmetal", bevel=0.1)
    L.box(0.3, 0.3, 0.3, W * 0.38 + 0.6, -D * 0.38 - 0.6, G + 0.8, "red", bevel=0.03)


def laser(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete")
    b.cyl(W * 0.44, 0.8, 0, 0, G, "charcoal", seg=8, bevel=0.1)
    b.cyl(1.7, 3.0, 0, 0, G + 0.8, "alu", seg=8)
    for k in range(8):
        a = 2 * math.pi * k / 8
        b.box(0.15, 1.2, 2.6, math.cos(a) * 1.9, math.sin(a) * 1.9, G + 1.0, "steel", bevel=0.02, rz=math.degrees(a) + 90)
    b.box(3.2, 3.2, 2.6, 0, 0.2, G + 3.8, "white", bevel=0.4)
    b.cyl(1.0, 1.8, 0, -1.4, G + 5.1, "gunmetal", seg=14, rx=90)
    L.cyl(0.8, 0.3, 0, -3.15, G + 5.1, "cyan", seg=14, rx=90)
    for sx in (-1, 1):
        b.box(0.3, 2.0, 1.6, sx * 1.75, 0.2, G + 4.3, "teal", bevel=0.08)


# ---------------------------------------------------------------- launchers
def missile(part: Part, x, y, z, length, r, body="white", nose="charcoal", band=None, axis="z", tilt=0.0):
    """Missile standing on (x, y, z) along +Z (or rotated by tilt degrees about X)."""
    part.cyl(r, length * 0.82, x, y, z, body, seg=12, rx=tilt)
    nz = length * 0.82
    ny = -math.sin(math.radians(tilt)) * nz
    nzz = math.cos(math.radians(tilt)) * nz
    part.cyl(r, length * 0.18, x, y + ny, z + nzz, nose, seg=12, r2=0.06, rx=tilt)
    if band:
        bz = length * 0.55
        part.cyl(r + 0.04, 0.4, x, y - math.sin(math.radians(tilt)) * bz, z + math.cos(math.radians(tilt)) * bz, band, seg=12, rx=tilt)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        part.box(0.08, r * 2.4, length * 0.12, x + math.cos(a) * r * 0.9, y + math.sin(a) * r * 0.9 * math.cos(math.radians(tilt)), z,
                 "gunmetal", bevel=0.0, rz=math.degrees(a) + 90, rx=tilt)


def launcher(m: Model, W, D, p):
    b = m.body
    col, dark = tints(p)
    plinth(m, W, D, "concrete")
    length = D - 1.4
    width = min(W - 0.6, 3.4)
    bed = truck_chassis(b, length, col, dark, width=width)
    # outriggers
    for sx in (-1, 1):
        for oy in (-length * 0.1, length * 0.38):
            b.box(1.2, 0.4, 0.4, sx * (width / 2 + 0.4), oy, G + 0.9, dark, bevel=0.05)
            b.cyl(0.35, 0.9, sx * (width / 2 + 0.9), oy, G, "gunmetal", seg=8)
    if p.get("kind") == "box":
        pivot_y = length * 0.25
        b.box(width - 0.2, length * 0.62, 2.4, 0, pivot_y - length * 0.1, bed + 1.2, col, bevel=0.2, rx=22, center=True)
        for ix in (-0.7, 0.7):
            for iz in (-0.5, 0.5):
                b.cyl(0.42, 0.2, ix, pivot_y - length * 0.42, bed + 0.1 + iz + 1.1, "charcoal", seg=10, rx=90 + 22)
        b.box(0.6, 0.6, 1.2, 0, pivot_y + 1.0, bed, dark, bevel=0.1)
    else:
        big = p.get("big", False)
        mlen = 15.0 if big else 12.0
        r = 0.95 if big else 0.78
        my = length * 0.28
        # erector arm
        b.box(0.5, 0.5, mlen * 0.8, -r - 0.3, my, bed, dark, bevel=0.06)
        b.box(0.5, 0.5, mlen * 0.8, r + 0.3, my, bed, dark, bevel=0.06)
        for zz in (mlen * 0.25, mlen * 0.55):
            b.box(2 * r + 1.1, 0.4, 0.4, 0, my, bed + zz, dark, bevel=0.05)
        b.between((0, my - 1.6, bed), (0, my, bed + 3.5), 0.3, "chrome")
        body = "white" if p.get("tint") != "dark" else "offwhite"
        nose = "charcoal" if p.get("tint") != "sand" else "red"
        missile(b, 0, my, bed + 0.3, mlen, r, body, nose, band=col)
        b.cyl(1.1, 0.4, 0, my, bed, dark, seg=10)


def drone_shape(part: Part, x, y, z, s=1.0, color="steel"):
    """Delta-wing loitering drone, nose toward -Y."""
    part.box(0.55 * s, 3.4 * s, 0.45 * s, x, y, z, color, bevel=0.15 * s, center=True)
    part.hexa([(x - 0.2 * s, y - 1.2 * s, z - 0.06 * s), (x + 0.2 * s, y - 1.2 * s, z - 0.06 * s), (x + 2.2 * s, y + 1.5 * s, z - 0.06 * s),
               (x - 2.2 * s, y + 1.5 * s, z - 0.06 * s), (x - 0.2 * s, y - 1.2 * s, z + 0.06 * s), (x + 0.2 * s, y - 1.2 * s, z + 0.06 * s),
               (x + 2.2 * s, y + 1.5 * s, z + 0.06 * s), (x - 2.2 * s, y + 1.5 * s, z + 0.06 * s)], color)
    part.box(0.1 * s, 0.6 * s, 0.6 * s, x - 2.0 * s, y + 1.25 * s, z - 0.06 * s, "gunmetal", bevel=0.0)
    part.box(0.1 * s, 0.6 * s, 0.6 * s, x + 2.0 * s, y + 1.25 * s, z - 0.06 * s, "gunmetal", bevel=0.0)
    part.cyl(0.32 * s, 0.25 * s, x, y + 1.7 * s, z, "charcoal", seg=8, rx=-90)
    part.cyl(0.25 * s, 0.5 * s, x, y - 1.7 * s, z, color, seg=8, rx=90, r2=0.05)


def drone_rack(m: Model, W, D, p):
    b = m.body
    plinth(m, W, D, "concrete")
    n = 4 if p.get("big") else 2
    col, dark = tints({"eastern": p.get("big")})
    deck = G + 0.9
    b.box(W - 1.0, D - 1.0, 0.9, 0, 0, G, dark, bevel=0.12)
    y_back, z_back = D / 2 - 1.3, deck + 0.9
    y_front, z_front = -D / 2 + 1.3, deck + 4.2
    angle = math.degrees(math.atan2(z_front - z_back, y_back - y_front))

    def rail_z(y):
        t = (y_back - y) / (y_back - y_front)
        return z_back + (z_front - z_back) * t

    for i in range(n):
        x = -W / 2 + 0.5 + (i + 0.5) * (W - 1.0) / n
        b.between((x, y_back, z_back), (x, y_front, z_front), 0.2, "gunmetal", seg=6)
        for yy in (y_back - 0.6, (y_back + y_front) / 2, y_front + 0.6):
            b.box(0.22, 0.22, rail_z(yy) - deck, x, yy, deck, "gunmetal", bevel=0.02)
        mid = (y_back + y_front) / 2
        with b.xform(place(x, mid, rail_z(mid) + 0.45, rx=-angle)):
            drone_shape(b, 0, 0, 0, 0.6, "sand" if not p.get("big") else "olive_l")
    b.box(1.4, 1.0, 1.0, W / 2 - 1.0, -D / 2 + 0.9, deck, "olive_l", bevel=0.1)


def jet_drone(part: Part, x, y, z, s=1.0, color="steel"):
    """Jet strike drone, nose toward -Y."""
    part.cyl(0.5 * s, 4.6 * s, x, y - 2.3 * s, z, color, seg=10, rx=-90, r2=0.32 * s)
    part.cyl(0.5 * s, 1.3 * s, x, y - 2.3 * s, z, color, seg=10, rx=90, r2=0.05)
    part.box(5.4 * s, 1.5 * s, 0.14 * s, x, y + 0.2 * s, z, color, bevel=0.05, center=True)
    part.box(2.0 * s, 0.8 * s, 0.12 * s, x, y + 2.0 * s, z, color, bevel=0.03, center=True)
    part.box(0.12 * s, 0.9 * s, 1.1 * s, x, y + 1.9 * s, z + 0.55 * s, color, bevel=0.03, center=True)
    part.cyl(0.32 * s, 1.4 * s, x, y + 0.6 * s, z + 0.45 * s, "gunmetal", seg=10, rx=-90)
    part.cyl(0.24 * s, 0.1 * s, x, y + 2.05 * s, z + 0.45 * s, "charcoal", seg=10, rx=-90)


def drone_ramp(m: Model, W, D, p):
    b = m.body
    col, dark = tints(p)
    plinth(m, W, D, "concrete")
    b.box(2.6, D - 2.0, 0.5, 0, 0.2, G + 2.3, "gunmetal", bevel=0.08, rx=-12, center=True)
    b.box(0.9, 1.0, 3.6, 0, -D / 2 + 2.2, G, dark, bevel=0.1)
    b.box(0.9, 1.0, 1.2, 0, D / 2 - 2.6, G, dark, bevel=0.1)
    with b.xform(place(0, 0.6, G + 3.2, rx=-12)):
        jet_drone(b, 0, 0, 0, 0.95, "olive_l" if col == "olive" else col)
    # small hangar
    b.box(W * 0.34, 4.0, 3.2, W * 0.3, D * 0.3, G, "olive_l", bevel=0.15)
    b.prism([(-2.2, 0), (2.2, 0), (0, 1.2)], W * 0.36, "x", W * 0.3, D * 0.3, G + 3.2, dark)


# ------------------------------------------------------------------- units
def unit_hull(part: Part, length, width, col, dark, tracked=True):
    z = 0.0
    if tracked:
        for sx in (-1, 1):
            x = sx * (width / 2 - 0.55)
            part.box(1.1, length, 1.25, x, 0, z, "tire", bevel=0.45)
            for i in range(5):
                part.cyl(0.42, 1.14, x - 0.57, -length / 2 + 1.0 + i * (length - 2.0) / 4, z + 0.5, "gunmetal", seg=10, ry=90)
            part.box(1.25, length - 0.4, 0.15, x, 0, z + 1.25, dark, bevel=0.03)
    else:
        n = 4
        for i in range(n):
            wy = -length / 2 + 1.2 + i * (length - 2.4) / (n - 1)
            for sx in (-1, 1):
                _wheel(part, sx * (width / 2 - 0.15), wy, z + 0.75, 0.75, 0.6)
    part.box(width - 1.0 if tracked else width - 0.6, length - 0.3, 1.3, 0, 0, z + 0.65, col, bevel=0.25)
    # sloped glacis at the front (-Y)
    part.hexa([(-width / 2 + 0.6, -length / 2 + 0.2, z + 1.9), (width / 2 - 0.6, -length / 2 + 0.2, z + 1.9),
               (width / 2 - 0.6, -length / 2 + 2.2, z + 2.2), (-width / 2 + 0.6, -length / 2 + 2.2, z + 2.2),
               (-width / 2 + 0.6, -length / 2 + 0.2, z + 1.95), (width / 2 - 0.6, -length / 2 + 0.2, z + 1.95),
               (width / 2 - 0.6, -length / 2 + 2.2, z + 2.25), (-width / 2 + 0.6, -length / 2 + 2.2, z + 2.25)], dark)


def u_truck(m: Model, p):
    b = m.body
    col, dark = tints(p)
    b.box(3.0, 8.0, 0.5, 0, 0, 1.0, dark, bevel=0.08)
    b.box(3.2, 2.6, 2.3, 0, -2.6, 1.2, col, bevel=0.3)
    b.box(2.9, 0.2, 0.8, 0, -3.92, 2.4, "glass_d", bevel=0.03)
    b.box(3.3, 4.6, 0.3, 0, 1.4, 1.5, dark, bevel=0.05)
    b.box(3.3, 4.6, 2.2, 0, 1.4, 1.8, "olive_l" if col == "olive" else col, bevel=0.35)
    for wy in (-2.6, 0.8, 2.8):
        for sx in (-1, 1):
            _wheel(b, sx * 1.45, wy, 0.75, 0.75, 0.55)
    m.marker("Front", (0, -4.2, 1.5))


def u_ifv(m: Model, p):
    b = m.body
    col, dark = tints(p)
    wheeled = p.get("wheeled", False)
    unit_hull(b, 8.8, 4.4, col, dark, tracked=not wheeled)
    b.box(2.4, 2.8, 1.0, 0, 0.2, 1.95, col, bevel=0.25)
    b.box(1.8, 2.2, 0.35, 0, 0.3, 2.95, dark, bevel=0.1)
    b.cyl(0.14, 3.2, 0, -1.0, 2.55, "gunmetal", seg=6, rx=90)
    b.box(0.6, 0.5, 0.5, 0.9, -0.9, 2.95, "glass_d", bevel=0.08)
    b.box(3.4, 0.2, 0.6, 0, 4.35, 0.9, dark, bevel=0.05)
    m.marker("Front", (0, -4.6, 1.5))


def u_tank(m: Model, p):
    b = m.body
    col, dark = tints(p)
    unit_hull(b, 9.8, 5.0, col, dark, tracked=True)
    # wide angular turret with a long gun
    b.hexa([(-2.1, -1.9, 1.95), (2.1, -1.9, 1.95), (2.2, 2.8, 1.95), (-2.2, 2.8, 1.95),
            (-1.5, -1.3, 3.45), (1.5, -1.3, 3.45), (1.8, 2.6, 3.45), (-1.8, 2.6, 3.45)], col, bevel=0.12)
    b.box(3.4, 1.4, 0.9, 0, 3.1, 2.2, dark, bevel=0.15)
    b.cyl(0.26, 7.0, 0, -1.6, 2.7, "gunmetal", seg=10, rx=90)
    b.cyl(0.38, 1.1, 0, -7.4, 2.7, dark, seg=10, rx=90)
    b.cyl(0.55, 0.5, 0.9, 1.0, 3.45, dark, seg=10)
    b.cyl(0.5, 0.4, -0.9, 0.4, 3.45, dark, seg=10)
    b.box(0.5, 0.5, 0.35, 1.6, -1.0, 3.2, "glass_d", bevel=0.05)
    m.marker("Front", (0, -5.0, 1.5))


def u_mlrs(m: Model, p):
    b = m.body
    col, dark = tints(p)
    b.box(3.0, 9.0, 0.6, 0, 0, 1.0, dark, bevel=0.08)
    b.box(3.2, 2.6, 2.4, 0, -3.2, 1.2, col, bevel=0.3)
    b.box(2.9, 0.2, 0.8, 0, -4.52, 2.5, "glass_d", bevel=0.03)
    for wy in (-3.2, 1.4, 3.4):
        for sx in (-1, 1):
            _wheel(b, sx * 1.45, wy, 0.75, 0.75, 0.55)
    if p.get("gun"):
        b.box(2.4, 3.0, 1.0, 0, 2.2, 1.6, col, bevel=0.2)
        b.cyl(0.28, 8.0, 0, 3.0, 2.4, "gunmetal", seg=8, rx=90 - 14)
        b.cyl(0.45, 0.8, 0, -4.6, 4.3, dark, seg=8, rx=90 - 14)
    else:
        b.box(2.8, 4.6, 2.2, 0, 1.8, 2.9, col, bevel=0.2, rx=-12, center=True)
        for ix in (-0.7, 0.0, 0.7):
            for iz in (-0.45, 0.45):
                b.cyl(0.25, 0.2, ix, -0.45, 2.9 + iz + 0.4, "charcoal", seg=8, rx=90 - 12)
    m.marker("Front", (0, -4.8, 1.5))


def u_spaag(m: Model, p):
    b = m.body
    col, dark = tints(p)
    unit_hull(b, 9.0, 4.6, col, dark, tracked=True)
    b.box(3.0, 3.2, 1.6, 0, 0.6, 1.95, col, bevel=0.3)
    for sx in (-1, 1):
        b.box(0.5, 1.2, 0.8, sx * 1.75, 0.0, 2.4, dark, bevel=0.1)
        b.cyl(0.13, 3.6, sx * 1.75, -0.2, 2.8, "gunmetal", seg=6, rx=90)
    b.box(2.2, 0.25, 1.4, 0, 2.2, 3.6, "white", bevel=0.1, rx=-15)
    b.cyl(0.5, 0.5, 0, -0.6, 3.55, "white", seg=10)
    b.dome(0.5, 0, -0.6, 4.05, "white", seg=10, rings=3)
    m.marker("Front", (0, -4.7, 1.5))


UNIT_STYLES = {"truck": u_truck, "ifv": u_ifv, "tank": u_tank, "mlrs": u_mlrs, "spaag": u_spaag}


# -------------------------------------------------------------- projectiles
def projectile(m: Model, wid: str, kind: str):
    b = m.body
    if kind == "drone":
        if wid == "RAPTOR":
            jet_drone(b, 0, 0, 0, 0.9, "olive_l")
        else:
            drone_shape(b, 0, 0, 0, 1.0, "sand")
    else:
        spec = {
            "SRBM": (6.0, 0.48, "olive", "white"),
            "GLCM": (4.6, 0.38, "alu", "alu"),
            "MRBM": (7.4, 0.55, "offwhite", "red"),
            "CLUSTER": (6.6, 0.52, "sand", "yellow"),
            "HYPERSONIC": (6.4, 0.42, "gunmetal", "cyan"),
        }.get(wid, (6.0, 0.45, "white", "red"))
        length, r, body, band = spec
        # lying along Y, nose at -Y
        b.cyl(r, length * 0.8, 0, length * 0.4, 0, body, seg=12, rx=90)
        b.cyl(r, length * 0.2, 0, -length * 0.4, 0, band if wid != "GLCM" else "charcoal", seg=12, rx=90, r2=0.05)
        b.cyl(r + 0.03, 0.3, 0, length * 0.1, 0, band, seg=12, rx=90)
        for k in range(4):
            a = math.radians(45 + 90 * k)
            b.box(0.06, 0.9, r * 2.6, math.cos(a) * r, length * 0.32, math.sin(a) * r, "gunmetal", bevel=0.0, ry=math.degrees(a), center=True)
        if wid == "GLCM":
            b.box(3.2, 0.7, 0.08, 0, 0.1, 0, "alu", bevel=0.02, center=True)
    m.marker("Front", (0, -4.0, 0))


def fuel_truck(m: Model):
    b = m.body
    b.box(3.0, 7.8, 0.5, 0, 0, 1.0, "gunmetal", bevel=0.08)
    b.box(3.1, 2.4, 2.2, 0, -2.8, 1.2, "white", bevel=0.3)
    b.box(2.8, 0.2, 0.8, 0, -4.0, 2.3, "glass_d", bevel=0.03)
    b.box(3.12, 0.6, 0.5, 0, -2.6, 2.3, "orange", bevel=0.05)
    b.cyl(1.35, 5.0, 0, 3.4, 2.75, "chrome", seg=14, rx=90)
    b.cyl(1.4, 0.4, 0, 1.0, 2.75, "orange", seg=14, rx=90)
    b.cyl(1.4, 0.4, 0, 3.4, 2.75, "orange", seg=14, rx=90)
    for wy in (-2.8, 1.3, 3.1):
        for sx in (-1, 1):
            _wheel(b, sx * 1.4, wy, 0.7, 0.7, 0.5)
    m.marker("Front", (0, -4.2, 1.5))


MIL_STYLES = {
    "researchLab": research_lab,
    "university": university,
    "milResearch": mil_research,
    "depot": depot,
    "radar": radar,
    "ciws": ciws,
    "sam": sam,
    "laser": laser,
    "launcher": launcher,
    "droneRack": drone_rack,
    "droneRamp": drone_ramp,
}
