"""
Civilian building styles. Each style is fn(model, W, D, params) where W/D are
the footprint in studs (X/Y). Ground is Z = 0; the plinth top is G.
"""

import math
import random

from .geo import Model

G = 0.45  # plinth height


def plinth(m: Model, W, D, color="concrete_l", trim="concrete"):
    b = m.body
    b.box(W - 0.15, D - 0.15, G - 0.1, 0, 0, 0, trim, bevel=0.12)
    b.box(W - 0.5, D - 0.5, 0.1, 0, 0, G - 0.1, color, bevel=0.04)


def bush(part, x, y, s=1.0, color="leaf"):
    part.sphere(0.9 * s, x, y, G + 0.6 * s, color, subd=1)
    part.sphere(0.6 * s, x + 0.5 * s, y + 0.2 * s, G + 0.9 * s, "leaf_d" if color == "leaf" else "leaf", subd=1)


def tree(part, x, y, s=1.0, z=None, kind=0):
    base = G if z is None else z
    part.cyl(0.22 * s, 2.2 * s, x, y, base, "wood", seg=6)
    if kind == 0:
        part.sphere(1.5 * s, x, y, base + 3.0 * s, "leaf", subd=1)
        part.sphere(1.05 * s, x + 0.6 * s, y - 0.3 * s, base + 3.9 * s, "grass", subd=1)
    elif kind == 1:  # conifer
        part.cyl(1.5 * s, 2.0 * s, x, y, base + 1.4 * s, "leaf_d", seg=7, r2=0.7 * s)
        part.cyl(1.1 * s, 1.8 * s, x, y, base + 2.9 * s, "leaf_d", seg=7, r2=0.05)
    else:  # round shrub tree
        part.sphere(1.25 * s, x, y, base + 2.6 * s, "grass_l", subd=1)


def lamp(part, x, y, h=4.5):
    part.cyl(0.12, h, x, y, G, "gunmetal", seg=6)
    part.box(0.6, 0.25, 0.2, x + 0.2, y, G + h - 0.1, "gunmetal", bevel=0.04)


def rooftop_units(part, w, d, x, y, z, count=2, seed=1):
    rnd = random.Random(seed)
    for i in range(count):
        ux = x + (i - (count - 1) / 2) * (w / max(count, 1)) * 0.7
        uy = y + rnd.uniform(-d * 0.2, d * 0.2)
        part.box(1.8, 1.4, 1.0, ux, uy, z, "alu", bevel=0.1)
        part.cyl(0.45, 0.15, ux + 0.3, uy, z + 1.0, "gunmetal", seg=8)


# ---------------------------------------------------------------- housing
def house(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "grass")
    wall = "cream" if p.get("roof") != "slate" else "offwhite"
    roof = "roof_s" if p.get("roof") == "slate" else "roof_r"
    long = p.get("long", False)
    bw, bd = W - 2.0, D - 2.6
    oy = 0.5
    h = 4.4
    # path to the door
    b.box(1.4, (D - bd) / 2 - oy + 0.4, 0.06, -1.0, -D / 2 + ((D - bd) / 2 - oy) / 2 + 0.1, G, "concrete_l", bevel=0.02)
    b.box(bw, bd, 0.45, 0, oy, G, "concrete", bevel=0.1)
    b.box(bw - 0.1, bd - 0.1, h, 0, oy, G + 0.45, wall, bevel=0.14)
    # corner trims
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box(0.35, 0.35, h, sx * (bw / 2 - 0.1), oy + sy * (bd / 2 - 0.1), G + 0.45, "white", bevel=0.05)
    top = G + 0.45 + h
    ridge = "y" if long else "x"
    span = bw if long else bd
    length = bd if long else bw
    b.gable_fill(span, length, 0, oy, top, wall, pitch=34, ridge_axis=ridge)
    b.gable_roof(span, length, 0, oy, top, roof, pitch=34, overhang=0.55, ridge_axis=ridge)
    # chimney
    b.box(0.9, 0.9, 3.2, bw * 0.25, oy + bd * 0.15, top, "brick", bevel=0.08)
    b.box(1.1, 1.1, 0.25, bw * 0.25, oy + bd * 0.15, top + 3.2, "concrete", bevel=0.05)
    # door + frame + step + canopy
    fy = oy - bd / 2
    b.box(1.6, 0.18, 2.9, -1.0, fy - 0.05, G + 0.45, "white", bevel=0.05)
    b.box(1.2, 0.2, 2.6, -1.0, fy - 0.12, G + 0.45, "wood", bevel=0.04)
    b.box(2.0, 0.9, 0.3, -1.0, fy - 0.45, G, "concrete_l", bevel=0.06)
    b.box(2.0, 1.0, 0.15, -1.0, fy - 0.5, G + 3.2, roof, bevel=0.05)
    # windows with frames and sills
    def win(x, y, z, side):
        if side in "ns":
            b.box(1.45, 0.16, 1.45, x, y, z - 0.12, "white", bevel=0.04)
            L.box(1.15, 0.2, 1.15, x, y + (-0.04 if side == "s" else 0.04), z, "glass", bevel=0.02)
            b.box(1.6, 0.35, 0.14, x, y + (-0.15 if side == "s" else 0.15), z - 0.2, "white", bevel=0.03)
        else:
            b.box(0.16, 1.45, 1.45, x, y, z - 0.12, "white", bevel=0.04)
            L.box(0.2, 1.15, 1.15, x + (-0.04 if side == "w" else 0.04), y, z, "glass", bevel=0.02)
    z1 = G + 2.1
    win(1.4, fy - 0.05, z1, "s")
    win(1.4, oy + bd / 2 + 0.05, z1, "n")
    win(-1.4, oy + bd / 2 + 0.05, z1, "n")
    win(-bw / 2 - 0.05, oy, z1, "w")
    win(bw / 2 + 0.05, oy, z1, "e")
    if long:
        win(-bw / 2 - 0.05, oy + bd * 0.3, z1, "w")
        win(bw / 2 + 0.05, oy - bd * 0.3, z1, "e")
        # dormer
        b.box(1.8, 1.4, 1.6, 0, oy - bd * 0.1, top + 0.4, wall, bevel=0.08)
        L.box(1.1, 0.2, 0.9, 0, oy - bd * 0.1 - 0.75, top + 0.8, "glass", bevel=0.02)
        b.gable_roof(1.8, 1.6, 0, oy - bd * 0.1, top + 2.0, roof, pitch=35, overhang=0.2, ridge_axis="y")
    # garden
    bush(b, W / 2 - 1.0, -D / 2 + 1.0, 0.8)
    bush(b, -W / 2 + 0.9, D / 2 - 0.9, 0.7)
    for i in range(4):
        b.box(0.15, 0.15, 0.8, W / 2 - 0.4, -D / 2 + 0.4 + i * 1.1, G, "wood", bevel=0.02)
    b.box(0.1, 3.4, 0.12, W / 2 - 0.4, -D / 2 + 2.05, G + 0.55, "wood", bevel=0.02)


def townhouse(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    n = p.get("count", 3)
    each = (W - 0.6) / n
    walls = ["cream", "beige", "ppink", "pblue"]
    roofs = ["roof_r", "roof_s", "roof_r", "roof_g"]
    bd = D - 2.2
    for i in range(n):
        x = -W / 2 + 0.3 + each * (i + 0.5)
        h = 6.4 + (i % 2) * 0.8
        wall = walls[i % len(walls)]
        b.box(each - 0.2, bd, h, x, 0.4, G, wall, bevel=0.12)
        b.box(each - 0.05, bd + 0.2, 0.3, x, 0.4, G + 3.1, "white", bevel=0.05)  # floor band
        b.gable_fill(bd, each - 0.2, x, 0.4, G + h, wall, pitch=30, ridge_axis="x")
        b.gable_roof(bd, each - 0.2, x, 0.4, G + h, roofs[i % len(roofs)], pitch=30, overhang=0.3, ridge_axis="x")
        fy = 0.4 - bd / 2
        b.box(1.3, 0.2, 2.6, x - each * 0.22, fy - 0.08, G, "wood", bevel=0.04)
        b.box(1.8, 1.1, 0.35, x - each * 0.22, fy - 0.55, G, "concrete", bevel=0.06)
        for fl in range(2):
            z = G + 1.3 + fl * 3.0
            L.box(1.4, 0.2, 1.4, x + each * 0.2, fy - 0.07, z, "glass", bevel=0.02)
            b.box(1.6, 0.4, 0.14, x + each * 0.2, fy - 0.2, z - 0.15, "white", bevel=0.03)
            L.box(1.4, 0.2, 1.4, x, 0.4 + bd / 2 + 0.07, z, "glass", bevel=0.02)
        L.box(1.2, 0.2, 1.2, x - each * 0.22, fy - 0.07, G + 4.3, "glass", bevel=0.02)
        b.box(0.7, 0.7, 2.2, x + each * 0.25, 0.4 + bd * 0.2, G + h + 0.6, "brick", bevel=0.06)
    bush(b, -W / 2 + 1.0, -D / 2 + 0.9, 0.6)
    bush(b, W / 2 - 1.0, -D / 2 + 0.9, 0.6)


def apartment(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    floors = p.get("floors", 4)
    fh = 3.2
    bw, bd = W - 1.6, D - 2.6
    oy = 0.3
    base_h = 1.0
    b.box(bw, bd, base_h, 0, oy, G, "grey_d", bevel=0.1)
    h = floors * fh
    b.box(bw - 0.2, bd - 0.2, h, 0, oy, G + base_h, "offwhite", bevel=0.15)
    # floor slabs and vertical fins give the facade rhythm
    for f in range(1, floors + 1):
        b.box(bw + 0.25, bd + 0.25, 0.28, 0, oy, G + base_h + f * fh - 0.28, "concrete_l", bevel=0.06)
    fins = max(2, int(bw // 6))
    for i in range(fins + 1):
        fx = -bw / 2 + 0.2 + i * (bw - 0.4) / fins
        for sy in (-1, 1):
            b.box(0.35, 0.5, h, fx, oy + sy * (bd / 2 + 0.05), G + base_h, "white", bevel=0.06)
    L.window_grid(bw - 0.2, bd - 0.2, 0, oy, G + base_h, floors, fh, win_w=1.7, gap=1.25, color="glass")
    # balconies on the front
    bays = max(1, fins)
    for f in range(1, floors):
        for i in range(bays):
            bx = -bw / 2 + (i + 0.5) * bw / bays
            if (i + f) % 2 == 0:
                z = G + base_h + f * fh
                b.box(2.4, 1.0, 0.18, bx, oy - bd / 2 - 0.55, z - 0.05, "concrete_l", bevel=0.05)
                b.box(2.4, 0.1, 0.8, bx, oy - bd / 2 - 1.0, z + 0.1, "grey", bevel=0.03)
    # stairwell tower + entrance canopies
    top = G + base_h + h
    b.box(3.0, 2.6, h + 1.6, -bw * 0.25, oy + bd / 2 - 1.0, G + base_h, "concrete", bevel=0.12)
    doors = max(1, int(bw // 12))
    for i in range(doors):
        dx = -bw / 2 + (i + 0.5) * bw / doors
        b.box(2.0, 0.2, 2.4, dx, oy - bd / 2 - 0.08, G + 0.2, "glass_d", bevel=0.03)
        b.box(3.2, 1.6, 0.2, dx, oy - bd / 2 - 0.8, G + 2.8, "charcoal", bevel=0.05)
    # roof
    b.box(bw + 0.1, bd + 0.1, 0.5, 0, oy, top, "grey", bevel=0.1)
    b.box(bw - 0.8, bd - 0.8, 0.1, 0, oy, top + 0.5, "charcoal", bevel=0.03)
    rooftop_units(b, bw, bd, 0, oy, top + 0.5, count=max(2, int(bw // 9)), seed=floors)
    b.cyl(0.9, 1.6, bw * 0.3, oy + bd * 0.15, top + 0.5, "alu", seg=10)


def tower(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    floors = p.get("floors", 16)
    fh = 3.1
    pw, pd = W - 1.0, D - 1.0
    b.box(pw, pd, 4.2, 0, 0, G, "grey_d", bevel=0.15)
    L.box(pw - 1.6, 0.2, 2.6, 0, -pd / 2 - 0.05, G + 0.6, "glass_l", bevel=0.03)
    tw, td = W - 3.4, D - 3.4
    z0 = G + 4.2
    h = floors * fh
    b.box(tw, td, h, 0, 0, z0, "glass_d", bevel=0.15)
    # corner columns + floor bands
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box(0.8, 0.8, h + 1.0, sx * (tw / 2 - 0.2), sy * (td / 2 - 0.2), z0, "offwhite", bevel=0.1)
    for f in range(1, floors + 1):
        b.box(tw + 0.2, td + 0.2, 0.25, 0, 0, z0 + f * fh - 0.25, "offwhite", bevel=0.05)
    L.window_grid(tw - 0.8, td - 0.8, 0, 0, z0, floors, fh, win_w=1.3, gap=0.5, color="glass_l", margin=0.6)
    top = z0 + h
    # stepped crown
    b.box(tw - 1.6, td - 1.6, 2.4, 0, 0, top, "offwhite", bevel=0.15)
    b.box(tw - 3.2, td - 3.2, 1.6, 0, 0, top + 2.4, "alu", bevel=0.12)
    b.cyl(0.18, 7.0, 0, 0, top + 4.0, "steel", seg=6)
    L.sphere(0.35, 0, 0, top + 11.1, "red", subd=1)


# ------------------------------------------------------------------ roads
def road(m: Model, W, D, p):
    b = m.body
    b.box(W, D, 0.3, 0, 0, 0, "asphalt", bevel=0.03)
    # subtle centre studs that read as lane markings when tiles join
    b.box(0.35, 1.1, 0.04, 0, 0, 0.3, "line", bevel=0.01)
    b.box(1.1, 0.35, 0.04, 0, 0, 0.3, "line", bevel=0.01)


def plaza(m: Model, W, D, p):
    b, L = m.body, m.lights
    b.box(W - 0.1, D - 0.1, 0.35, 0, 0, 0, "concrete", bevel=0.08)
    n = 4
    s = (W - 0.6) / n
    for i in range(n):
        for j in range(n):
            if (i + j) % 2 == 0:
                b.box(s - 0.08, s - 0.08, 0.06, -W / 2 + 0.3 + (i + 0.5) * s, -D / 2 + 0.3 + (j + 0.5) * s, 0.35, "concrete_l", bevel=0.02)
    b.cyl(3.0, 0.7, 0, 0, 0.35, "concrete_l", seg=16, bevel=0.1)
    b.cyl(2.6, 0.72, 0, 0, 0.38, "water", seg=16)
    b.cyl(0.6, 1.4, 0, 0, 0.35, "concrete_l", seg=10)
    b.cyl(1.2, 0.3, 0, 0, 1.75, "concrete_l", seg=12)
    for sx, sy in ((-1, -1), (1, 1)):
        tree(b, sx * (W / 2 - 1.6), sy * (D / 2 - 1.6), 0.8, z=0.4)
    for sx, sy in ((1, -1), (-1, 1)):
        lamp(b, sx * (W / 2 - 1.2), sy * (D / 2 - 1.2))
        L.sphere(0.25, sx * (W / 2 - 1.0), sy * (D / 2 - 1.2), G + 4.3, "glow", subd=1)
    b.box(2.2, 0.6, 0.45, 0, -D / 2 + 1.0, 0.35, "wood", bevel=0.06)


# -------------------------------------------------------------- utilities
def wind_turbine(m: Model, W, D, p):
    b = m.body
    plinth(m, W, D, "concrete_l")
    b.cyl(1.4, 0.6, 0, 0, G, "concrete", seg=12, bevel=0.1)
    b.cyl(0.85, 32.0, 0, 0, G + 0.6, "white", seg=12, r2=0.42)
    b.box(0.5, 0.1, 1.6, 0, -0.85, G + 0.6, "grey", bevel=0.03)  # door
    top = G + 32.6
    b.box(1.3, 3.6, 1.3, 0, 0.6, top - 0.2, "white", bevel=0.35)
    b.box(1.32, 0.6, 1.32, 0, 1.6, top - 0.21, "teal", bevel=0.2)
    hub_y = -1.35
    rotor = m.part("Rotor", pivot=(0, hub_y, top + 0.45))
    rotor.cyl(0.55, 0.9, 0, hub_y + 0.45, top + 0.45, "white", seg=12, rx=90, r2=0.1)
    rotor.cyl(0.6, 0.5, 0, hub_y + 0.6, top + 0.45, "white", seg=12, rx=90)
    cx, cz = 0.0, top + 0.45
    blade_len = 13.0
    root_w, tip_w = 0.85, 0.25
    for k in range(3):
        a = math.radians(k * 120)

        def pt(along, across, dy, a=a):
            # blade direction rotates by angle a in the rotor plane (XZ)
            return (cx + math.sin(a) * along + math.cos(a) * across,
                    hub_y + dy,
                    cz + math.cos(a) * along - math.sin(a) * across)

        rotor.hexa([pt(0.5, -root_w / 2, -0.14), pt(0.5, root_w / 2, -0.14), pt(0.5, root_w / 2, 0.14), pt(0.5, -root_w / 2, 0.14),
                    pt(blade_len, -tip_w / 2, -0.05), pt(blade_len, tip_w / 2, -0.05), pt(blade_len, tip_w / 2, 0.05), pt(blade_len, -tip_w / 2, 0.05)],
                   "white")
        tip = pt(blade_len - 0.8, 0, 0)
        rotor.box(0.32, 0.22, 0.32, tip[0], tip[1], tip[2], "red", bevel=0.0, center=True)
    m.marker("Spin", (0, hub_y, top + 0.45))


def solar_farm(m: Model, W, D, p):
    b = m.body
    plinth(m, W, D, "grass")
    rows = int((D - 2) // 4.2)
    for r in range(rows):
        y = -D / 2 + 2.6 + r * 4.2
        for x in (-W * 0.28, W * 0.28):
            b.box(0.25, 0.25, 1.3, x - 2.5, y, G, "steel", bevel=0.03)
            b.box(0.25, 0.25, 1.3, x + 2.5, y, G, "steel", bevel=0.03)
        b.box(W - 2.6, 3.0, 0.18, 0, y, G + 1.5, "navy", bevel=0.04, rx=-25, center=True)
        b.box(W - 2.6, 0.12, 0.2, 0, y - 1.36, G + 2.15, "alu", bevel=0.02, rx=-25, center=True)
    b.box(2.0, 1.6, 1.8, W / 2 - 1.6, -D / 2 + 1.4, G, "alu", bevel=0.12)
    for i in range(int(W // 3)):
        b.box(0.12, 0.12, 1.2, -W / 2 + 0.5 + i * 3, -D / 2 + 0.4, G, "grey", bevel=0.02)


def cooling_tower(part, x, y, scale=1.0, z=G):
    s = scale
    prof = [(7.0 * s, 0), (6.1 * s, 4 * s), (5.2 * s, 9 * s), (4.9 * s, 13 * s), (5.2 * s, 16 * s), (5.6 * s, 18 * s)]
    part.lathe(prof, x, y, z, "offwhite", seg=24, cap_bottom=False, cap_top=False)
    inner = [(r - 0.35 * s, h) for (r, h) in prof]
    part.lathe(inner, x, y, z, "grey", seg=24, cap_bottom=False, cap_top=False, inward=True)
    # rim and red band
    part.lathe([(5.6 * s, 18 * s), (5.25 * s, 18 * s)], x, y, z, "offwhite", seg=24, cap_bottom=False, cap_top=False)
    part.lathe([(5.25 * s, 15.6 * s), (5.42 * s, 16.8 * s)], x, y, z + 0.02, "red", seg=24, cap_bottom=False, cap_top=False)
    part.cyl(4.9 * s, 0.2, x, y, z + 2 * s, "charcoal", seg=24)  # dark interior floor
    for i in range(12):  # support legs
        a = 2 * math.pi * i / 12
        part.box(0.4 * s, 0.4 * s, 1.0 * s, x + math.cos(a) * 6.9 * s, y + math.sin(a) * 6.9 * s, z, "concrete", bevel=0.05)


def striped_stack(part, x, y, h, r, z=G):
    seg = h / 6
    for i in range(6):
        part.cyl(r, seg, x, y, z + i * seg, "white" if i % 2 == 0 else "red", seg=12)
    part.cyl(r + 0.2, 0.4, x, y, z + h, "charcoal", seg=12)


def coal_plant(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete")
    hx, hy = -W * 0.18, -D * 0.12
    hw, hd = W * 0.52, D * 0.55
    b.box(hw, hd, 12.0, hx, hy, G, "pblue", bevel=0.2)
    for i in range(int(hw // 3)):
        b.box(0.3, hd + 0.2, 12.0, hx - hw / 2 + 1.5 + i * 3, hy, G, "steelblue", bevel=0.05)
    L.window_grid(hw, hd, hx, hy, G + 6.5, 1, 4.0, win_w=2.2, gap=0.8, color="glass", sides="s")
    b.prism([(-hd / 2 - 0.4, 0), (hd / 2 + 0.4, 0), (0, 2.4)], hw + 0.6, "x", hx, hy, G + 12.0, "steelblue")
    b.box(W * 0.26, D * 0.32, 19.0, -W * 0.3, D * 0.28, G, "alu", bevel=0.2)
    b.box(W * 0.28, D * 0.34, 0.6, -W * 0.3, D * 0.28, G + 19.0, "grey_d", bevel=0.1)
    striped_stack(b, -W * 0.06, D * 0.34, 36, 1.4)
    striped_stack(b, -W * 0.17, D * 0.34, 36, 1.4)
    cooling_tower(b, W * 0.27, -D * 0.1, 0.95)
    # coal pile + conveyor
    b.sphere(4.2, W * 0.3, D * 0.34, G - 1.6, "black", subd=1, sz=0.55)
    b.box(1.2, D * 0.35, 0.7, W * 0.13, D * 0.3, G + 6, "rust", bevel=0.08, rx=18, center=True)
    b.between((W * 0.3 - 2, D * 0.2, G), (W * 0.13, D * 0.18, G + 4.5), 0.2, "steel")


def nuclear_plant(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete")
    cooling_tower(b, -W * 0.27, -D * 0.18, 1.35)
    cooling_tower(b, W * 0.03, -D * 0.22, 1.35)
    # containment
    rx, ry = W * 0.3, D * 0.2
    b.cyl(7.5, 11.0, rx, ry, G, "offwhite", seg=24, bevel=0.2)
    b.cyl(7.8, 0.6, rx, ry, G + 4.0, "teal", seg=24)
    b.dome(7.5, rx, ry, G + 11.0, "white", seg=24, rings=7)
    # turbine hall
    tx, ty = -W * 0.14, D * 0.3
    b.box(W * 0.5, D * 0.27, 10.0, tx, ty, G, "pblue", bevel=0.2)
    b.prism([(-D * 0.14, 0), (D * 0.14, 0), (D * 0.1, 1.8), (-D * 0.1, 1.8)], W * 0.5, "x", tx, ty, G + 10.0, "steelblue")
    L.window_grid(W * 0.5, D * 0.27, tx, ty, G + 5.5, 1, 4.0, win_w=2.6, gap=1.0, color="glass_l", sides="s")
    b.box(W * 0.5 + 0.2, 0.3, 0.8, tx, ty - D * 0.135 - 0.1, G + 9.0, "teal", bevel=0.05)
    # switchyard
    for i in range(4):
        y = -D * 0.42 + i * 3.6
        b.box(0.5, 0.5, 7.0, W * 0.44, y, G, "steel", bevel=0.05)
        b.box(3.0, 0.3, 0.3, W * 0.44, y, G + 6.4, "steel", bevel=0.03)
    b.box(2.6, 2.6, 2.6, W * 0.38, D * 0.42, G, "grey", bevel=0.15)


def water_tower(m: Model, W, D, p):
    b = m.body
    plinth(m, W, D, "concrete_l")
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.between((sx * 2.4, sy * 2.4, G), (sx * 1.4, sy * 1.4, G + 14.5), 0.22, "steel", seg=6)
    for z in (G + 4.5, G + 9.5):
        k = 2.4 - (z - G) / 14.5 * 1.0
        for (a, c) in (((-k, -k), (k, -k)), ((k, -k), (k, k)), ((k, k), (-k, k)), ((-k, k), (-k, -k))):
            b.between((a[0], a[1], z), (c[0], c[1], z), 0.12, "steel", seg=6)
    b.cyl(0.4, 14.5, 0, 0, G, "alu", seg=8)
    b.cyl(3.4, 1.0, 0, 0, G + 14.3, "white", seg=16, r2=3.9)
    b.sphere(3.9, 0, 0, G + 17.6, "white", uv=(18, 10), sz=0.82)
    b.cyl(3.95, 0.6, 0, 0, G + 16.6, "teal", seg=18)
    b.cyl(0.5, 0.6, 0, 0, G + 20.6, "white", seg=8)


def pump_station(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    bx, by = -W * 0.2, -D * 0.22
    bw, bd = W * 0.48, D * 0.42
    b.box(bw, bd, 6.0, bx, by, G, "beige", bevel=0.15)
    b.gable_fill(bd, bw, bx, by, G + 6.0, "beige", pitch=22, ridge_axis="x")
    b.gable_roof(bd, bw, bx, by, G + 6.0, "roof_b", pitch=22, overhang=0.4, ridge_axis="x")
    L.window_grid(bw, bd, bx, by, G + 2.4, 1, 3.0, win_w=1.6, gap=1.0, color="glass", sides="se")
    for x in (W * 0.2, -W * 0.18):
        y = D * 0.24
        b.cyl(D * 0.19, 1.4, x, y, G, "concrete", seg=20, bevel=0.1)
        b.cyl(D * 0.17, 1.42, x, y, G, "water", seg=20)
        b.box(D * 0.36, 0.3, 0.3, x, y, G + 1.6, "steel", bevel=0.03)
    b.between((bx + bw / 2, by, G + 1.2), (W * 0.2, D * 0.24 - D * 0.19, G + 1.2), 0.45, "steelblue")
    b.between((-W * 0.18, D * 0.05, G + 1.2), (bx, by + bd / 2, G + 1.2), 0.45, "steelblue")


# -------------------------------------------------------------- industry
def oil_pump(m: Model, W, D, p):
    b = m.body
    plinth(m, W, D, "dirt", "concrete")
    b.box(2.6, D - 1.2, 0.6, 0, 0, G, "gunmetal", bevel=0.08)
    # samson post
    for sx in (-1, 1):
        b.between((sx * 0.9, -0.3, G + 0.6), (sx * 0.15, 0.2, G + 5.4), 0.16, "gunmetal", seg=6)
        b.between((sx * 0.9, 1.1, G + 0.6), (sx * 0.15, 0.2, G + 5.4), 0.16, "gunmetal", seg=6)
    # motor + crank
    b.box(1.3, 1.4, 1.2, 0, D / 2 - 1.5, G + 0.6, "orange", bevel=0.12)
    b.cyl(0.5, 0.3, 0.8, D / 2 - 2.2, G + 1.5, "gunmetal", seg=10, ry=90)
    beam = m.part("Beam", pivot=(0, 0.2, G + 5.6))
    beam.box(0.55, D - 1.0, 0.65, 0, 0.2, G + 5.3, "yellow", bevel=0.1)
    # horse head at -Y
    beam.hexa([(-0.4, -D / 2 + 0.1, G + 3.9), (0.4, -D / 2 + 0.1, G + 3.9), (0.4, -D / 2 + 1.2, G + 5.2), (-0.4, -D / 2 + 1.2, G + 5.2),
               (-0.4, -D / 2 - 0.1, G + 6.3), (0.4, -D / 2 - 0.1, G + 6.3), (0.4, -D / 2 + 1.2, G + 6.0), (-0.4, -D / 2 + 1.2, G + 6.0)], "yellow")
    beam.box(1.0, 0.9, 0.9, 0, D / 2 - 1.0, G + 4.8, "gunmetal", bevel=0.1)
    b.cyl(0.08, 4.6, 0, -D / 2 + 0.55, G + 0.3, "chrome", seg=6)
    b.cyl(0.35, 0.6, 0, -D / 2 + 0.55, G, "gunmetal", seg=8)
    m.marker("Spin", (0, 0.2, G + 5.6))


def tank(part, x, y, r, h, color="white", z=G, ladder=True):
    part.cyl(r, h, x, y, z, color, seg=20, bevel=0.15)
    part.cyl(r + 0.08, 0.3, x, y, z + h * 0.5, "alu", seg=20)
    part.cyl(r * 0.95, 0.45, x, y, z + h, "alu", seg=20, r2=r * 0.6)
    if ladder:
        part.box(0.5, 0.15, h, x + r + 0.1, y, z, "steel", bevel=0.02)


def oil_tank(m: Model, W, D, p):
    b = m.body
    plinth(m, W, D, "concrete")
    b.box(W - 0.6, 0.3, 0.8, 0, -D / 2 + 0.45, G, "concrete_l", bevel=0.06)
    b.box(W - 0.6, 0.3, 0.8, 0, D / 2 - 0.45, G, "concrete_l", bevel=0.06)
    for sx in (-1, 1):
        for sy in (-1, 1):
            tank(b, sx * W / 4, sy * D / 4, W / 4 - 0.6, 4.6, "offwhite", ladder=sx > 0)
    b.between((-W / 4, 0, G + 0.6), (W / 4, 0, G + 0.6), 0.25, "steel")


def refinery(m: Model, W, D, p):
    b, L = m.body, m.lights
    s = p.get("scale", 1)
    plinth(m, W, D, "concrete")
    # control building
    cx, cy = -W * 0.3, -D * 0.34
    b.box(W * 0.3, D * 0.22, 4.8, cx, cy, G, "offwhite", bevel=0.15)
    b.box(W * 0.3 + 0.2, D * 0.22 + 0.2, 0.4, cx, cy, G + 4.8, "teal", bevel=0.08)
    L.window_grid(W * 0.3, D * 0.22, cx, cy, G + 1.2, 1, 3.4, win_w=1.5, gap=0.8, color="glass", sides="se")
    # storage tanks
    tr = min(W, D) * 0.11 + 0.6
    tanks = [(-0.3, 0.18), (-0.3, -0.04)]
    if s >= 2:
        tanks += [(0.33, 0.32)]
    if s >= 3:
        tanks += [(0.33, 0.08), (-0.08, 0.38)]
    for (tx, ty) in tanks:
        tank(b, tx * W, ty * D, tr, 3.6 + s, "white")
    # distillation columns with platforms
    for i in range(s + 1):
        x = W * (0.02 + i * 0.1)
        h = 14 + s * 4 - i * 2
        b.cyl(1.05, h, x, -D * 0.1, G, "alu", seg=12)
        for k in range(1, int(h // 5) + 1):
            b.cyl(1.5, 0.15, x, -D * 0.1, G + k * 5, "orange", seg=12)
        b.cyl(1.1, 0.7, x, -D * 0.1, G + h, "gunmetal", seg=12, r2=0.5)
    # furnace
    b.box(W * 0.16, D * 0.16, 5.5, W * 0.33, -D * 0.25, G, "rust", bevel=0.12)
    b.cyl(0.6, 9.0, W * 0.33, -D * 0.25, G + 5.5, "gunmetal", seg=8)
    # pipe rack
    rack_y = D * 0.08
    b.box(W * 0.78, 1.6, 0.25, 0, rack_y, G + 3.2, "steel", bevel=0.04)
    for i in range(6):
        b.box(0.3, 1.6, 3.2, -W * 0.39 + i * W * 0.156, rack_y, G, "steel", bevel=0.04)
    for k, col in enumerate(("yellow", "steelblue", "alu")):
        b.between((-W * 0.39, rack_y - 0.5 + k * 0.5, G + 3.6), (W * 0.39, rack_y - 0.5 + k * 0.5, G + 3.6), 0.2, col)
    # flare stack with a flame (Lights so it glows at night)
    fx, fy = W * 0.42, -D * 0.42
    b.cyl(0.55, 16 + s * 4, fx, fy, G, "steel", seg=8, r2=0.4)
    for z in range(4, 16 + s * 4, 5):
        b.cyl(0.9, 0.2, fx, fy, G + z, "red", seg=8)
    L.cyl(0.35, 1.4, fx, fy, G + 16 + s * 4, "amber", seg=6, r2=0.05)


def steel_mill(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete")
    hx = -W * 0.12
    hw, hd = W * 0.62, D * 0.62
    b.box(hw, hd, 12.0, hx, 0, G, "steel", bevel=0.2)
    for i in range(int(hw // 3.2)):
        b.box(0.35, hd + 0.2, 12.0, hx - hw / 2 + 1.6 + i * 3.2, 0, G, "gunmetal", bevel=0.05)
    b.box(hw + 0.3, hd + 0.3, 1.0, hx, 0, G + 8.0, "orange", bevel=0.08)
    # monitor roof
    b.prism([(-hd / 2 - 0.4, 0), (hd / 2 + 0.4, 0), (hd * 0.15, 2.2), (-hd * 0.15, 2.2)], hw + 0.5, "x", hx, 0, G + 12.0, "gunmetal")
    L.box(hw - 1.0, hd * 0.3, 1.2, hx, 0, G + 14.2, "amber", bevel=0.05)
    # blast furnace + stoves
    fx = W * 0.32
    b.cyl(2.6, 18.0, fx, -D * 0.12, G, "rust", seg=14, r2=1.9)
    b.cyl(1.0, 6.0, fx, -D * 0.12, G + 18.0, "gunmetal", seg=10)
    for i in range(3):
        b.cyl(1.6, 14.0, fx + 3.4, -D * 0.36 + i * 3.6, G, "alu", seg=12)
        b.dome(1.6, fx + 3.4, -D * 0.36 + i * 3.6, G + 14.0, "alu", seg=12, rings=3)
    b.between((fx, -D * 0.12, G + 15.0), (hx + hw / 2, -D * 0.05, G + 10.0), 0.55, "gunmetal")
    # glowing slag cart + conveyor
    b.box(2.4, 1.6, 1.2, fx - 1.0, D * 0.32, G, "gunmetal", bevel=0.12)
    L.box(1.8, 1.0, 0.3, fx - 1.0, D * 0.32, G + 1.2, "orange", bevel=0.05)
    b.box(1.2, D * 0.4, 0.6, W * 0.1, D * 0.3, G + 5, "rust", bevel=0.06, rx=-14, center=True)


def warehouse(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete")
    bw, bd = W - 1.2, D - 2.2
    oy = 0.5
    b.box(bw, bd, 6.4, 0, oy, G, "pblue", bevel=0.15)
    # barrel-vault roof
    prof = []
    for i in range(9):
        a = math.pi * i / 8
        prof.append((-math.cos(a) * (bd / 2 + 0.3), math.sin(a) * 2.6))
    b.prism(prof, bw + 0.4, "x", 0, oy, G + 6.4, "alu")
    doors = max(2, int(bw // 7))
    for i in range(doors):
        x = -bw / 2 + (i + 0.5) * bw / doors
        b.box(3.4, 0.2, 4.4, x, oy - bd / 2 - 0.05, G, "grey_d", bevel=0.05)
        for k in range(5):
            b.box(3.4, 0.25, 0.08, x, oy - bd / 2 - 0.1, G + 0.6 + k * 0.8, "grey", bevel=0.01)
        b.box(4.0, 1.4, 0.6, x, oy - bd / 2 - 0.8, G, "concrete_l", bevel=0.06)
        L.box(0.8, 0.3, 0.3, x, oy - bd / 2 - 0.2, G + 5.0, "glow", bevel=0.03)
    for i in range(3):
        b.box(1.2, 1.2, 1.2, W / 2 - 1.0, -D / 2 + 1.0 + i * 0.0, G + i * 1.2, "wood", bevel=0.08)


def factory(m: Model, W, D, p):
    b, L = m.body, m.lights
    military = p.get("tint") == "military"
    large = p.get("large", False)
    plinth(m, W, D, "concrete")
    wall = "olive_l" if military else "beige"
    roof = "olive_d" if military else "slate"
    bw, bd = W - 1.6, D - 2.4
    oy = 0.4
    h = 10.0 if large else 8.0
    b.box(bw, bd, h, 0, oy, G, wall, bevel=0.18)
    b.box(bw + 0.2, bd + 0.2, 0.8, 0, oy, G, "grey_d", bevel=0.08)
    for i in range(int(bw // 4)):
        b.box(0.3, bd + 0.2, h, -bw / 2 + 2 + i * 4, oy, G, "olive" if military else "tan", bevel=0.05)
    # sawtooth roof with glazing (Lights)
    teeth = max(2, int(bd // 5))
    step = bd / teeth
    for i in range(teeth):
        y0 = oy - bd / 2 + i * step
        b.prism([(y0, 0), (y0 + step, 0), (y0 + step, 2.6)], bw, "x", 0, 0, G + h, roof)
        L.box(bw - 0.6, 0.15, 2.3, 0, y0 + step - 0.12, G + h + 0.1, "glass_l", bevel=0.02)
    fy = oy - bd / 2
    docks = 3 if large else 2
    for i in range(docks):
        x = -bw / 2 + (i + 1) * bw / (docks + 1)
        b.box(3.6, 0.2, 4.6, x, fy - 0.05, G, "grey_d", bevel=0.05)
        b.box(4.4, 1.4, 0.2, x, fy - 0.7, G + 5.0, "charcoal", bevel=0.05)
    L.window_grid(bw, bd, 0, oy, G + h * 0.55, 1, 3.0, win_w=1.8, gap=1.8, color="glass", sides="ew")
    # chimney + silos
    b.cyl(0.9, h + 10, bw / 2 - 2.0, oy + bd / 2 - 2.0, G, "brick" if not military else "olive_d", seg=10)
    b.cyl(1.1, 0.5, bw / 2 - 2.0, oy + bd / 2 - 2.0, G + h + 10, "charcoal", seg=10)
    if military:
        # hazard stripes, roof emblem and a guard post
        for i in range(8):
            b.box(0.6, 0.12, 0.6, -bw / 2 + 0.8 + i * 1.2, fy - 0.1, G + h - 1.0, "amber" if i % 2 == 0 else "hazard", bevel=0.0)
        b.box(2.0, 2.0, 2.8, -W / 2 + 1.6, -D / 2 + 1.4, G, "olive_l", bevel=0.12)
        b.box(2.4, 2.4, 0.3, -W / 2 + 1.6, -D / 2 + 1.4, G + 2.8, "olive_d", bevel=0.06)
        L.box(1.4, 0.2, 0.9, -W / 2 + 1.6, -D / 2 + 0.4, G + 1.4, "glass", bevel=0.02)
    else:
        for i in range(2):
            b.cyl(1.4, 7.0, -bw / 2 + 2.0 + i * 3.2, oy + bd / 2 + 1.2, G, "alu", seg=12)
            b.dome(1.4, -bw / 2 + 2.0 + i * 3.2, oy + bd / 2 + 1.2, G + 7.0, "alu", seg=12, rings=3)


# --------------------------------------------------------------- services
def shop(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    bw, bd = W - 1.4, D - 2.0
    oy = 0.4
    b.box(bw, bd, 4.8, 0, oy, G, "cream", bevel=0.14)
    b.box(bw + 0.2, bd + 0.2, 0.5, 0, oy, G + 4.8, "terracotta", bevel=0.08)
    fy = oy - bd / 2
    L.box(bw - 1.0, 0.2, 2.4, 0, fy - 0.05, G + 0.5, "glass_l", bevel=0.03)
    b.box(0.25, 0.3, 3.0, 0, fy - 0.1, G + 0.3, "white", bevel=0.04)
    # striped awning
    stripes = 6
    for i in range(stripes):
        x = -bw / 2 + (i + 0.5) * bw / stripes
        b.box(bw / stripes + 0.01, 1.8, 0.14, x, fy - 0.8, G + 3.25, "red" if i % 2 == 0 else "white", bevel=0.02, rx=20, center=True)
    b.box(bw * 0.75, 0.3, 1.0, 0, fy - 0.15, G + 5.3, "amber", bevel=0.06)
    L.box(bw * 0.6, 0.32, 0.5, 0, fy - 0.17, G + 5.55, "glow", bevel=0.03)
    rooftop_units(b, bw, bd, 0, oy, G + 5.3, count=1, seed=3)
    b.box(0.6, 0.6, 1.0, W / 2 - 0.6, -D / 2 + 0.6, G, "teal", bevel=0.1)


def park(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "grass", "concrete")
    b.box(W - 1.0, 1.3, 0.06, 0, 0, G, "sand", bevel=0.02)
    b.box(1.3, D - 1.0, 0.06, 0, 0, G, "sand", bevel=0.02)
    tree(b, -W / 4 - 0.3, -D / 4 - 0.2, 1.0, kind=0)
    tree(b, W / 4 + 0.2, D / 4 + 0.3, 1.1, kind=1)
    tree(b, W / 4 + 0.3, -D / 4 - 0.3, 0.8, kind=2)
    b.cyl(W * 0.17, 0.15, -W / 4, D / 4, G, "water", seg=14)
    b.cyl(W * 0.19, 0.12, -W / 4, D / 4, G - 0.02, "sand", seg=14)
    b.box(1.6, 0.5, 0.45, 1.6, -1.2, G, "wood", bevel=0.05)
    lamp(b, -0.9, -0.9, 3.5)
    L.sphere(0.22, -0.7, -0.9, G + 3.35, "glow", subd=1)
    bush(b, W / 2 - 1.0, -D / 2 + 1.0, 0.5, "grass_l")


def office(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    floors = p.get("floors", 8)
    fh = 3.3
    bw, bd = W - 2.0, D - 2.0
    b.box(bw + 0.6, bd + 0.6, 3.6, 0, 0, G, "charcoal", bevel=0.15)
    L.box(bw - 1.0, 0.2, 2.6, 0, -bd / 2 - 0.35, G + 0.4, "glass_l", bevel=0.03)
    z0 = G + 3.6
    b.box(bw, bd, floors * fh, 0, 0, z0, "glass", bevel=0.12)
    for f in range(floors + 1):
        b.box(bw + 0.3, bd + 0.3, 0.32, 0, 0, z0 + f * fh - 0.16, "alu", bevel=0.06)
    for i in range(5):
        x = -bw / 2 + 0.4 + i * (bw - 0.8) / 4
        for sy in (-1, 1):
            b.box(0.22, 0.3, floors * fh, x, sy * (bd / 2 + 0.05), z0, "alu", bevel=0.04)
    L.window_grid(bw - 0.4, bd - 0.4, 0, 0, z0, floors, fh, win_w=2.2, gap=0.5, color="glass_l", margin=0.4)
    top = z0 + floors * fh
    b.box(bw - 2.0, bd - 2.0, 2.2, 0, 0, top, "alu", bevel=0.12)
    b.box(bw * 0.6, 0.3, 1.2, 0, -bd / 2 + 0.9, top + 2.2, "teal", bevel=0.05)


def school(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    by = -D * 0.26
    bw, bd = W * 0.9, D * 0.36
    b.box(bw, bd, 7.4, 0, by, G, "brick", bevel=0.15)
    b.box(bw + 0.2, bd + 0.2, 0.35, 0, by, G + 3.6, "cream", bevel=0.05)
    b.box(bw + 0.3, bd + 0.3, 0.5, 0, by, G + 7.4, "cream", bevel=0.08)
    L.window_grid(bw, bd, 0, by, G + 0.6, 2, 3.6, win_w=1.5, gap=0.9, color="glass")
    b.box(4.2, bd + 1.2, 8.6, -bw * 0.32, by, G, "cream", bevel=0.12)
    b.box(3.0, 0.3, 1.0, -bw * 0.32, by - bd / 2 - 0.7, G + 7.2, "teal", bevel=0.05)
    # sports field
    fy = D * 0.2
    b.box(W * 0.72, D * 0.48, 0.08, 0, fy, G, "grass", bevel=0.02)
    b.box(0.15, D * 0.48, 0.1, 0, fy, G + 0.01, "line", bevel=0.0)
    b.cyl(1.4, 0.09, 0, fy, G + 0.02, "line", seg=16)
    b.cyl(1.25, 0.1, 0, fy, G + 0.02, "grass", seg=16)
    for sx in (-1, 1):
        b.box(0.15, 2.4, 1.4, sx * W * 0.34, fy, G, "white", bevel=0.03)
    b.cyl(0.12, 9.0, W * 0.43, D * 0.43, G, "alu", seg=6)
    b.box(0.08, 2.0, 1.3, W * 0.43, D * 0.43 - 1.0, G + 7.6, "pblue", bevel=0.0)


def hospital(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    by = -D * 0.16
    bw, bd = W * 0.8, D * 0.44
    b.box(bw, bd, 11.0, 0, by, G, "white", bevel=0.18)
    for f in range(1, 4):
        b.box(bw + 0.25, bd + 0.25, 0.28, 0, by, G + f * 3.4, "pblue", bevel=0.05)
    L.window_grid(bw, bd, 0, by, G + 0.6, 3, 3.4, win_w=1.6, gap=0.8, color="glass_l")
    # red cross on the facade
    fy = by - bd / 2 - 0.1
    b.box(1.0, 0.3, 3.2, 0, fy, G + 6.8, "red", bevel=0.05)
    b.box(3.2, 0.3, 1.0, 0, fy, G + 7.9, "red", bevel=0.05)
    # wing + ambulance canopy
    b.box(W * 0.36, D * 0.34, 6.0, -W * 0.2, D * 0.26, G, "offwhite", bevel=0.15)
    b.box(5.0, 3.0, 0.3, W * 0.22, D * 0.12, G + 3.6, "red", bevel=0.06)
    for sx in (-1, 1):
        b.box(0.25, 0.25, 3.6, W * 0.22 + sx * 2.2, D * 0.12 - 1.2, G, "alu", bevel=0.03)
    # helipad on roof
    b.cyl(3.6, 0.25, 0, by, G + 11.0, "charcoal", seg=18)
    b.box(0.5, 2.6, 0.04, -0.8, by, G + 11.25, "line", bevel=0.0)
    b.box(0.5, 2.6, 0.04, 0.8, by, G + 11.25, "line", bevel=0.0)
    b.box(1.6, 0.5, 0.04, 0, by, G + 11.25, "line", bevel=0.0)


def billboard(m: Model, W, D, p):
    b, L = m.body, m.lights
    plinth(m, W, D, "concrete_l")
    b.box(0.6, 0.6, 6.5, 0, 0, G, "gunmetal", bevel=0.08)
    b.box(W - 0.2, 1.0, 0.3, 0, 0, G + 6.3, "gunmetal", bevel=0.05)
    b.box(W - 0.1, 0.5, 4.6, 0, 0, G + 6.6, "charcoal", bevel=0.1)
    # flat board faces: the game puts the player's message on "Board"
    board = m.part("Board")
    board.box(W - 0.6, 0.62, 4.1, 0, 0, G + 6.85, "white", bevel=0.0)
    for x in (-W * 0.3, 0, W * 0.3):
        b.box(0.2, 1.2, 0.2, x, -0.6, G + 11.2, "gunmetal", bevel=0.03)
        L.box(0.5, 0.3, 0.2, x, -1.1, G + 11.1, "glow", bevel=0.03)


STYLES = {
    "house": house,
    "townhouse": townhouse,
    "apartment": apartment,
    "tower": tower,
    "road": road,
    "plaza": plaza,
    "windTurbine": wind_turbine,
    "solarFarm": solar_farm,
    "coalPlant": coal_plant,
    "nuclearPlant": nuclear_plant,
    "waterTower": water_tower,
    "pumpStation": pump_station,
    "oilPump": oil_pump,
    "oilTank": oil_tank,
    "refinery": refinery,
    "steelMill": steel_mill,
    "warehouse": warehouse,
    "factory": factory,
    "shop": shop,
    "park": park,
    "office": office,
    "school": school,
    "hospital": hospital,
    "billboard": billboard,
}
