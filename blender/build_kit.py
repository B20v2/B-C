"""
Forge & Frontline asset kit generator.

    python blender/build_kit.py [--out assets] [--no-render] [--only small_house,unit_tank]

Requires Blender's Python module (`pip install bpy`) or run inside Blender:
    blender -b -P blender/build_kit.py -- --out assets

Outputs (in --out):
    palette.png                 shared 8x8 colour palette texture
    FF_Buildings.fbx            every building (one root per building id)
    FF_Vehicles.fbx             vehicles, projectiles, fuel truck
    FF_World.fbx                mainland sites + trees / rocks
    ForgeKit.blend              editable source scene
    previews/<asset>.png        turntable-angle renders, plus contact sheets
    kit.json                    asset list with triangle counts and sizes
"""

import argparse
import json
import math
import os
import sys
import time

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from ffkit import palette as P  # noqa: E402
from ffkit.geo import Model, palette_material, realize  # noqa: E402
from ffkit.civil import STYLES  # noqa: E402
from ffkit.military import MIL_STYLES, UNIT_STYLES, projectile, fuel_truck  # noqa: E402
from ffkit.world import SITES, prop_tree, prop_rock  # noqa: E402

MAX_TRIS = 18000  # Roblox MeshPart limit is 20k; keep headroom


def parse_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(HERE), "assets"))
    ap.add_argument("--manifest", default=os.path.join(HERE, "manifest.json"))
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=12)
    ap.add_argument("--res", type=int, default=360)
    return ap.parse_args(argv)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    return scene


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def split_heavy(root, collection):
    """Split any mesh over MAX_TRIS into chunks (Roblox per-mesh limit)."""
    import bmesh
    for child in list(root.children):
        if child.type != "MESH" or tri_count(child) <= MAX_TRIS:
            continue
        bm = bmesh.new()
        bm.from_mesh(child.data)
        bm.faces.ensure_lookup_table()
        # bucket faces along the longest horizontal axis
        xs = [f.calc_center_median() for f in bm.faces]
        span_x = max(c.x for c in xs) - min(c.x for c in xs)
        span_y = max(c.y for c in xs) - min(c.y for c in xs)
        axis = 0 if span_x >= span_y else 1
        chunks = math.ceil(tri_count(child) / MAX_TRIS)
        lo = min(c[axis] for c in xs)
        hi = max(c[axis] for c in xs) + 1e-3
        base_name = child.name
        for k in range(chunks):
            a = lo + (hi - lo) * k / chunks
            b = lo + (hi - lo) * (k + 1) / chunks
            part = bmesh.new()
            vmap = {}
            for f, c in zip(bm.faces, xs):
                if a <= c[axis] < b:
                    vs = []
                    for v in f.verts:
                        if v.index not in vmap:
                            vmap[v.index] = part.verts.new(v.co)
                        vs.append(vmap[v.index])
                    nf = part.faces.new(vs)
                    nf.material_index = f.material_index
            mesh = bpy.data.meshes.new(f"{base_name}{k + 1}")
            part.to_mesh(mesh)
            part.free()
            # copy UVs by recomputing from the stored per-face colour is not
            # possible after realize, so re-derive from the source UV layer
            src_uv = child.data.uv_layers[0]
            uvl = mesh.uv_layers.new(name="UVMap")
            # every face is a flat colour: copy the UV of the source face
            src_faces = [f for f, c in zip(bm.faces, xs) if a <= c[axis] < b]
            for poly, sf in zip(mesh.polygons, src_faces):
                uv = src_uv.data[child.data.polygons[sf.index].loop_indices[0]].uv
                for li in poly.loop_indices:
                    uvl.data[li].uv = uv
                poly.use_smooth = False
            mesh.materials.append(child.data.materials[0])
            obj = bpy.data.objects.new(f"{base_name}{k + 1}", mesh)
            obj.parent = root
            obj.location = child.location
            collection.objects.link(obj)
        bm.free()
        bpy.data.objects.remove(child)


def build_all(args, mat):
    with open(args.manifest) as f:
        manifest = json.load(f)
    cell = manifest["cellSize"]
    only = set(filter(None, args.only.split(",")))
    cols = {}
    for name in ("Buildings", "Vehicles", "World"):
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
        cols[name] = c

    roots = []

    def add(model, colname, meta):
        if only and model.name not in only:
            for part in model.parts.values():
                part.bm.free()
            return
        root = realize(model, cols[colname], mat)
        split_heavy(root, cols[colname])
        meta["name"] = model.name
        meta["collection"] = colname
        roots.append((root, meta))

    for b in manifest["buildings"]:
        style = STYLES.get(b["model"]) or MIL_STYLES.get(b["model"])
        if not style:
            print("!! no style for", b["model"])
            continue
        m = Model(b["id"])
        style(m, b["w"] * cell, b["d"] * cell, b["params"])
        add(m, "Buildings", {"kind": "building", "w": b["w"] * cell, "d": b["d"] * cell})

    for u in manifest["units"]:
        m = Model("unit_" + u["id"])
        UNIT_STYLES[u["model"]](m, u["params"])
        add(m, "Vehicles", {"kind": "unit"})

    for w in manifest["weapons"]:
        m = Model("proj_" + w["id"])
        projectile(m, w["id"], w["kind"])
        add(m, "Vehicles", {"kind": "projectile"})

    m = Model("fuel_truck")
    fuel_truck(m)
    add(m, "Vehicles", {"kind": "truck"})

    seen = set()
    for pnt in manifest["points"]:
        if pnt["model"] in seen:
            continue
        seen.add(pnt["model"])
        m = Model("site_" + pnt["model"])
        SITES[pnt["model"]](m, 130)
        add(m, "World", {"kind": "site", "w": 130, "d": 130})

    for i, (kind, s) in enumerate(((0, 1.0), (0, 1.5), (1, 1.2), (1, 1.8), (2, 1.0), (2, 1.4))):
        m = Model(f"prop_tree_{i + 1}")
        prop_tree(m, kind, s)
        add(m, "World", {"kind": "prop"})
    for i, s in enumerate((1.0, 2.0, 3.2)):
        m = Model(f"prop_rock_{i + 1}")
        prop_rock(m, s)
        add(m, "World", {"kind": "prop"})
    return roots


def bounds(root):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ch in root.children:
        if ch.type != "MESH" or "__" not in ch.name or ch.name.split("__")[-1] in ("Front", "Spin"):
            continue
        for v in ch.data.vertices:
            w = ch.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def export(out, roots):
    os.makedirs(out, exist_ok=True)
    for colname, fname in (("Buildings", "FF_Buildings.fbx"), ("Vehicles", "FF_Vehicles.fbx"), ("World", "FF_World.fbx")):
        objs = []
        for root, meta in roots:
            if meta["collection"] == colname:
                objs.append(root)
                objs.extend(root.children)
        if not objs:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.export_scene.fbx(
            filepath=os.path.join(out, fname),
            use_selection=True,
            object_types={"EMPTY", "MESH"},
            mesh_smooth_type="FACE",
            add_leaf_bones=False,
            path_mode="COPY",
            embed_textures=True,
            axis_forward="-Z",
            axis_up="Y",
            apply_unit_scale=True,
            apply_scale_options="FBX_SCALE_ALL",
        )
        print("exported", fname, len(objs), "objects")


def setup_render(scene, args):
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    try:
        scene.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
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
    sun_data.angle = math.radians(4)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(42), math.radians(8), math.radians(-35))
    scene.collection.objects.link(sun)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def render_previews(scene, cam, roots, out):
    prev = os.path.join(out, "previews")
    os.makedirs(prev, exist_ok=True)
    for root, _ in roots:
        for o in [root] + list(root.children):
            o.hide_render = True
    for root, meta in roots:
        for o in [root] + list(root.children):
            o.hide_render = o.name.split("__")[-1] in ("Front", "Spin")
        lo, hi = bounds(root)
        center = (lo + hi) / 2
        size = (hi - lo)
        rot = (math.radians(58), 0, math.radians(38))
        cam.rotation_euler = rot
        direction = cam.rotation_euler.to_matrix() @ Vector((0, 0, 1))
        cam.location = center + direction * (size.length * 2 + 20)
        cam.data.ortho_scale = max(size.x, size.y, size.z) * 1.55 + 1.0
        cam.data.clip_end = size.length * 6 + 200
        scene.render.filepath = os.path.join(prev, root.name + ".png")
        bpy.ops.render.render(write_still=True)
        for o in [root] + list(root.children):
            o.hide_render = True
    for root, _ in roots:
        for o in [root] + list(root.children):
            o.hide_render = o.name.split("__")[-1] in ("Front", "Spin")


def contact_sheets(out, roots):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("Pillow not installed: skipping contact sheets")
        return
    prev = os.path.join(out, "previews")
    groups = {}
    for root, meta in roots:
        groups.setdefault(meta["collection"], []).append(root.name)
    for group, names in groups.items():
        cols = 6
        cell = 240
        rows = math.ceil(len(names) / cols)
        sheet = Image.new("RGB", (cols * cell, rows * (cell + 24)), (24, 28, 26))
        draw = ImageDraw.Draw(sheet)
        for i, n in enumerate(names):
            path = os.path.join(prev, n + ".png")
            if not os.path.exists(path):
                continue
            im = Image.open(path).convert("RGBA").resize((cell, cell))
            x, y = (i % cols) * cell, (i // cols) * (cell + 24)
            tile = Image.new("RGBA", (cell, cell), (52, 60, 56, 255))
            tile.alpha_composite(im)
            sheet.paste(tile.convert("RGB"), (x, y))
            draw.text((x + 6, y + cell + 4), n, fill=(232, 226, 206))
        sheet.save(os.path.join(prev, f"_sheet_{group}.png"))


def main():
    args = parse_args()
    t0 = time.time()
    scene = reset_scene()
    os.makedirs(args.out, exist_ok=True)
    pal_path = os.path.join(args.out, "palette.png")
    P.write_png(pal_path)
    mat = palette_material(pal_path)
    roots = build_all(args, mat)
    print(f"built {len(roots)} assets in {time.time() - t0:.1f}s")

    info = []
    for root, meta in roots:
        lo, hi = bounds(root)
        tris = sum(tri_count(c) for c in root.children if c.type == "MESH")
        parts = sorted(c.name.split("__")[-1] for c in root.children)
        info.append({**meta, "tris": tris, "size": [round(hi.x - lo.x, 2), round(hi.y - lo.y, 2), round(hi.z - lo.z, 2)], "parts": parts})
        heavy = [c.name for c in root.children if c.type == "MESH" and tri_count(c) > MAX_TRIS]
        if heavy:
            print("!! still over the triangle limit:", heavy)
    with open(os.path.join(args.out, "kit.json"), "w") as f:
        json.dump(info, f, indent=1)

    export(args.out, roots)
    if not args.no_render:
        cam = setup_render(scene, args)
        render_previews(scene, cam, roots, args.out)
        contact_sheets(args.out, roots)
        print(f"rendered previews in {time.time() - t0:.1f}s")
    if not args.only:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out, "ForgeKit.blend"), compress=True)
    print(f"done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
