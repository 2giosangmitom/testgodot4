"""lowpoly_env — helper module for building PS1-style environment glbs headlessly in Blender.

All build scripts work in **Godot level coordinates** (x right, y up, z toward the viewer;
1 unit = 1 m). The helper converts to Blender's Z-up space when it creates objects, and the
glTF exporter (export_yup=True) converts back, so numbers in the build scripts are exactly the
numbers Phase 2 sees in Godot.

Conventions produced here:
  * Materials: one per texture, named `M_<tex>` (variants `M_<tex>_cut`, `_glass`, `_emit`).
    Principled BSDF + Image Texture with 'Closest' interpolation; opaque/cutout materials multiply
    the texture by the `Col` colour attribute (vertex AO) so glTF exports COLOR_0.
  * World-scale UVs: 128 px per metre (`PX_PER_M`) so every texture has the same texel density.
  * Vertex colours: simple ray-cast ambient occlusion baked per face corner + optional tint.
  * Geometry is merged per material into `<env>_<tex>` objects unless built inside `env.obj(name)`.
    Emissive objects contain `_emit`, glass objects contain `_glass`, alpha-cutout ones `_cut`.
  * Collision: `env.col(...)` boxes are merged per category into `<env>_<cat>-colonly` meshes.
  * Markers: `env.marker(name, ...)` → empty `MARKER_<name>`. Forward = Godot -Z (yaw 0),
    yaw is the Godot rotation.y in degrees, pitch is rotation.x (positive looks up).

Usage inside Blender:  import lowpoly_env as L ; env = L.Env("school") ; ... ; env.export()
"""
import bpy
import json
import math
import os
import struct
import sys
from contextlib import contextmanager
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures", "env")
OUT_DIR = os.path.join(ROOT, "assets", "models", "env")
PX_PER_M = 128.0

FACES = ("+x", "-x", "+y", "-y", "+z", "-z")


def g2b(p):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (p[0], -p[2], p[1])


def v3(p):
    return Vector((float(p[0]), float(p[1]), float(p[2])))


def rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def yaw_pitch_to(pos, target):
    d = v3(target) - v3(pos)
    yaw = math.degrees(math.atan2(-d.x, -d.z))
    pitch = math.degrees(math.atan2(d.y, math.hypot(d.x, d.z)))
    return yaw, pitch


# ------------------------------------------------------------------ materials
_img_cache = {}
_mat_cache = {}


def load_image(tex):
    if tex in _img_cache:
        return _img_cache[tex]
    path = os.path.join(TEX_DIR, tex + ".png")
    if not os.path.exists(path):
        raise FileNotFoundError(f"texture missing: {path} (run tools/textures/env/make_textures.py)")
    img = bpy.data.images.load(path, check_existing=True)
    img.name = tex
    _img_cache[tex] = img
    return img


def tex_size(tex):
    img = load_image(tex)
    return img.size[0], img.size[1]


def parse_mat(mid):
    """'wall_yellow' | 'railing@cut' | 'glass@glass' | 'sign_store@emit'"""
    if "@" in mid:
        tex, kind = mid.split("@", 1)
    else:
        tex, kind = mid, "opaque"
    return tex, kind


def get_material(mid):
    if mid in _mat_cache:
        return _mat_cache[mid]
    tex, kind = parse_mat(mid)
    suffix = {"opaque": "", "cut": "_cut", "glass": "_glass", "emit": "_emit"}[kind]
    mat = bpy.data.materials.new("M_" + tex + suffix)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    try:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    except KeyError:
        pass
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = load_image(tex)
    img.interpolation = "Closest"
    img.location = (-700, 200)
    if kind in ("opaque", "cut"):
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        vc.location = (-700, -100)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        mix.location = (-350, 150)
        nt.links.new(img.outputs["Color"], mix.inputs[6])
        nt.links.new(vc.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    if kind == "cut":
        m = nt.nodes.new("ShaderNodeMath")
        m.operation = "ROUND"
        m.location = (-350, -150)
        nt.links.new(img.outputs["Alpha"], m.inputs[0])
        nt.links.new(m.outputs[0], bsdf.inputs["Alpha"])
        mat.use_backface_culling = False
        try:
            mat.surface_render_method = "DITHERED"
        except AttributeError:
            mat.blend_method = "CLIP"
    elif kind == "glass":
        nt.links.new(img.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.use_backface_culling = False
        try:
            mat.surface_render_method = "BLENDED"
        except AttributeError:
            mat.blend_method = "BLEND"
    elif kind == "emit":
        nt.links.new(img.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
        mat.use_backface_culling = True
    else:
        mat.use_backface_culling = True
    _mat_cache[mid] = mat
    return mat


# ------------------------------------------------------------------ geometry container
class Group:
    def __init__(self, name, origin=(0, 0, 0), ao=True, occluder=True):
        self.name = name
        self.origin = v3(origin)
        self.verts = []        # world Godot coords (Vector)
        self.faces = []        # (vert index tuple, uv list, mat id, tint)
        self.ao = ao
        self.occluder = occluder

    def tris(self):
        return sum(len(f[0]) - 2 for f in self.faces)


class Env:
    def __init__(self, name, out_name=None):
        self.name = name
        self.out_name = out_name or name
        self.groups = {}
        self.cols = {}           # category -> list of 8-corner lists
        self.markers = []        # (name, pos, yaw, pitch)
        self.stack = [Matrix.Identity(4)]
        self.cur = None
        self.default_seg = 2.5
        bpy.ops.wm.read_factory_settings(use_empty=True)
        _img_cache.clear()
        _mat_cache.clear()

    # ---------------- transforms / grouping
    @property
    def M(self):
        return self.stack[-1]

    @contextmanager
    def at(self, pos=(0, 0, 0), yaw=0.0, pitch=0.0, roll=0.0, scale=1.0):
        m = Matrix.Translation(v3(pos)) @ rot_y(yaw) @ rot_x(pitch) @ rot_z(roll)
        if scale != 1.0:
            m = m @ Matrix.Scale(scale, 4)
        self.stack.append(self.M @ m)
        try:
            yield
        finally:
            self.stack.pop()

    @contextmanager
    def obj(self, name, origin=None, ao=True, occluder=True):
        """Put everything built inside into a separately named object.
        origin: pivot in *local* coords of the current transform (default local 0,0,0)."""
        prev = self.cur
        if name not in self.groups:
            o = self.M @ v3(origin or (0, 0, 0))
            self.groups[name] = Group(name, o, ao=ao, occluder=occluder)
        self.cur = self.groups[name]
        try:
            yield self.cur
        finally:
            self.cur = prev

    def _group_for(self, mid):
        if self.cur is not None:
            return self.cur
        tex, kind = parse_mat(mid)
        gname = f"{self.name}_{tex}" + {"opaque": "", "cut": "_cut", "glass": "_glass", "emit": "_emit"}[kind]
        if gname not in self.groups:
            self.groups[gname] = Group(gname, ao=(kind in ("opaque", "cut")), occluder=(kind == "opaque"))
        return self.groups[gname]

    # ---------------- primitives
    def quad(self, p, U, V, mat, uv="world", rect=(0, 0, 1, 1), seg=None, tint=None, uvoff=(0, 0), nu=None, nv=None):
        """Quad with corner p and edge vectors U, V (local coords). Normal = U x V.
        uv: 'world' (texel density from local coords) or 'fit' (rect u0,v0,u1,v1 over the face)."""
        p, U, V = v3(p), v3(U), v3(V)
        seg = seg or self.default_seg
        lu, lv = U.length, V.length
        if lu < 1e-6 or lv < 1e-6:
            return
        nu = nu or max(1, math.ceil(lu / seg - 1e-6))
        nv = nv or max(1, math.ceil(lv / seg - 1e-6))
        g = self._group_for(mat)
        M = self.M
        tex, _ = parse_mat(mat)
        tw, th = tex_size(tex)
        su, sv = PX_PER_M / tw, PX_PER_M / th
        Uh, Vh = U.normalized(), V.normalized()
        base = len(g.verts)
        uvs = {}
        for j in range(nv + 1):
            for i in range(nu + 1):
                lp = p + U * (i / nu) + V * (j / nv)
                g.verts.append(M @ lp)
                if uv == "world":
                    uvs[(i, j)] = (lp.dot(Uh) * su + uvoff[0], lp.dot(Vh) * sv + uvoff[1])
                else:
                    uvs[(i, j)] = (rect[0] + (rect[2] - rect[0]) * i / nu, rect[1] + (rect[3] - rect[1]) * j / nv)
        for j in range(nv):
            for i in range(nu):
                idx = (base + j * (nu + 1) + i, base + j * (nu + 1) + i + 1,
                       base + (j + 1) * (nu + 1) + i + 1, base + (j + 1) * (nu + 1) + i)
                uv4 = [uvs[(i, j)], uvs[(i + 1, j)], uvs[(i + 1, j + 1)], uvs[(i, j + 1)]]
                g.faces.append((idx, uv4, mat, tint))

    def face(self, pts, mat, uv="world", uvs=None, tint=None):
        """Arbitrary planar polygon (local coords, CCW seen from the front)."""
        pts = [v3(q) for q in pts]
        g = self._group_for(mat)
        n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
        if n.length < 1e-9:
            return
        n.normalize()
        tex, _ = parse_mat(mat)
        tw, th = tex_size(tex)
        su, sv = PX_PER_M / tw, PX_PER_M / th
        if uvs is None:
            # project: vertical faces -> (horizontal tangent, y); horizontal -> (x, -z)
            if abs(n.y) > 0.7:
                Uh = Vector((1, 0, 0)); Vh = Vector((0, 0, -1)) if n.y > 0 else Vector((0, 0, 1))
            else:
                Uh = Vector((n.z, 0, -n.x))
                Uh = Uh.normalized() if Uh.length > 1e-6 else Vector((1, 0, 0))
                Vh = n.cross(Uh).normalized()
            uvs = [(q.dot(Uh) * su, q.dot(Vh) * sv) for q in pts]
        base = len(g.verts)
        for q in pts:
            g.verts.append(self.M @ q)
        g.faces.append((tuple(range(base, base + len(pts))), list(uvs), mat, tint))

    def box(self, mn, mx, mat, mats=None, skip=(), uv="world", rects=None, seg=None, tint=None, uvoff=(0, 0)):
        """Axis-aligned (in local coords) box from min corner to max corner.
        mats: {face: mat} overrides, rects: {face: (u0,v0,u1,v1)} switches that face to 'fit' UVs."""
        x0, y0, z0 = mn
        x1, y1, z1 = mx
        dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
        spec = {
            "+z": ((x0, y0, z1), (dx, 0, 0), (0, dy, 0)),
            "-z": ((x1, y0, z0), (-dx, 0, 0), (0, dy, 0)),
            "+x": ((x1, y0, z1), (0, 0, -dz), (0, dy, 0)),
            "-x": ((x0, y0, z0), (0, 0, dz), (0, dy, 0)),
            "+y": ((x0, y1, z1), (dx, 0, 0), (0, 0, -dz)),
            "-y": ((x0, y0, z0), (dx, 0, 0), (0, 0, dz)),
        }
        mats = mats or {}
        rects = rects or {}
        for f in FACES:
            if f in skip:
                continue
            p, U, V = spec[f]
            m = mats.get(f, mat)
            if f in rects:
                self.quad(p, U, V, m, uv="fit", rect=rects[f], seg=seg, tint=tint)
            else:
                self.quad(p, U, V, m, uv=uv, seg=seg, tint=tint, uvoff=uvoff)

    def cbox(self, pos, size, mat, yaw=0.0, **kw):
        """Box standing on pos (bottom centre), size (sx, sy, sz), rotated by yaw."""
        sx, sy, sz = size
        with self.at(pos, yaw=yaw):
            self.box((-sx / 2, 0, -sz / 2), (sx / 2, sy, sz / 2), mat, **kw)

    def cyl(self, base, r, h, mat, segs=8, r_top=None, caps=(True, True), cap_mat=None, tint=None, uv_v=None):
        """Vertical cylinder/cone (local Y axis) from base centre."""
        r_top = r if r_top is None else r_top
        bx, by, bz = base
        g_mat = mat
        tex, _ = parse_mat(mat)
        tw, th = tex_size(tex)
        circ = 2 * math.pi * max(r, r_top)
        for i in range(segs):
            a0 = 2 * math.pi * i / segs
            a1 = 2 * math.pi * (i + 1) / segs
            p00 = (bx + math.sin(a0) * r, by, bz + math.cos(a0) * r)
            p10 = (bx + math.sin(a1) * r, by, bz + math.cos(a1) * r)
            p11 = (bx + math.sin(a1) * r_top, by + h, bz + math.cos(a1) * r_top)
            p01 = (bx + math.sin(a0) * r_top, by + h, bz + math.cos(a0) * r_top)
            u0 = circ * i / segs * PX_PER_M / tw
            u1 = circ * (i + 1) / segs * PX_PER_M / tw
            vv0 = by * PX_PER_M / th if uv_v is None else uv_v[0]
            vv1 = (by + h) * PX_PER_M / th if uv_v is None else uv_v[1]
            self.face([p00, p10, p11, p01], g_mat, uvs=[(u0, vv0), (u1, vv0), (u1, vv1), (u0, vv1)], tint=tint)
        cm = cap_mat or mat
        if caps[1] and r_top > 0:
            pts = [(bx + math.sin(2 * math.pi * i / segs) * r_top, by + h, bz + math.cos(2 * math.pi * i / segs) * r_top) for i in range(segs)]
            self.face(pts, cm, uv="world", tint=tint)
        if caps[0] and r > 0:
            pts = [(bx + math.sin(2 * math.pi * i / segs) * r, by, bz + math.cos(2 * math.pi * i / segs) * r) for i in reversed(range(segs))]
            self.face(pts, cm, uv="world", tint=tint)

    def card(self, center, w, h, mat, yaw=0.0, uv="fit", rect=(0, 0, 1, 1), pitch=0.0, tint=None):
        """Upright quad centred at `center`, facing local +z after yaw (good for signs/posters)."""
        with self.at(center, yaw=yaw, pitch=pitch):
            self.quad((-w / 2, -h / 2, 0), (w, 0, 0), (0, h, 0), mat, uv=uv, rect=rect, tint=tint)

    def cross_cards(self, center, w, h, mat, n=2, yaw=0.0, rect=(0, 0, 1, 1)):
        for k in range(n):
            self.card(center, w, h, mat, yaw=yaw + 180.0 * k / n, rect=rect)

    def strip(self, a, b, y0, y1, mat, uv="world", rect=(0, 0, 1, 1), sag=0.0, segs=1, tint=None):
        """Vertical ribbon between ground points a(x,z) and b(x,z) from y0 to y1, optional sag (cables)."""
        pts = []
        for i in range(segs + 1):
            t = i / segs
            x = a[0] + (b[0] - a[0]) * t
            z = a[1] + (b[1] - a[1]) * t
            s = -sag * 4 * t * (1 - t)
            pts.append((x, s, z))
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        for i in range(segs):
            (xa, sa, za), (xb, sb, zb) = pts[i], pts[i + 1]
            if uv == "world":
                tw, th = tex_size(parse_mat(mat)[0])
                ua, ub = L * i / segs * PX_PER_M / tw, L * (i + 1) / segs * PX_PER_M / tw
                uvs = [(ua, 0), (ub, 0), (ub, 1), (ua, 1)]
            else:
                ua = rect[0] + (rect[2] - rect[0]) * i / segs
                ub = rect[0] + (rect[2] - rect[0]) * (i + 1) / segs
                uvs = [(ua, rect[1]), (ub, rect[1]), (ub, rect[3]), (ua, rect[3])]
            self.face([(xa, y0 + sa, za), (xb, y0 + sb, zb), (xb, y1 + sb, zb), (xa, y1 + sa, za)], mat, uvs=uvs, tint=tint)

    # ---------------- architecture helpers
    def wall(self, axis, c, a0, a1, y0, y1, mat, t=0.2, openings=(), side_mats=None, col=True, col_cat="walls",
             inner_mat=None, uvoff=(0, 0), tint=None, skip_ends=False):
        """Straight wall. axis='x': runs along x from a0..a1 at z=c (thickness t, centred);
        axis='z': runs along z from a0..a1 at x=c.
        openings: list of (b0, b1, oy0, oy1, kind) along the run; kind 'door' (no collision) or
        'window' (collision stays solid) or 'hole' (no collision)."""
        a0, a1 = min(a0, a1), max(a0, a1)
        ops = sorted([o if len(o) == 5 else (*o, "window") for o in openings], key=lambda o: o[0])
        segs = []   # (b0, b1, y0, y1)
        cur = a0
        for b0, b1, oy0, oy1, kind in ops:
            if b0 > cur:
                segs.append((cur, b0, y0, y1))
            if oy0 > y0:
                segs.append((b0, b1, y0, oy0))
            if oy1 < y1:
                segs.append((b0, b1, oy1, y1))
            cur = b1
        if cur < a1:
            segs.append((cur, a1, y0, y1))
        h = t / 2
        mats = dict(side_mats or {})
        if inner_mat:
            mats.setdefault("-z" if axis == "x" else "-x", inner_mat)
        for b0, b1, sy0, sy1 in segs:
            skip = []
            if skip_ends:
                skip += ["-x", "+x"] if axis == "x" else ["+z", "-z"]
            if axis == "x":
                self.box((b0, sy0, c - h), (b1, sy1, c + h), mat, mats=mats, skip=skip, uvoff=uvoff, tint=tint)
            else:
                self.box((c - h, sy0, b0), (c + h, sy1, b1), mat, mats=mats, skip=skip, uvoff=uvoff, tint=tint)
        # reveal faces inside openings are covered by the segment boxes' end faces.
        if col:
            cur = a0
            csegs = []
            for b0, b1, oy0, oy1, kind in ops:
                if kind == "window":
                    continue
                if b0 > cur:
                    csegs.append((cur, b0, y0, y1))
                if oy1 < y1:
                    csegs.append((b0, b1, oy1, y1))
                if oy0 > y0:
                    csegs.append((b0, b1, y0, oy0))
                cur = b1
            if cur < a1:
                csegs.append((cur, a1, y0, y1))
            for b0, b1, sy0, sy1 in csegs:
                if axis == "x":
                    self.col((b0, sy0, c - h), (b1, sy1, c + h), col_cat)
                else:
                    self.col((c - h, sy0, b0), (c + h, sy1, b1), col_cat)

    def floor(self, x0, z0, x1, z1, y, mat, col=True, thick=0.3, uvoff=(0, 0), tint=None, seg=None, cat="floor", under=None):
        """Horizontal walkable surface facing up (+ optional underside facing down)."""
        xa, xb = min(x0, x1), max(x0, x1)
        za, zb = min(z0, z1), max(z0, z1)
        self.quad((xa, y, zb), (xb - xa, 0, 0), (0, 0, -(zb - za)), mat, uvoff=uvoff, tint=tint, seg=seg)
        if under:
            self.quad((xa, y - thick, za), (xb - xa, 0, 0), (0, 0, zb - za), under, tint=tint, seg=seg)
        if col:
            self.col((xa, y - thick, za), (xb, y, zb), cat)

    def ceiling(self, x0, z0, x1, z1, y, mat, tint=None, seg=None):
        xa, xb = min(x0, x1), max(x0, x1)
        za, zb = min(z0, z1), max(z0, z1)
        self.quad((xa, y, za), (xb - xa, 0, 0), (0, 0, zb - za), mat, tint=tint, seg=seg)

    # ---------------- collision / markers
    def col(self, mn, mx, cat="col"):
        x0, y0, z0 = mn
        x1, y1, z1 = mx
        corners = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1),
                   (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]
        self.cols.setdefault(cat, []).append([self.M @ v3(c) for c in corners])

    def col_ramp(self, a, b, width, thick=0.25, cat="stairs"):
        """Ramp whose top centre-line goes from a (bottom) to b (top). For stairs: a = first step
        nosing at floor level, b = top landing edge."""
        a, b = self.M @ v3(a), self.M @ v3(b)
        d = b - a
        side = d.cross(Vector((0, 1, 0)))
        side.normalize()
        side *= width / 2
        n = side.cross(d).normalized()
        if n.y < 0:
            n = -n
        top = [a - side, a + side, b + side, b - side]
        if (top[1] - top[0]).cross(top[2] - top[0]).dot(n) > 0:
            top = [top[0], top[3], top[2], top[1]]
        bot = [q - n * thick for q in top]
        # order corners like col(): bottom 4 then top 4 (winding fixed in _box_mesh)
        self.cols.setdefault(cat, []).append(bot + top)

    def marker(self, name, pos, yaw=0.0, pitch=0.0):
        if not name.startswith("MARKER_"):
            name = "MARKER_" + name
        p = self.M @ v3(pos)
        # account for current transform yaw
        fwd = (self.M.to_3x3() @ rot_y(yaw).to_3x3() @ Vector((0, 0, -1)))
        wyaw = math.degrees(math.atan2(-fwd.x, -fwd.z))
        self.markers.append((name, p, wyaw, pitch))

    def marker_look(self, name, pos, target):
        yaw, pitch = yaw_pitch_to(pos, target)
        self.marker(name, pos, yaw, pitch)

    # ---------------- bake + build
    def _occluder_bvh(self):
        verts, polys = [], []
        for g in self.groups.values():
            if not g.occluder:
                continue
            off = len(verts)
            verts.extend(g.verts)
            polys.extend([tuple(i + off for i in f[0]) for f in g.faces])
        for cat, boxes in self.cols.items():
            pass  # collision boxes are not occluders
        if not polys:
            return None
        return BVHTree.FromPolygons(verts, polys)

    @staticmethod
    def _hemi_dirs(n=14):
        dirs = []
        ga = math.pi * (3 - math.sqrt(5))
        for i in range(n):
            z = 1 - (i + 0.5) / n          # cos-ish distribution (more near normal)
            z = math.sqrt(z)
            r = math.sqrt(max(0.0, 1 - z * z))
            a = ga * i
            dirs.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
        return dirs

    def bake_ao(self, radius=1.4, strength=0.85, min_ao=0.32, rays=14):
        bvh = self._occluder_bvh()
        dirs = self._hemi_dirs(rays)
        cache = {}
        self._colors = {}
        for g in self.groups.values():
            cols = []
            for idx, uvs, mat, tint in g.faces:
                pts = [g.verts[i] for i in idx]
                n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
                if n.length < 1e-12:
                    n = Vector((0, 1, 0))
                n.normalize()
                fc = []
                for q in pts:
                    if not g.ao or bvh is None:
                        a = 1.0
                    else:
                        key = (round(q.x, 2), round(q.y, 2), round(q.z, 2), round(n.x, 1), round(n.y, 1), round(n.z, 1))
                        a = cache.get(key)
                        if a is None:
                            t = n.orthogonal().normalized()
                            b = n.cross(t)
                            o = q + n * 0.04
                            occ = 0.0
                            for d in dirs:
                                wd = t * d.x + b * d.y + n * d.z
                                hit = bvh.ray_cast(o, wd, radius)
                                if hit[0] is not None:
                                    occ += 1.0 - (hit[3] / radius) ** 0.7
                            a = 1.0 - strength * occ / len(dirs)
                            if n.y < -0.5:
                                a *= 0.85
                            a = max(min_ao, a)
                            cache[key] = a
                    c = [a, a, a]
                    if tint is not None:
                        c = [c[0] * tint[0], c[1] * tint[1], c[2] * tint[2]]
                    fc.append(c)
                cols.append(fc)
            self._colors[g.name] = cols

    def _make_object(self, g):
        me = bpy.data.meshes.new(g.name)
        o = g.origin
        verts = [g2b(v - o) for v in g.verts]
        faces = [f[0] for f in g.faces]
        me.from_pydata(verts, [], faces)
        assert len(me.polygons) == len(faces), g.name
        mids = []
        for f in g.faces:
            if f[2] not in mids:
                mids.append(f[2])
        for mid in mids:
            me.materials.append(get_material(mid))
        mi = {m: i for i, m in enumerate(mids)}
        me.polygons.foreach_set("material_index", [mi[f[2]] for f in g.faces])
        uvl = me.uv_layers.new(name="UVMap")
        flat_uv = []
        for f in g.faces:
            for uv in f[1]:
                flat_uv.extend(uv)
        uvl.data.foreach_set("uv", flat_uv)
        ca = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        flat_c = []
        for fc in self._colors[g.name]:
            for c in fc:
                lin = [max(0.0, x) ** 2.2 for x in c]
                flat_c.extend(lin + [1.0])
        ca.data.foreach_set("color", flat_c)
        me.color_attributes.active_color = ca
        try:
            me.color_attributes.render_color_index = 0
        except Exception:
            pass
        me.update()
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(g.name, me)
        ob.location = g2b(o)
        bpy.context.scene.collection.objects.link(ob)
        return ob

    def _make_cols(self):
        objs = []
        for cat, boxes in self.cols.items():
            verts, faces = [], []
            for c in boxes:
                b = len(verts)
                verts.extend(g2b(q) for q in c)
                # bottom 0-3, top 4-7
                fl = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
                faces.extend(tuple(b + i for i in f) for f in fl)
            me = bpy.data.meshes.new(f"{self.name}_{cat}-colonly")
            me.from_pydata(verts, [], faces)
            me.validate()
            ob = bpy.data.objects.new(f"{self.name}_{cat}-colonly", me)
            ob.display_type = "WIRE"
            bpy.context.scene.collection.objects.link(ob)
            objs.append(ob)
        return objs

    def _make_markers(self):
        for name, p, yaw, pitch in self.markers:
            e = bpy.data.objects.new(name, None)
            e.empty_display_type = "ARROWS"
            e.empty_display_size = 0.3
            e.location = g2b(p)
            e.rotation_euler = (math.radians(pitch), 0.0, math.radians(yaw))
            bpy.context.scene.collection.objects.link(e)

    def stats(self):
        tot = sum(g.tris() for g in self.groups.values())
        return tot

    def export(self, path=None, quiet=False):
        path = path or os.path.join(OUT_DIR, self.out_name + ".glb")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        # drop empty groups
        self.groups = {k: g for k, g in self.groups.items() if g.faces}
        self.bake_ao()
        for g in self.groups.values():
            self._make_object(g)
        self._make_cols()
        self._make_markers()
        bpy.ops.export_scene.gltf(
            filepath=path, export_format="GLB", export_yup=True, export_apply=True,
            export_extras=True, export_vertex_color="MATERIAL", export_lights=False,
            export_cameras=False, export_image_format="AUTO", export_materials="EXPORT",
            export_animations=False, export_texcoords=True, export_normals=True,
            use_selection=False)
        externalize_glb_images(path)
        tot = self.stats()
        ncol = sum(len(b) for b in self.cols.values())
        names = sorted(n for n, *_ in self.markers)
        print(f"[env] {os.path.basename(path)}: {tot} tris, {len(self.groups)} mesh objects, "
              f"{ncol} collision boxes, {len(names)} markers")
        if not quiet:
            big = sorted(self.groups.values(), key=lambda g: -g.tris())[:8]
            print("[env]   biggest: " + ", ".join(f"{g.name}={g.tris()}" for g in big))
            print("[env]   markers: " + " ".join(names))
        return tot


def externalize_glb_images(path, tex_dir=TEX_DIR):
    """Rewrite a .glb so every embedded image becomes an external `uri` pointing at the shared
    PNG in assets/textures/env (relative path). Godot then loads those textures as resources
    (one import, PSX import settings, no per-glb extracted copies). The BIN chunk is compacted."""
    data = open(path, "rb").read()
    magic, _ver, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF", path
    off, chunks = 12, []
    while off < length:
        clen, ctype = struct.unpack_from("<I4s", data, off)
        off += 8
        chunks.append((ctype, data[off:off + clen]))
        off += clen
    js = json.loads(chunks[0][1].decode("utf-8"))
    bin_ = chunks[1][1] if len(chunks) > 1 else b""
    rel = os.path.relpath(tex_dir, os.path.dirname(os.path.abspath(path))).replace(os.sep, "/")
    drop = set()
    for im in js.get("images", []):
        if "bufferView" in im:
            name = im.get("name")
            if not name or not os.path.exists(os.path.join(tex_dir, name + ".png")):
                continue
            drop.add(im.pop("bufferView"))
            im.pop("mimeType", None)
            im["uri"] = f"{rel}/{name}.png"
    if not drop:
        return
    remap, views, nb = {}, [], bytearray()
    for i, v in enumerate(js.get("bufferViews", [])):
        if i in drop:
            continue
        st = v.get("byteOffset", 0)
        seg = bin_[st:st + v["byteLength"]]
        while len(nb) % 4:
            nb.append(0)
        v = dict(v)
        v["byteOffset"] = len(nb)
        nb += seg
        remap[i] = len(views)
        views.append(v)
    js["bufferViews"] = views
    for a in js.get("accessors", []):
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
        sp = a.get("sparse")
        if sp:
            sp["indices"]["bufferView"] = remap[sp["indices"]["bufferView"]]
            sp["values"]["bufferView"] = remap[sp["values"]["bufferView"]]
    for im in js.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = remap[im["bufferView"]]
    while len(nb) % 4:
        nb.append(0)
    js["buffers"][0]["byteLength"] = len(nb)
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    while len(jb) % 4:
        jb += b" "
    total = 12 + 8 + len(jb) + 8 + len(nb)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(jb), b"JSON"))
        f.write(jb)
        f.write(struct.pack("<I4s", len(nb), b"BIN\x00"))
        f.write(bytes(nb))


def run_args():
    argv = sys.argv
    return argv[argv.index("--") + 1:] if "--" in argv else []
