"""
Mainland strategic sites and decoration props (trees, rocks).
Sites are ~130 studs across and reuse the building styles so the mainland
reads as real places.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix

from .geo import Model
from . import civil, military


def _stamp(m: Model, style, W, D, x, y, params=None, rz=0):
    """Build another style into this model, offset by (x, y) and rotated."""
    sub = Model("tmp")
    style(sub, W, D, params or {})
    mat = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(rz), 4, "Z")
    for pname, part in sub.parts.items():
        dst = m.part(pname if pname in ("Body", "Lights") else "Body")
        bmesh.ops.transform(part.bm, matrix=mat, verts=part.bm.verts)
        tmp = bpy.data.meshes.new("_stamp")
        part.bm.to_mesh(tmp)
        dst.bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        part.bm.free()


def _ground(m: Model, S, color="concrete"):
    m.body.box(S, S, 0.3, 0, 0, -0.25, color, bevel=0.2)


def site_city(m: Model, S):
    _ground(m, S, "asphalt")
    rnd = random.Random(7)
    b = m.body
    b.box(S * 0.95, 6, 0.08, 0, 0, 0.05, "line", bevel=0.0)
    b.box(6, S * 0.95, 0.08, 0, 0, 0.05, "line", bevel=0.0)
    picks = [(civil.apartment, 24, 16, {"floors": 5}), (civil.tower, 16, 16, {"floors": 12}),
             (civil.office, 24, 24, {"floors": 7}), (civil.townhouse, 24, 8, {"count": 3}),
             (civil.shop, 12, 12, {}), (civil.apartment, 24, 16, {"floors": 3})]
    slots = [(-38, -38), (-38, 0), (-38, 38), (0, -38), (0, 38), (38, -38), (38, 0), (38, 38)]
    for i, (x, y) in enumerate(slots):
        style, W, D, p = picks[(i + rnd.randint(0, 5)) % len(picks)]
        _stamp(m, style, W, D, x, y, p, rz=rnd.choice((0, 90, 180, 270)))
    civil.tree(b, 18, 18, 1.4, z=0)
    civil.tree(b, -18, -18, 1.4, z=0)


def site_airport(m: Model, S):
    _ground(m, S, "grass")
    b, L = m.body, m.lights
    b.box(16, S * 0.98, 0.25, -10, 0, 0, "asphalt", bevel=0.1)
    for i in range(-6, 7):
        b.box(0.8, 5, 0.04, -10, i * 9, 0.25, "line", bevel=0.0)
    b.box(6, S * 0.8, 0.25, 12, 0, 0, "asphalt", bevel=0.05)
    for i in range(4):
        y = -S * 0.36 + i * S * 0.24
        b.box(16, 16, 9, 34, y, 0, "alu", bevel=0.3)
        b.prism([(-8, 0), (8, 0), (6, 3), (-6, 3)], 16, "x", 34, y, 9, "steelblue")
        b.box(0.3, 12, 7.5, 25.9, y, 0, "grey_d", bevel=0.05)
    # control tower
    b.cyl(2.2, 22, 46, S * 0.42, 0, "white", seg=12)
    b.cyl(4.2, 3.4, 46, S * 0.42, 22, "glass_d", seg=12, r2=4.8)
    L.cyl(4.25, 2.6, 46, S * 0.42, 22.4, "glass_l", seg=12, r2=4.75)
    b.cyl(5.0, 0.6, 46, S * 0.42, 25.4, "white", seg=12)
    # a parked jet
    b.cyl(1.4, 14, 12, -20, 1.4, "white", seg=12, rx=90)
    b.box(18, 3, 0.4, 12, -21, 1.6, "white", bevel=0.2, center=True)
    b.box(6, 1.6, 0.3, 12, -27.5, 2.2, "white", bevel=0.1, center=True)
    b.box(0.3, 2, 3.4, 12, -27.5, 2.2, "red", bevel=0.1)


def site_oil_field(m: Model, S):
    _ground(m, S, "dirt")
    rnd = random.Random(3)
    for i in range(12):
        x, y = rnd.uniform(-S * 0.42, S * 0.12), rnd.uniform(-S * 0.42, S * 0.42)
        _stamp(m, civil.oil_pump, 12, 18, x, y, {}, rz=rnd.choice((0, 90)))
    _stamp(m, civil.refinery, 40, 32, -S * 0.1, S * 0.3, {"scale": 2})
    for k in range(3):
        civil.tank(m.body, S * 0.32, -S * 0.25 + k * 22, 8, 7, "offwhite", z=0)
    m.body.between((S * 0.3, -S * 0.3, 1), (S * 0.3, S * 0.3, 1), 0.6, "yellow")


def site_nuclear(m: Model, S):
    _ground(m, S, "concrete")
    _stamp(m, civil.nuclear_plant, 84, 72, -14, -6, {})
    civil.cooling_tower(m.body, 42, 34, 1.6, z=0)
    _stamp(m, civil.warehouse, 32, 24, 40, -40, {})
    _stamp(m, civil.office, 24, 24, -44, 46, {"floors": 4})
    for i in range(8):
        m.body.box(0.4, 0.4, 2.0, -S / 2 + 4 + i * (S - 8) / 7, -S / 2 + 3, 0, "grey", bevel=0.05)


def site_port(m: Model, S):
    b = m.body
    b.box(S, S * 0.45, 2.0, 0, -S * 0.27, -1.8, "concrete", bevel=0.2)
    b.box(S, S * 0.55, 0.3, 0, S * 0.22, -0.25, "water", bevel=0.05)
    rnd = random.Random(5)
    cols = ["red", "steelblue", "orange", "olive", "white", "teal"]
    for row in range(3):
        for i in range(10):
            x = -S * 0.44 + i * 8.5
            y = -S * 0.42 + row * 4.2
            for lvl in range(rnd.randint(1, 3)):
                b.box(7.6, 3.4, 3.2, x, y, 0.2 + lvl * 3.2, cols[(i + row + lvl) % len(cols)], bevel=0.15)
    for i in range(3):
        x = -S * 0.3 + i * S * 0.3
        for sx in (-3, 3):
            b.box(1.2, 1.2, 24, x + sx, -S * 0.08, 0, "orange", bevel=0.15)
        b.box(1.4, 30, 1.4, x, -S * 0.08 + 9, 24, "orange", bevel=0.15)
        b.box(3, 3, 2.4, x, -S * 0.08, 21, "yellow", bevel=0.2)
    # cargo ship
    b.box(16, 70, 6, 0, S * 0.3, -1, "navy", bevel=0.8)
    b.box(14, 12, 9, 0, S * 0.3 + 26, 5, "white", bevel=0.3)


def site_base(m: Model, S):
    _ground(m, S, "concrete")
    b = m.body
    military.fence(b, S, S, z=0)
    for i in range(3):
        x = -S * 0.3 + i * S * 0.3
        _stamp(m, military.depot, 32, 24, x, -S * 0.22, {})
    b.cyl(10, 0.25, S * 0.25, S * 0.25, 0, "asphalt", seg=24)
    b.box(1.4, 9, 0.06, S * 0.25 - 2.5, S * 0.25, 0.25, "line", bevel=0.0)
    b.box(1.4, 9, 0.06, S * 0.25 + 2.5, S * 0.25, 0.25, "line", bevel=0.0)
    b.box(5, 1.4, 0.06, S * 0.25, S * 0.25, 0.25, "line", bevel=0.0)
    _stamp(m, military.radar, 16, 16, -S * 0.3, S * 0.28, {})
    _stamp(m, military.sam, 24, 24, 0, S * 0.25, {"large": True})


SITES = {
    "city": site_city,
    "airport": site_airport,
    "oilField": site_oil_field,
    "nuclear": site_nuclear,
    "port": site_port,
    "base": site_base,
}


# ------------------------------------------------------------------ props
def prop_tree(m: Model, kind: int, s: float):
    civil.tree(m.body, 0, 0, s, z=0, kind=kind)


def prop_rock(m: Model, s: float):
    b = m.body
    b.sphere(2.2 * s, 0, 0, 0.6 * s, "grey", subd=1, sz=0.7)
    b.sphere(1.3 * s, 1.6 * s, 0.8 * s, 0.4 * s, "concrete", subd=1, sz=0.8)
