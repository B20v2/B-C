"""
render_parts.py - preview renders of the procedural (part-built) models.

    lune run tools/export_parts.luau build/ForgeAndFrontline.rbxlx parts.json [filter]
    python blender/render_parts.py parts.json out_dir [--res 320] [--samples 10]

Rebuilds every Roblox part (block, ball, cylinder, wedge, head mesh) as a
Blender primitive with the part's colour/material, renders one image per
model and a contact sheet per group (_sheet_<group>.png).
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

# Roblox (x, y, z) with Y up -> Blender (x, -z, y) with Z up
P = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def parse():
    argv = sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("json")
    ap.add_argument("out")
    ap.add_argument("--res", type=int, default=320)
    ap.add_argument("--samples", type=int, default=10)
    ap.add_argument("--only", default="")
    return ap.parse_args(argv)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


_mats = {}


def material(color, mat, t):
    key = (round(color[0], 3), round(color[1], 3), round(color[2], 3), mat, round(t, 2))
    m = _mats.get(key)
    if m:
        return m
    m = bpy.data.materials.new("M%d" % len(_mats))
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    srgb = tuple(c ** 2.2 for c in color)
    bsdf.inputs["Base Color"].default_value = (*srgb, 1)
    rough = {"Glass": 0.08, "Metal": 0.35, "DiamondPlate": 0.4, "SmoothPlastic": 0.45, "Neon": 0.5}.get(mat, 0.7)
    bsdf.inputs["Roughness"].default_value = rough
    if mat in ("Metal", "DiamondPlate", "CorrodedMetal"):
        bsdf.inputs["Metallic"].default_value = 0.6
    if mat == "Neon":
        bsdf.inputs["Emission Color"].default_value = (*srgb, 1)
        bsdf.inputs["Emission Strength"].default_value = 2.5
    if t > 0.01:
        bsdf.inputs["Alpha"].default_value = max(0.15, 1 - t)
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    _mats[key] = m
    return m


def add_part(coll, p):
    sx, sy, sz = p["size"]
    shape = p["shape"]
    mesh = p.get("mesh")
    if mesh == "Head":
        ms = p.get("meshScale") or [1, 1, 1]
        # classic Roblox head: rounded cylinder ~ (1.25, 1.25, 1.25) x part size
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.5, depth=1)
        o = bpy.context.active_object
        bev = o.modifiers.new("b", "BEVEL")
        bev.width = 0.18
        bev.segments = 4
        d = min(sx, sz)
        dims = (d * ms[0], d * ms[2], sy * ms[1])
        o.scale = dims
        local_fix = Matrix.Identity(4)
    elif mesh == "Sphere" or shape == "Ball":
        ms = p.get("meshScale") or [1, 1, 1]
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=0.5)
        o = bpy.context.active_object
        o.scale = (sx * ms[0], sz * ms[2], sy * ms[1]) if mesh else (sx, sz, sy)
        local_fix = Matrix.Identity(4)
    elif shape == "Cylinder":
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.5, depth=1)
        o = bpy.context.active_object
        # Roblox cylinders run along local X
        o.scale = (sy, sz, sx)
        local_fix = Matrix.Rotation(math.radians(90), 4, "Y")
    else:
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.active_object
        o.scale = (sx, sz, sy)
        local_fix = Matrix.Identity(4)
    c = p["cf"]
    pos = Vector((c[0], c[1], c[2]))
    rot = Matrix(((c[3], c[4], c[5]), (c[6], c[7], c[8]), (c[9], c[10], c[11])))
    bl_rot = P @ rot @ P.inverted()
    world = Matrix.Translation(P @ pos) @ bl_rot.to_4x4() @ local_fix
    scale = o.scale.copy()
    o.matrix_world = world @ Matrix.Diagonal((*scale, 1))
    o.data.materials.append(material(p["color"], p["mat"], p["t"]))
    for col in o.users_collection:
        col.objects.unlink(o)
    coll.objects.link(o)
    return o


def setup(scene, args):
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = args.res
    scene.render.resolution_y = args.res
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.62, 0.67, 0.74, 1.0)
    bg.inputs[1].default_value = 0.9
    scene.world = world
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.2
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(42), math.radians(8), math.radians(-35))
    scene.collection.objects.link(sun)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def main():
    args = parse()
    with open(args.json) as f:
        models = json.load(f)
    if args.only:
        keep = set(args.only.split(","))
        models = [m for m in models if m["name"] in keep]
    scene = reset()
    cam = setup(scene, args)
    os.makedirs(args.out, exist_ok=True)
    groups = {}
    for m in models:
        coll = bpy.data.collections.new(m["name"])
        scene.collection.children.link(coll)
        objs = [add_part(coll, p) for p in m["parts"]]
        if not objs:
            continue
        bpy.context.view_layer.update()
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for o in objs:
            for corner in o.bound_box:
                w = o.matrix_world @ Vector(corner)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        center = (lo + hi) / 2
        size = hi - lo
        # Roblox front (-Z) is Blender +Y: look from front-right, above
        cam.rotation_euler = (math.radians(58), 0, math.radians(180 - 38))
        direction = cam.rotation_euler.to_matrix() @ Vector((0, 0, 1))
        cam.location = center + direction * (size.length * 2 + 20)
        cam.data.ortho_scale = max(size.x, size.y, size.z) * 1.45 + 0.6
        cam.data.clip_end = size.length * 6 + 200
        scene.render.filepath = os.path.join(args.out, m["name"] + ".png")
        bpy.ops.render.render(write_still=True)
        bpy.data.collections.remove(coll)
        for o in list(bpy.data.objects):
            if o.users == 0:
                bpy.data.objects.remove(o)
        groups.setdefault(m.get("group", "Models"), []).append(m["name"])
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return
    for group, names in groups.items():
        cols, cell = 6, 240
        rows = math.ceil(len(names) / cols)
        sheet = Image.new("RGB", (cols * cell, rows * (cell + 24)), (24, 28, 26))
        draw = ImageDraw.Draw(sheet)
        for i, n in enumerate(names):
            path = os.path.join(args.out, n + ".png")
            if not os.path.exists(path):
                continue
            im = Image.open(path).convert("RGBA").resize((cell, cell))
            x, y = (i % cols) * cell, (i // cols) * (cell + 24)
            tile = Image.new("RGBA", (cell, cell), (52, 60, 56, 255))
            tile.alpha_composite(im)
            sheet.paste(tile.convert("RGB"), (x, y))
            draw.text((x + 6, y + cell + 4), n, fill=(232, 226, 206))
        sheet.save(os.path.join(args.out, "_sheet_%s.png" % group))


if __name__ == "__main__":
    main()
