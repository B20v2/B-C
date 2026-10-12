"""
Modelling toolkit: bevelled primitives built straight into bmesh.

Coordinates (Blender): X = width, Y = depth, Z = up. Footprints are centred
on the origin with the ground at Z = 0. Vehicles face -Y.

Every primitive takes a palette colour name; colours become per-face UVs on
the shared palette texture when the model is realised.
"""

import math
from contextlib import contextmanager

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import palette as P


def place(x=0.0, y=0.0, z=0.0, rx=0.0, ry=0.0, rz=0.0) -> Matrix:
    """Translation + rotation matrix for Part.xform()."""
    return Matrix.Translation((x, y, z)) @ _rot(rx, ry, rz)


def _rot(rx=0.0, ry=0.0, rz=0.0) -> Matrix:
    return (Matrix.Rotation(math.radians(rz), 4, "Z")
            @ Matrix.Rotation(math.radians(ry), 4, "Y")
            @ Matrix.Rotation(math.radians(rx), 4, "X"))


class Part:
    """One mesh object of a model (Body, Lights, Rotor...)."""

    def __init__(self, name: str, pivot=(0.0, 0.0, 0.0)):
        self.name = name
        self.pivot = Vector(pivot)
        self.bm = bmesh.new()

    # ------------------------------------------------------------------ utils
    @contextmanager
    def xform(self, matrix):
        """Everything built inside the block is transformed by `matrix`
        afterwards (build flat, then tilt / move as one piece)."""
        before = set(self.bm.verts)
        yield self
        new = [v for v in self.bm.verts if v not in before]
        if new:
            bmesh.ops.transform(self.bm, matrix=matrix, verts=new)

    def _paint(self, faces, color):
        mi = P.index(color)
        for f in faces:
            f.material_index = mi

    def _faces_of(self, verts):
        faces = set()
        for v in verts:
            faces.update(v.link_faces)
        return faces

    def _bevel(self, verts, amount, segments=1, only=None):
        if amount <= 0:
            return None
        edges = set()
        for v in verts:
            for e in v.link_edges:
                if only is None or only(e):
                    edges.add(e)
        if not edges:
            return None
        return bmesh.ops.bevel(self.bm, geom=list(edges), offset=amount, offset_type="OFFSET",
                               segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)

    # ------------------------------------------------------------- primitives
    def box(self, sx, sy, sz, x=0.0, y=0.0, z=0.0, color="concrete", bevel=0.12,
            rx=0.0, ry=0.0, rz=0.0, center=False):
        """Box; (x, y, z) is the centre of its bottom face unless center=True."""
        sx, sy, sz = max(sx, 0.02), max(sy, 0.02), max(sz, 0.02)
        oz = 0.0 if center else sz / 2
        m = Matrix.Translation((x, y, z)) @ _rot(rx, ry, rz) @ Matrix.Translation((0, 0, oz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        verts = res["verts"]
        self._paint(self._faces_of(verts), color)
        b = min(bevel, sx * 0.3, sy * 0.3, sz * 0.3)
        res = self._bevel(verts, b)
        if res:
            self._paint(res["faces"], color)
        return verts

    def cyl(self, r, h, x=0.0, y=0.0, z=0.0, color="concrete", seg=12, r2=None, bevel=0.0,
            rx=0.0, ry=0.0, rz=0.0, caps=True):
        """Cylinder / frustum standing on (x, y, z)."""
        top = r if r2 is None else r2
        m = Matrix.Translation((x, y, z)) @ _rot(rx, ry, rz) @ Matrix.Translation((0, 0, h / 2))
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=seg,
                                    radius1=r, radius2=top, depth=h, matrix=m)
        verts = res["verts"]
        self._paint(self._faces_of(verts), color)
        if bevel > 0:
            # bevel only the rims, not the vertical seams
            def rim(e):
                a, b = e.verts
                return abs((a.co - b.co).normalized().dot(m.to_3x3() @ Vector((0, 0, 1)))) < 0.5
            res = self._bevel(verts, min(bevel, r * 0.3, h * 0.3), only=rim)
            if res:
                self._paint(res["faces"], color)
        return verts

    def between(self, p1, p2, r, color="steel", seg=8):
        """Cylinder (pipe, strut) from p1 to p2."""
        a, b = Vector(p1), Vector(p2)
        d = b - a
        length = d.length
        if length < 1e-4:
            return []
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        m = Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4()
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg,
                                    radius1=r, radius2=r, depth=length, matrix=m)
        self._paint(self._faces_of(res["verts"]), color)
        return res["verts"]

    def sphere(self, r, x=0.0, y=0.0, z=0.0, color="white", subd=2, uv=None, sz=1.0):
        if uv:
            res = bmesh.ops.create_uvsphere(self.bm, u_segments=uv[0], v_segments=uv[1], radius=r,
                                            matrix=Matrix.Translation((x, y, z)) @ Matrix.Diagonal((1, 1, sz, 1)))
        else:
            res = bmesh.ops.create_icosphere(self.bm, subdivisions=subd, radius=r,
                                             matrix=Matrix.Translation((x, y, z)) @ Matrix.Diagonal((1, 1, sz, 1)))
        self._paint(self._faces_of(res["verts"]), color)
        return res["verts"]

    def dome(self, r, x=0.0, y=0.0, z=0.0, color="white", seg=16, rings=6, sz=1.0):
        """Half sphere sitting on z."""
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings * 2, radius=r,
                                        matrix=Matrix.Translation((x, y, z)) @ Matrix.Diagonal((1, 1, sz, 1)))
        verts = res["verts"]
        below = [v for v in verts if v.co.z < z - 1e-4]
        bmesh.ops.delete(self.bm, geom=below, context="VERTS")
        kept = [v for v in verts if v.is_valid]
        self._paint(self._faces_of(kept), color)
        return kept

    def hexa(self, corners, color="concrete", bevel=0.0):
        """Arbitrary 8-corner block: 4 bottom corners (ccw from above) then 4 top."""
        vs = [self.bm.verts.new(Vector(c)) for c in corners]
        idx = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        faces = []
        for f in idx:
            try:
                faces.append(self.bm.faces.new([vs[i] for i in f]))
            except ValueError:
                pass
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        self._paint(faces, color)
        if bevel > 0:
            res = self._bevel(vs, bevel)
            if res:
                self._paint(res["faces"], color)
        return vs

    def prism(self, profile, length, axis="y", x=0.0, y=0.0, z=0.0, color="concrete", rz=0.0):
        """Extrude a 2D profile [(u, v)] along an axis; u is the horizontal axis
        across, v is up. Gable roofs, ramps, wedges."""
        half = length / 2
        rot = _rot(rz=rz)
        ring_a, ring_b = [], []
        for (u, v) in profile:
            if axis == "y":
                pa, pb = Vector((u, -half, v)), Vector((u, half, v))
            else:
                pa, pb = Vector((-half, u, v)), Vector((half, u, v))
            ring_a.append(self.bm.verts.new((Matrix.Translation((x, y, z)) @ rot) @ pa))
            ring_b.append(self.bm.verts.new((Matrix.Translation((x, y, z)) @ rot) @ pb))
        faces = [self.bm.faces.new(ring_a), self.bm.faces.new(list(reversed(ring_b)))]
        n = len(profile)
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new([ring_a[i], ring_a[j], ring_b[j], ring_b[i]]))
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        self._paint(faces, color)
        return ring_a + ring_b

    def lathe(self, profile, x=0.0, y=0.0, z=0.0, color="concrete", seg=20, cap_bottom=True, cap_top=True, inward=False):
        """Surface of revolution from [(radius, height)] bottom to top."""
        rings = []
        for (r, h) in profile:
            ring = []
            for s in range(seg):
                a = 2 * math.pi * s / seg
                ring.append(self.bm.verts.new((x + math.cos(a) * r, y + math.sin(a) * r, z + h)))
            rings.append(ring)
        faces = []
        for i in range(len(rings) - 1):
            for s in range(seg):
                t = (s + 1) % seg
                quad = [rings[i][s], rings[i][t], rings[i + 1][t], rings[i + 1][s]]
                if inward:
                    quad.reverse()
                faces.append(self.bm.faces.new(quad))
        if cap_bottom:
            faces.append(self.bm.faces.new(list(reversed(rings[0])) if not inward else rings[0]))
        if cap_top:
            faces.append(self.bm.faces.new(rings[-1] if not inward else list(reversed(rings[-1]))))
        self._paint(faces, color)
        return [v for r in rings for v in r]

    # --------------------------------------------------------------- helpers
    def gable_roof(self, w, d, x, y, z, color, pitch=30.0, overhang=0.6, thickness=0.35, ridge_axis="y"):
        """Pitched roof with eaves overhang and a ridge cap."""
        half = w / 2 + overhang
        rise = (w / 2) * math.tan(math.radians(pitch))
        length = d + overhang * 2
        prof = [(-half, 0), (half, 0), (half, thickness), (0, rise + thickness), (-half, thickness)]
        if ridge_axis == "y":
            self.prism(prof, length, "y", x, y, z - 0.05, color)
            self.box(0.5, length + 0.1, 0.3, x, y, z + rise + thickness - 0.15, color, bevel=0.08)
        else:
            self.prism(prof, length, "x", x, y, z - 0.05, color)
            self.box(length + 0.1, 0.5, 0.3, x, y, z + rise + thickness - 0.15, color, bevel=0.08)
        return rise

    def gable_fill(self, w, d, x, y, z, color, pitch=30.0, ridge_axis="y"):
        """Solid triangular gable walls under a roof."""
        rise = (w / 2) * math.tan(math.radians(pitch))
        prof = [(-w / 2, 0), (w / 2, 0), (0, rise)]
        self.prism(prof, d, ridge_axis, x, y, z, color)

    def window_grid(self, w, d, x, y, z0, floors, floor_h, win_w=1.6, win_h=None, gap=1.1,
                    color="glass", depth=0.18, sides="nsew", margin=1.0):
        """Window panes on the facades of a w x d block (as thin boxes)."""
        wh = win_h or floor_h * 0.5
        for f in range(floors):
            zc = z0 + f * floor_h + floor_h * 0.28
            for side in sides:
                along = w if side in "ns" else d
                count = max(1, int((along - margin * 2 + gap) // (win_w + gap)))
                total = count * win_w + (count - 1) * gap
                start = -total / 2 + win_w / 2
                for i in range(count):
                    o = start + i * (win_w + gap)
                    if side == "s":
                        self.box(win_w, depth, wh, x + o, y - d / 2 - depth / 2 + 0.06, zc, color, bevel=0.0)
                    elif side == "n":
                        self.box(win_w, depth, wh, x + o, y + d / 2 + depth / 2 - 0.06, zc, color, bevel=0.0)
                    elif side == "w":
                        self.box(depth, win_w, wh, x - w / 2 - depth / 2 + 0.06, y + o, zc, color, bevel=0.0)
                    else:
                        self.box(depth, win_w, wh, x + w / 2 + depth / 2 - 0.06, y + o, zc, color, bevel=0.0)


class Model:
    def __init__(self, name: str):
        self.name = name
        self.parts = {}
        self.markers = {}

    def part(self, name: str, pivot=(0.0, 0.0, 0.0)) -> Part:
        if name not in self.parts:
            self.parts[name] = Part(name, pivot)
        return self.parts[name]

    @property
    def body(self) -> Part:
        return self.part("Body")

    @property
    def lights(self) -> Part:
        return self.part("Lights")

    def marker(self, name, pos):
        """Tiny helper object the game uses for orientation / attachment points."""
        self.markers[name] = Vector(pos)


_palette_mat = None


def palette_material(image_path: str):
    global _palette_mat
    if _palette_mat:
        return _palette_mat
    mat = bpy.data.materials.new("FF_Palette")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(image_path)
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    _palette_mat = mat
    return mat


def realize(model: Model, collection, mat) -> "bpy.types.Object":
    """Turn a Model into Blender objects: an Empty named after the asset with
    one mesh child per part (named '<asset>__<part>')."""
    root = bpy.data.objects.new(model.name, None)
    root.empty_display_size = 2
    collection.objects.link(root)
    for pname, part in model.parts.items():
        bm = part.bm
        if len(bm.faces) == 0:
            bm.free()
            continue
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        if part.pivot.length > 0:
            bmesh.ops.translate(bm, verts=bm.verts, vec=-part.pivot)
        mesh = bpy.data.meshes.new(f"{model.name}__{pname}")
        bm.to_mesh(mesh)
        bm.free()
        uvl = mesh.uv_layers.new(name="UVMap")
        for poly in mesh.polygons:
            u, v = P.uv(poly.material_index)
            for li in poly.loop_indices:
                uvl.data[li].uv = (u, v)
            poly.material_index = 0
            poly.use_smooth = False
        mesh.materials.append(mat)
        obj = bpy.data.objects.new(f"{model.name}__{pname}", mesh)
        obj.location = part.pivot
        obj.parent = root
        collection.objects.link(obj)
    for mname, pos in model.markers.items():
        # markers are tiny meshes (empties may be dropped by importers);
        # the game reads their position and then deletes them
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.2)
        mesh = bpy.data.meshes.new(f"{model.name}__{mname}")
        bm.to_mesh(mesh)
        bm.free()
        uvl = mesh.uv_layers.new(name="UVMap")
        u, v = P.uv(P.index("red"))
        for loop in uvl.data:
            loop.uv = (u, v)
        mesh.materials.append(mat)
        mk = bpy.data.objects.new(f"{model.name}__{mname}", mesh)
        mk.location = pos
        mk.parent = root
        collection.objects.link(mk)
    return root
