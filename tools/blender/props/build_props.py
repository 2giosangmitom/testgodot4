"""PSX props (headless Blender 5.x) -> assets/models/props/<name>.glb

Usage: blender -b --factory-startup -P tools/blender/props/build_props.py -- [names...]

Conventions
- Origin at base-center, real-world meters, <=300 tris, textures from assets/textures/props (NEAREST).
- Front of every prop faces Blender -Y = Godot +Z.
- Products (scanning minigame) print their barcode on the BACK face: Blender +Y = Godot -Z.
  The root node carries glTF extras (Godot node metadata `extras`):
  {"barcode_axis": "-Z", "barcode_axis_blender": "+Y", "product": "...", "price_vnd": 12000}.
- Named sub-nodes: fan_blade (spins around its local Z in Godot), *_emit (flames/screens: unshaded/emissive),
  *_glass (glass shader), pot_lid (liftable), standing_fan_grille (alpha-scissor).
"""
import bpy
import json
import math
import os
import sys
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "chars"))
import glbpost  # noqa: E402

TEX = os.path.join(ROOT, "assets", "textures", "props")
OUT = os.path.join(ROOT, "assets", "models", "props")
PAL = json.load(open(os.path.join(ROOT, "tools", "textures", "props", "palette.json")))
TEX_SIZE = {}

BOX = {"front": (0, 0, 48, 40), "back": (48, 0, 96, 40), "px": (96, 0, 128, 40), "nx": (0, 40, 32, 64),
       "top": (32, 40, 80, 64), "bottom": (80, 40, 128, 64)}
CYL = {"side": (0, 0, 64, 48), "top": (0, 48, 16, 64), "bottom": (16, 48, 32, 64), "extra": (32, 48, 64, 64)}
ALPHA_TEX = {"fan_grille", "dirt_stain"}


def load_size(name):
    if name in TEX_SIZE:
        return TEX_SIZE[name]
    img = bpy.data.images.load(os.path.join(TEX, name + ".png"), check_existing=True)
    TEX_SIZE[name] = tuple(img.size)
    return TEX_SIZE[name]


def R(spec):
    """UV spec -> (texture, (x0,y0,x1,y1) px). spec: 'swatch' (palette) or ('tex', rect)."""
    if isinstance(spec, str):
        return "props_palette", tuple(PAL["swatches"][spec])
    return spec


def uv_of(tex, rect, s, t):
    """s,t in 0..1 within rect (t=0 top of rect)."""
    W, H = load_size(tex)
    x0, y0, x1, y1 = rect
    ins = 0.35
    x = x0 + ins + s * (x1 - x0 - 2 * ins)
    y = y0 + ins + t * (y1 - y0 - 2 * ins)
    return (x / W, 1 - y / H)


class PB:
    def __init__(self):
        self.verts = []
        self.faces = []  # (idx, uvs, tex)

    def v(self, co):
        self.verts.append(Vector(co))
        return len(self.verts) - 1

    def face(self, cos, spec, st=None):
        tex, rect = R(spec)
        n = len(cos)
        if st is None:
            st = [(0, 1), (1, 1), (1, 0), (0, 0)] if n == 4 else [
                (0.5 + 0.5 * math.cos(2 * math.pi * k / n), 0.5 + 0.5 * math.sin(2 * math.pi * k / n)) for k in range(n)]
        idx = [self.v(c) for c in cos]
        self.faces.append((idx, [uv_of(tex, rect, a, b) for a, b in st], tex))

    def mark(self):
        return len(self.verts)

    def xform(self, start, M, pivot=Vector((0, 0, 0))):
        for i in range(start, len(self.verts)):
            self.verts[i] = pivot + M @ (self.verts[i] - pivot)

    def flip_since(self, fstart):
        for i in range(fstart, len(self.faces)):
            idx, uvs, tex = self.faces[i]
            self.faces[i] = (idx[::-1], uvs[::-1], tex)

    # ---------- primitives ----------
    def box(self, c, size, spec, faces=("front", "back", "px", "nx", "top", "bottom")):
        """spec: swatch/('tex',rect) for all faces, or dict face->spec."""
        cx, cy, cz = c
        x, y, z = size[0] / 2, size[1] / 2, size[2] / 2
        F = {
            "front": [(-x, -y, -z), (x, -y, -z), (x, -y, z), (-x, -y, z)],
            "back": [(x, y, -z), (-x, y, -z), (-x, y, z), (x, y, z)],
            "px": [(x, -y, -z), (x, y, -z), (x, y, z), (x, -y, z)],
            "nx": [(-x, y, -z), (-x, -y, -z), (-x, -y, z), (-x, y, z)],
            "top": [(-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)],
            "bottom": [(-x, y, -z), (x, y, -z), (x, -y, -z), (-x, -y, -z)],
        }
        for f in faces:
            sp = spec[f] if isinstance(spec, dict) else spec
            if sp is None:
                continue
            self.face([Vector((cx + a, cy + b, cz + d)) for a, b, d in F[f]], sp)

    def pillow(self, rings, spec_map, caps=True):
        """4-sided tube along Z. rings: [(z, hx, hy)] bottom->top. spec_map: face->spec (BOX names)."""
        zs = [r[0] for r in rings]
        z0, z1 = min(zs), max(zs)
        sides = {
            "front": lambda r: [(-r[1], -r[2]), (r[1], -r[2])],
            "px": lambda r: [(r[1], -r[2]), (r[1], r[2])],
            "back": lambda r: [(r[1], r[2]), (-r[1], r[2])],
            "nx": lambda r: [(-r[1], r[2]), (-r[1], -r[2])],
        }
        for name, fn in sides.items():
            for i in range(len(rings) - 1):
                a, b = rings[i], rings[i + 1]
                (p0, p1), (q0, q1) = fn(a), fn(b)
                ta = 1 - (a[0] - z0) / (z1 - z0)
                tb = 1 - (b[0] - z0) / (z1 - z0)
                self.face([Vector((p0[0], p0[1], a[0])), Vector((p1[0], p1[1], a[0])),
                           Vector((q1[0], q1[1], b[0])), Vector((q0[0], q0[1], b[0]))], spec_map[name],
                          st=[(0, ta), (1, ta), (1, tb), (0, tb)])
        if caps:
            t, b = rings[-1], rings[0]
            self.face([Vector((-t[1], -t[2], t[0])), Vector((t[1], -t[2], t[0])), Vector((t[1], t[2], t[0])),
                       Vector((-t[1], t[2], t[0]))], spec_map["top"])
            self.face([Vector((-b[1], b[2], b[0])), Vector((b[1], b[2], b[0])), Vector((b[1], -b[2], b[0])),
                       Vector((-b[1], -b[2], b[0]))], spec_map["bottom"])

    def cyl(self, rings, n, side, top=None, bottom=None, center=(0, 0), inner=False, u_range=(0, 1),
            v_range=None):
        """Lathe along Z. rings: [(z, r)] bottom->top. side: spec (u wraps around, v top->bottom).
        top/bottom: spec for flat caps (None = open). inner=True builds inward-facing walls."""
        cx, cy = center
        zs = [r[0] for r in rings]
        z0, z1 = min(zs), max(zs)
        f0 = len(self.faces)
        angs = [math.radians(-180 + (k + 0.5) * 360 / n) for k in range(n)]
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            if v_range:
                ta = v_range[0] + (v_range[1] - v_range[0]) * (i / (len(rings) - 1))
                tb = v_range[0] + (v_range[1] - v_range[0]) * ((i + 1) / (len(rings) - 1))
                ta, tb = 1 - ta, 1 - tb
            else:
                ta = 1 - (a[0] - z0) / (z1 - z0) if z1 > z0 else 1
                tb = 1 - (b[0] - z0) / (z1 - z0) if z1 > z0 else 0
            for k in range(n):
                k2 = (k + 1) % n
                u0 = 0.5 + math.degrees(angs[k]) / 360
                u1 = 0.5 + math.degrees(angs[k2]) / 360
                if k2 == 0:
                    u1 += 1
                u0 = u_range[0] + (u_range[1] - u_range[0]) * u0
                u1 = u_range[0] + (u_range[1] - u_range[0]) * u1
                P = lambda r, ang: Vector((cx + math.sin(ang) * r[1], cy - math.cos(ang) * r[1], r[0]))
                self.face([P(a, angs[k]), P(a, angs[k2]), P(b, angs[k2]), P(b, angs[k])], side,
                          st=[(u0, ta), (u1, ta), (u1, tb), (u0, tb)])
        for cap, ring, up in ((top, rings[-1], True), (bottom, rings[0], False)):
            if cap is None:
                continue
            pts = [Vector((cx + math.sin(a) * ring[1], cy - math.cos(a) * ring[1], ring[0])) for a in angs]
            st = [(0.5 + 0.5 * math.sin(a), 0.5 + 0.5 * math.cos(a)) for a in angs]
            if not up:
                pts, st = pts[::-1], st[::-1]
            self.face(pts, cap, st=st)
        if inner:
            self.flip_since(f0)

    def rod(self, p0, p1, r, n, spec):
        """Capped n-sided rod between two points."""
        p0, p1 = Vector(p0), Vector(p1)
        L = (p1 - p0).length
        m = self.mark()
        self.cyl([(0, r), (L, r)], n, spec, top=spec, bottom=spec)
        d = (p1 - p0).normalized()
        q = Vector((0, 0, 1)).rotation_difference(d)
        self.xform(m, q.to_matrix())
        for i in range(m, len(self.verts)):
            self.verts[i] += p0


# ----------------------------------------------------------------------------------------------
# Prop definitions: each returns {"parts": [(name, PB, location)], "extras": {...}}
# ----------------------------------------------------------------------------------------------
def T(tex, rect):
    return (tex, rect)


def product_extras(name, price):
    return {"barcode_axis": "-Z", "barcode_axis_blender": "+Y", "product": name, "price_vnd": price}


def can(tex, product, price):
    def f():
        p = PB()
        side = T(tex, CYL["side"])
        p.cyl([(0.0, 0.027), (0.008, 0.033), (0.112, 0.033), (0.122, 0.028)], 8, side,
              top=T(tex, CYL["top"]), bottom=T(tex, CYL["bottom"]))
        return {"parts": [("root", p, None)], "extras": product_extras(product, price)}
    return f


def instant_noodle_pack():
    p = PB()
    tx = "noodle_pack"
    m = {k: T(tx, BOX[k]) for k in BOX}
    p.pillow([(0.0, 0.062, 0.004), (0.012, 0.065, 0.018), (0.158, 0.065, 0.018), (0.17, 0.062, 0.004)], m)
    return {"parts": [("root", p, None)], "extras": product_extras("Mì Hảo Hạn tôm chua cay", 4000)}


def noodle_cup():
    p = PB()
    tx = "noodle_cup"
    p.cyl([(0.0, 0.042), (0.093, 0.054), (0.097, 0.056)], 8, T(tx, CYL["side"]), top=T(tx, CYL["top"]),
          bottom=T(tx, CYL["bottom"]))
    return {"parts": [("root", p, None)], "extras": product_extras("Mì Ly Hảo Hạn bò hầm", 9000)}


def snack_bag():
    p = PB()
    m = {k: T("snack_bag", BOX[k]) for k in BOX}
    p.pillow([(0.0, 0.075, 0.003), (0.03, 0.08, 0.03), (0.19, 0.08, 0.03), (0.22, 0.075, 0.003)], m)
    return {"parts": [("root", p, None)], "extras": product_extras("Bim Bim Giòn Rụm vị tôm cay", 6000)}


def water_bottle():
    p = PB()
    tx = "water_bottle"
    p.cyl([(0.0, 0.028), (0.006, 0.032), (0.15, 0.032), (0.172, 0.024), (0.188, 0.013)], 8, T(tx, CYL["side"]),
          bottom=T(tx, CYL["bottom"]))
    p.cyl([(0.186, 0.015), (0.21, 0.015)], 8, T(tx, CYL["extra"]), top=T(tx, CYL["top"]))
    return {"parts": [("root", p, None)], "extras": product_extras("Nước suối Trong Lành 500ml", 5000)}


def cardboard_box_closed():
    p = PB()
    p.box((0, 0, 0.15), (0.4, 0.3, 0.3), {k: T("cardboard", BOX[k]) for k in BOX})
    return {"parts": [("root", p, None)], "extras": {}}


def cardboard_box_open():
    p = PB()
    w, d, h = 0.4, 0.3, 0.3
    spec = {k: T("cardboard", BOX[k]) for k in BOX}
    spec["top"] = None
    p.box((0, 0, h / 2), (w, d, h), spec)
    f0 = len(p.faces)  # inner walls + floor (flipped box, slightly inset)
    p.box((0, 0, h / 2 + 0.002), (w - 0.008, d - 0.008, h - 0.004), {"front": "kraft", "back": "kraft", "px": "kraft",
                                                                      "nx": "kraft", "bottom": "kraft", "top": None})
    p.flip_since(f0)
    # 4 flaps opened outward ~120 deg (two-sided thin boxes)
    for (axis, sgn, length, width) in (("y", -1, d / 2, w), ("y", 1, d / 2, w), ("x", -1, w / 2, d), ("x", 1, w / 2, d)):
        m = p.mark()
        if axis == "y":
            p.box((0, 0, length / 2), (width, 0.004, length), {"front": "cardboard", "back": "kraft", "px": "kraft",
                                                             "nx": "kraft", "top": "kraft", "bottom": None})
            M = Matrix.Rotation(math.radians(-sgn * 120), 3, "X")
            p.xform(m, M)
            for i in range(m, len(p.verts)):
                p.verts[i] += Vector((0, sgn * d / 2, h))
        else:
            p.box((0, 0, length / 2), (0.004, width, length), {"px": "cardboard", "nx": "kraft", "front": "kraft",
                                                             "back": "kraft", "top": "kraft", "bottom": None})
            M = Matrix.Rotation(math.radians(sgn * 120), 3, "Y")
            p.xform(m, M)
            for i in range(m, len(p.verts)):
                p.verts[i] += Vector((sgn * w / 2, 0, h))
    return {"parts": [("root", p, None)], "extras": {}}


def mop():
    p = PB()
    p.cyl([(0.1, 0.012), (1.32, 0.012)], 6, "aluminum", top="blue_plastic")
    p.box((0, 0, 0.11), (0.06, 0.05, 0.04), "blue_plastic")
    # strands: flared skirt + inner
    p.cyl([(0.0, 0.11), (0.05, 0.09), (0.12, 0.035)], 8, "mop_strands", bottom="mop_strands", top="mop_strands")
    return {"parts": [("root", p, None)], "extras": {}}


def mop_bucket():
    p = PB()
    rings = [(0.0, 0.13), (0.27, 0.165)]
    p.cyl(rings, 8, "blue_plastic", bottom="blue_plastic")
    p.cyl([(0.01, 0.122), (0.27, 0.157)], 8, "blue_plastic", inner=True)
    p.cyl([(0.27, 0.157), (0.282, 0.172)], 8, "blue_plastic")  # rim lip
    p.cyl([(0.17, 0.148), (0.171, 0.148)], 8, "water", top="water")  # dirty water surface
    # handle: 5 straight segments over the top
    pts = [Vector((-0.165, 0, 0.25)), Vector((-0.14, 0, 0.36)), Vector((-0.05, 0, 0.42)), Vector((0.05, 0, 0.42)),
           Vector((0.14, 0, 0.36)), Vector((0.165, 0, 0.25))]
    for a, b in zip(pts[:-1], pts[1:]):
        p.rod(a, b, 0.004, 4, "dark_steel")
    return {"parts": [("root", p, None)], "extras": {}}


def barcode_scanner():
    p = PB()
    m = p.mark()
    p.box((0, 0, 0.055), (0.034, 0.03, 0.11), "black_plastic")  # grip
    p.xform(m, Matrix.Rotation(math.radians(-15), 3, "X"), Vector((0, 0, 0)))
    p.box((0, -0.04, 0.125), (0.05, 0.13, 0.055), {"front": "red_window", "back": "black_plastic", "px": "black_plastic",
                                                   "nx": "black_plastic", "top": "gray_plastic", "bottom": "black_plastic"})
    p.box((0, -0.012, 0.085), (0.012, 0.018, 0.022), "yellow_plastic")  # trigger
    p.box((0, 0.0, 0.004), (0.06, 0.08, 0.008), "black_plastic")  # stand foot
    return {"parts": [("root", p, None)], "extras": {"scan_axis": "+Z", "scan_axis_blender": "-Y"}}


def cash_register():
    p = PB()
    tx = "cash_register"
    p.box((0, 0, 0.05), (0.38, 0.4, 0.1), {"front": "dark_steel", "back": T(tx, (32, 16, 64, 32)), "px": "dark_steel",
                                           "nx": "dark_steel", "top": "gray_plastic", "bottom": "black_plastic"})
    m = p.mark()
    p.box((0, 0, 0.0), (0.32, 0.22, 0.06), {"front": "dark_steel", "back": "dark_steel", "px": "dark_steel",
                                             "nx": "dark_steel", "top": T(tx, (0, 0, 32, 32)), "bottom": None})
    p.xform(m, Matrix.Rotation(math.radians(-12), 3, "X"))
    for i in range(m, len(p.verts)):
        p.verts[i] += Vector((0, 0.03, 0.13))
    p.box((0.12, -0.12, 0.17), (0.025, 0.025, 0.14), "dark_steel")
    p.box((0.12, -0.12, 0.27), (0.16, 0.035, 0.07), {"front": T(tx, (32, 0, 64, 16)), "back": T(tx, (32, 0, 64, 16)),
                                                    "px": "black_plastic", "nx": "black_plastic", "top": "black_plastic",
                                                    "bottom": "black_plastic"})
    p.box((-0.11, -0.14, 0.13), (0.1, 0.06, 0.06), {"front": T(tx, (0, 32, 32, 48)), "top": T(tx, (0, 32, 32, 48)),
                                                    "back": "dark_steel", "px": "dark_steel", "nx": "dark_steel",
                                                    "bottom": None})
    return {"parts": [("root", p, None)], "extras": {"cashier_side": "+Y blender / -Z godot"}}


def plastic_basket():
    p = PB()
    rings_o = [(0.0, 0.17, 0.11), (0.22, 0.21, 0.15)]
    # outer walls via pillow (tapered), inner walls flipped
    sp = {k: "red_plastic" for k in BOX}
    p.pillow(rings_o, sp, caps=False)
    p.face([Vector((-0.17, 0.11, 0)), Vector((0.17, 0.11, 0)), Vector((0.17, -0.11, 0)), Vector((-0.17, -0.11, 0))],
           "red_plastic")
    f0 = len(p.faces)
    p.pillow([(0.008, 0.162, 0.102), (0.22, 0.202, 0.142)], sp, caps=False)
    p.face([Vector((-0.162, -0.102, 0.008)), Vector((0.162, -0.102, 0.008)), Vector((0.162, 0.102, 0.008)),
            Vector((-0.162, 0.102, 0.008))], "dark_red")
    p.flip_since(f0)
    # rim + slots suggested by darker bands
    p.pillow([(0.2, 0.209, 0.149), (0.225, 0.213, 0.153)], {k: "dark_red" for k in BOX}, caps=False)
    for sx in (-1, 1):  # handles lying folded over the long sides
        pts = [Vector((sx * 0.21, -0.1, 0.22)), Vector((sx * 0.23, -0.06, 0.26)), Vector((sx * 0.23, 0.06, 0.26)),
               Vector((sx * 0.21, 0.1, 0.22))]
        for a, b in zip(pts[:-1], pts[1:]):
            p.rod(a, b, 0.008, 4, "black_plastic")
    return {"parts": [("root", p, None)], "extras": {}}


def gas_stove():
    p = PB()
    tx = "stove"
    p.box((0, 0, 0.05), (0.34, 0.28, 0.1), {"top": T(tx, (0, 0, 36, 36)), "front": T(tx, (36, 0, 64, 32)),
                                           "back": "dark_steel", "px": "dark_steel", "nx": "dark_steel",
                                           "bottom": "black_plastic"})
    p.cyl([(0.1, 0.05), (0.115, 0.045)], 8, "dark_steel", top="soot")  # burner
    for a in range(4):  # pan supports
        ang = math.radians(45 + 90 * a)
        p.box((math.cos(ang) * 0.075, math.sin(ang) * 0.075, 0.115), (0.03, 0.03, 0.03), "black_plastic")
    p.cyl([(0.0, 0.016), (0.02, 0.016)], 6, "black_plastic", top="gray_plastic", center=(0.12, 0))
    m = p.mark()
    p.cyl([(0.0, 0.018), (0.02, 0.016)], 6, "black_plastic", top="mid_gray")
    p.xform(m, Matrix.Rotation(math.radians(90), 3, "X"))
    for i in range(m, len(p.verts)):
        p.verts[i] += Vector((0.1, -0.14, 0.05))
    return {"parts": [("root", p, None)], "extras": {"burner_center": [0.0, 0.115, 0.0], "note": "single burner portable gas stove"}}


def pot():
    p = PB()
    p.cyl([(0.0, 0.085), (0.1, 0.09)], 8, "aluminum", bottom="soot")
    p.cyl([(0.008, 0.083), (0.1, 0.087)], 8, "aluminum", inner=True)
    p.cyl([(0.0081, 0.083), (0.0082, 0.083)], 8, "dark_steel", top="dark_steel")
    p.cyl([(0.1, 0.087), (0.104, 0.093)], 8, "chrome")
    for sx in (-1, 1):
        p.box((sx * 0.105, 0, 0.085), (0.035, 0.05, 0.012), "black_plastic")
    lid = PB()
    lid.cyl([(0.0, 0.094), (0.012, 0.08), (0.022, 0.03)], 8, "aluminum", bottom="dark_steel", top="aluminum")
    lid.cyl([(0.022, 0.012), (0.04, 0.016)], 6, "black_plastic", top="black_plastic")
    return {"parts": [("root", p, None), ("pot_lid", lid, Vector((0, 0, 0.104)))], "extras": {}}


def kettle():
    p = PB()
    p.cyl([(0.0, 0.088), (0.022, 0.088)], 8, "black_plastic", top="black_plastic", bottom="black_plastic")  # base
    p.cyl([(0.022, 0.08), (0.2, 0.07), (0.215, 0.06)], 8, "chrome", bottom="dark_steel")
    p.cyl([(0.215, 0.06), (0.225, 0.05)], 8, "black_plastic", top="black_plastic")
    # handle (back, +Y)
    pts = [Vector((0, 0.07, 0.05)), Vector((0, 0.115, 0.07)), Vector((0, 0.12, 0.17)), Vector((0, 0.07, 0.205))]
    for a, b in zip(pts[:-1], pts[1:]):
        p.rod(a, b, 0.012, 4, "black_plastic")
    # spout (front, -Y)
    m = p.mark()
    p.pillow([(0.0, 0.02, 0.012), (0.04, 0.01, 0.006)], {k: "chrome" for k in BOX}, caps=False)
    p.xform(m, Matrix.Rotation(math.radians(55), 3, "X"))
    for i in range(m, len(p.verts)):
        p.verts[i] += Vector((0, -0.065, 0.18))
    p.box((0, 0.105, 0.06), (0.012, 0.01, 0.015), "led_green")  # switch
    return {"parts": [("root", p, None)], "extras": {"note": "electric kettle (siêu tốc)"}}


def standing_fan():
    p = PB()
    p.cyl([(0.0, 0.17), (0.03, 0.16), (0.045, 0.06)], 8, "white_plastic", top="white_plastic", bottom="gray_plastic")
    p.cyl([(0.04, 0.016), (1.08, 0.014)], 6, "white_plastic")
    p.box((0, 0.04, 0.09), (0.12, 0.05, 0.02), {"top": "blue_plastic", "front": "blue_plastic", "back": "white_plastic",
                                               "px": "white_plastic", "nx": "white_plastic", "bottom": "white_plastic"})
    # motor housing along Y
    m = p.mark()
    p.cyl([(0.0, 0.05), (0.03, 0.065), (0.12, 0.055), (0.14, 0.03)], 8, "white_plastic", top="white_plastic",
          bottom="white_plastic")
    p.xform(m, Matrix.Rotation(math.radians(-90), 3, "X"))
    for i in range(m, len(p.verts)):
        p.verts[i] += Vector((0, 0.03, 1.15))
    # rim ring around the blades (thin 10-sided band, two-sided)
    rim = [(0, 0.205), (0.07, 0.205)]
    m = p.mark()
    p.cyl(rim, 10, "white_plastic")
    p.cyl(rim, 10, "white_plastic", inner=True)
    p.xform(m, Matrix.Rotation(math.radians(90), 3, "X"))
    for i in range(m, len(p.verts)):
        p.verts[i] += Vector((0, -0.005, 1.15))
    # grille discs (alpha scissor) - separate node so materials can differ
    g = PB()
    for y in (-0.075, -0.005):
        pts = [Vector((math.cos(2 * math.pi * k / 10) * 0.205, y, math.sin(2 * math.pi * k / 10) * 0.205)) for k in range(10)]
        st = [(0.5 + 0.5 * math.cos(2 * math.pi * k / 10), 0.5 - 0.5 * math.sin(2 * math.pi * k / 10)) for k in range(10)]
        g.face(pts[::-1], T("fan_grille", (0, 0, 64, 64)), st=st[::-1])
        g.face(pts, T("fan_grille", (0, 0, 64, 64)), st=st)
    # blades: hub + 3 blades, origin at hub center, spin around Blender Y (= Godot local Z)
    b = PB()
    m = b.mark()
    b.cyl([(0.0, 0.03), (0.03, 0.022)], 6, "blue_plastic", top="blue_plastic", bottom="blue_plastic")
    b.xform(m, Matrix.Rotation(math.radians(90), 3, "X"))
    for k in range(3):
        m = b.mark()
        b.box((0.11, 0.0, 0.0), (0.16, 0.006, 0.085), {"front": "blue_plastic", "back": "navy", "px": "blue_plastic",
                                                      "nx": "blue_plastic", "top": "blue_plastic", "bottom": "blue_plastic"})
        b.xform(m, Matrix.Rotation(math.radians(18), 3, "X"))
        b.xform(m, Matrix.Rotation(math.radians(120 * k), 3, "Y"))
    return {"parts": [("root", p, None), ("standing_fan_grille", g, Vector((0, 0, 1.15))),
                      ("fan_blade", b, Vector((0, -0.04, 1.15)))],
            "extras": {"fan_blade_spin_axis": "local Z (Godot) / local Y (Blender)"},
            "alpha": {"fan_grille"}}


def bed_mattress():
    p = PB()
    tx = "mattress"
    side = T(tx, (0, 30, 64, 40))
    p.box((0, 0, 0.05), (1.2, 1.9, 0.1), {"top": T(tx, (0, 0, 64, 40)), "front": side, "back": side, "px": side,
                                         "nx": side, "bottom": "cloth_gray"})
    p.pillow([(0.1, 0.25, 0.14), (0.14, 0.26, 0.15), (0.2, 0.22, 0.12)], {k: T(tx, (0, 40, 32, 64)) for k in BOX})
    for i in range(len(p.verts) - 24, len(p.verts)):
        p.verts[i] += Vector((0, 0.72, 0))
    p.box((0.2, -0.55, 0.14), (0.55, 0.42, 0.08), T(tx, (32, 40, 64, 64)))  # folded blanket
    return {"parts": [("root", p, None)], "extras": {"note": "floor mattress, long axis Blender Y (Godot Z), pillow at +Y (Godot -Z)"}}


def small_desk(height=0.72, name_note="desk"):
    def f():
        p = PB()
        w, d = 0.8, 0.5
        p.box((0, 0, height - 0.0125), (w, d, 0.025), "wood_light")
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.box((sx * (w / 2 - 0.03), sy * (d / 2 - 0.03), (height - 0.025) / 2), (0.035, 0.035, height - 0.025),
                      "wood_dark")
        if height > 0.5:
            p.box((0, d / 2 - 0.03, height * 0.55), (w - 0.06, 0.015, height * 0.35), "wood_light")  # modesty panel
            p.box((0.22, 0, height - 0.07), (0.3, d - 0.08, 0.07), {"front": "wood_red", "back": "wood_light",
                                                                     "px": "wood_light", "nx": "wood_light",
                                                                     "top": None, "bottom": "wood_light"})
            p.box((0.22, -(d - 0.08) / 2 - 0.006, height - 0.07), (0.06, 0.012, 0.012), "brass")
        return {"parts": [("root", p, None)], "extras": {"desk_top_height": height}}
    return f


def laptop():
    p = PB()
    tx = "laptop"
    p.box((0, 0, 0.009), (0.33, 0.23, 0.018), {"top": T(tx, (0, 26, 40, 52)), "front": "dark_steel", "back": "dark_steel",
                                              "px": "dark_steel", "nx": "dark_steel", "bottom": "black_plastic"})
    m = p.mark()
    p.box((0, -0.004, 0.11), (0.33, 0.008, 0.22), {"front": T(tx, (0, 0, 40, 26)), "back": T(tx, (40, 0, 64, 32)),
                                                  "px": "dark_steel", "nx": "dark_steel", "top": "dark_steel",
                                                  "bottom": "dark_steel"})
    p.xform(m, Matrix.Rotation(math.radians(15), 3, "X"))  # tilt back ~105 deg open
    for i in range(m, len(p.verts)):
        p.verts[i] += Vector((0, 0.115, 0.018))
    s = PB()  # emissive screen quad slightly in front of the panel (local to hinge)
    s.face([Vector((-0.15, -0.0095, 0.012)), Vector((0.15, -0.0095, 0.012)), Vector((0.15, -0.0095, 0.205)),
            Vector((-0.15, -0.0095, 0.205))], T(tx, (1, 1, 39, 23)))
    s.xform(0, Matrix.Rotation(math.radians(15), 3, "X"))
    return {"parts": [("root", p, None), ("laptop_screen_emit", s, Vector((0, 0.115, 0.018)))], "extras": {}}


def plastic_wardrobe():
    p = PB()
    tx = "wardrobe"
    p.box((0, 0, 0.83), (0.8, 0.45, 1.6), {"front": T(tx, (0, 0, 64, 128)), "back": "lilac", "px": "lilac",
                                           "nx": "lilac", "top": "white_plastic", "bottom": "white_plastic"})
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.36, sy * 0.19, 0.015), (0.04, 0.04, 0.03), "white_plastic")
    return {"parts": [("root", p, None)], "extras": {}}


def mini_fridge():
    p = PB()
    tx = "fridge"
    p.box((0, 0, 0.445), (0.48, 0.5, 0.85), {"front": T(tx, (0, 0, 64, 44)), "back": T(tx, (0, 44, 64, 64)),
                                             "px": "white_plastic", "nx": "white_plastic", "top": "white_plastic",
                                             "bottom": "gray_plastic"})
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.2, sy * 0.2, 0.01), (0.04, 0.04, 0.02), "black_plastic")
    return {"parts": [("root", p, None)], "extras": {"door_hinge": "left (+X blender)"}}


def ladder_wood():
    p = PB()
    H = 1.95
    for sx in (-1, 1):
        p.box((sx * 0.2, 0, H / 2), (0.045, 0.03, H), "wood_light")
    for k in range(6):
        z = 0.28 + k * 0.3
        p.box((0, 0, z), (0.36, 0.035, 0.03), "wood_dark")
    return {"parts": [("root", p, None)], "extras": {"note": "upright; lean it against the loft (1.9 m)"}}


def broom():
    p = PB()
    p.cyl([(0.3, 0.013), (1.05, 0.012)], 6, "bamboo", top="bamboo")
    p.cyl([(0.28, 0.03), (0.36, 0.022)], 6, "rope", top="rope")
    p.pillow([(0.0, 0.15, 0.03), (0.12, 0.12, 0.035), (0.3, 0.035, 0.03)], {k: "straw" for k in BOX})
    return {"parts": [("root", p, None)], "extras": {"note": "chổi rơm (rice-straw broom)"}}


def incense_bundle(lit=False):
    def f():
        p = PB()
        p.cyl([(0.0, 0.012), (0.12, 0.012)], 6, T("incense", (0, 20, 32, 32)), bottom="dark_red")
        p.cyl([(0.12, 0.012), (0.13, 0.013)], 6, T("incense", (0, 18, 32, 20)))
        p.cyl([(0.13, 0.012), (0.33, 0.014)], 6, T("incense", (0, 0, 32, 18)), top="soot" if lit else "wood_dark")
        parts = [("root", p, None)]
        if lit:
            e = PB()
            e.cyl([(0.0, 0.013), (0.006, 0.012)], 6, "ember", top="ember")
            parts.append(("incense_tips_emit", e, Vector((0, 0, 0.33))))
        return {"parts": parts, "extras": {"lit": lit}}
    return f


def incense_bowl():
    p = PB()
    tx = "incense_bowl"
    p.cyl([(0.0, 0.05), (0.012, 0.06), (0.07, 0.088), (0.11, 0.078)], 8, T(tx, (0, 0, 64, 24)), bottom="cream_ceramic")
    p.cyl([(0.09, 0.07), (0.11, 0.075)], 8, "cream_ceramic", inner=True)
    p.cyl([(0.089, 0.07), (0.09, 0.07)], 8, "ash", top=T(tx, (0, 24, 32, 32)))
    import random
    rnd = random.Random(4)
    for k in range(6):  # burnt stick stubs
        a = rnd.uniform(0, 6.28)
        r = rnd.uniform(0.0, 0.04)
        h = rnd.uniform(0.02, 0.07)
        p.box((math.cos(a) * r, math.sin(a) * r, 0.09 + h / 2), (0.004, 0.004, h), T(tx, (32, 24, 64, 32)))
    return {"parts": [("root", p, None)], "extras": {"incense_slot_height": 0.09, "note": "bát hương"}}


def oil_lamp():
    p = PB()
    p.cyl([(0.0, 0.055), (0.012, 0.05), (0.03, 0.022), (0.045, 0.02)], 8, "brass", bottom="brass")   # foot
    p.cyl([(0.045, 0.03), (0.07, 0.055), (0.1, 0.05), (0.115, 0.02)], 8, "glass", bottom=None)          # oil font
    p.cyl([(0.112, 0.024), (0.13, 0.026)], 8, "brass", top="brass")                                      # burner collar
    p.box((0, 0, 0.138), (0.012, 0.004, 0.016), "soot")                                                   # wick
    p.box((0.03, 0, 0.122), (0.014, 0.008, 0.008), "brass")                                               # wick knob
    g = PB()
    g.cyl([(0.0, 0.024), (0.03, 0.04), (0.06, 0.036), (0.14, 0.02)], 8, "glass")
    g.cyl([(0.0, 0.023), (0.03, 0.039), (0.06, 0.035), (0.14, 0.019)], 8, "glass", inner=True)
    fl = PB()  # flame: double cone, origin at wick top
    fl.cyl([(0.0, 0.001), (0.012, 0.009), (0.04, 0.0005)], 6, "flame_outer", bottom="flame_core")
    return {"parts": [("root", p, None), ("oil_lamp_glass", g, Vector((0, 0, 0.128))),
                      ("oil_lamp_flame_emit", fl, Vector((0, 0, 0.145)))],
            "extras": {"flame_node": "oil_lamp_flame_emit", "note": "đèn dầu; hide the flame node when unlit"}}


def old_photo_frame():
    p = PB()
    tx = "old_photo"
    m = p.mark()
    p.box((0, 0, 0.12), (0.18, 0.015, 0.24), {"front": T(tx, (2, 0, 46, 52)), "back": T(tx, (40, 0, 64, 64)),
                                              "px": "wood_red", "nx": "wood_red", "top": "wood_red", "bottom": "wood_red"})
    p.xform(m, Matrix.Rotation(math.radians(-10), 3, "X"))  # leans back
    m = p.mark()
    p.box((0, 0.06, 0.07), (0.03, 0.01, 0.15), "wood_dark")  # stand strut
    p.xform(m, Matrix.Rotation(math.radians(25), 3, "X"), Vector((0, 0.06, 0.14)))
    return {"parts": [("root", p, None)], "extras": {"note": "altar portrait with cracked glass"}}


def joss_paper():
    p = PB()
    tx = "joss_paper"
    edge = T(tx, (0, 32, 64, 64))
    p.box((0, 0, 0.015), (0.19, 0.19, 0.03), {"top": T(tx, (0, 0, 32, 32)), "front": edge, "back": edge, "px": edge,
                                             "nx": edge, "bottom": T(tx, (32, 0, 64, 32))})
    return {"parts": [("root", p, None)], "extras": {"note": "vàng mã stack"}}


def joss_paper_sheet():
    p = PB()
    tx = "joss_paper"
    p.box((0, 0, 0.0005), (0.19, 0.19, 0.001), {"top": T(tx, (0, 0, 32, 32)), "bottom": T(tx, (32, 0, 64, 32)),
                                               "front": None, "back": None, "px": None, "nx": None})
    return {"parts": [("root", p, None)], "extras": {}}


def phone():
    p = PB()
    tx = "phone"
    p.box((0, 0, 0.0045), (0.07, 0.145, 0.009), {"top": "black_plastic", "bottom": T(tx, (16, 0, 32, 32)),
                                                 "front": "dark_steel", "back": "dark_steel", "px": "dark_steel",
                                                 "nx": "dark_steel"})
    s = PB()
    s.face([Vector((-0.032, -0.066, 0)), Vector((0.032, -0.066, 0)), Vector((0.032, 0.066, 0)), Vector((-0.032, 0.066, 0))],
           T(tx, (0, 0, 16, 32)))
    return {"parts": [("root", p, None), ("phone_screen_emit", s, Vector((0, 0, 0.0092)))],
            "extras": {"note": "lying flat, screen up (+Y godot), top of screen toward -Z godot"}}


def plastic_stool():
    p = PB()
    h = 0.27
    p.pillow([(h - 0.025, 0.14, 0.14), (h, 0.135, 0.135)], {k: "red_plastic" for k in BOX})
    for sx in (-1, 1):
        for sy in (-1, 1):
            m = p.mark()
            p.pillow([(0.0, 0.022, 0.022), (h - 0.02, 0.018, 0.018)], {k: "red_plastic" for k in BOX})
            for i in range(m, len(p.verts)):
                z = p.verts[i].z
                spread = 0.155 - 0.04 * (z / h)
                p.verts[i] += Vector((sx * spread, sy * spread, 0))
    return {"parts": [("root", p, None)], "extras": {"seat_height": h, "note": "ghế nhựa đỏ"}}


def plastic_chair():
    p = PB()
    h = 0.44
    p.box((0, 0, h - 0.015), (0.42, 0.42, 0.03), "blue_plastic")
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.rod((sx * 0.2, sy * 0.2, h - 0.02), (sx * 0.23, sy * 0.23, 0.0), 0.016, 4, "blue_plastic")
    m = p.mark()
    p.box((0, 0, 0.2), (0.4, 0.025, 0.36), "blue_plastic")
    p.xform(m, Matrix.Rotation(math.radians(-10), 3, "X"))
    for i in range(m, len(p.verts)):
        p.verts[i] += Vector((0, 0.2, h + 0.02))
    for sx in (-1, 1):
        p.rod((sx * 0.18, 0.2, h), (sx * 0.19, 0.24, h + 0.22), 0.012, 4, "blue_plastic")
    return {"parts": [("root", p, None)], "extras": {"seat_height": h}}


def dirt_stain():
    p = PB()
    p.face([Vector((-0.4, -0.4, 0.002)), Vector((0.4, -0.4, 0.002)), Vector((0.4, 0.4, 0.002)), Vector((-0.4, 0.4, 0.002))],
           T("dirt_stain", (0, 0, 64, 64)))
    return {"parts": [("root", p, None)], "extras": {"decal": True, "note": "floor decal, faces +Y godot"},
            "alpha": {"dirt_stain"}}


PROPS = {
    "can_tra_xanh": can("can_tra_xanh", "Trà Xanh Mát 330ml", 10000),
    "can_sam": can("can_sam", "Nước Tăng Lực Sấm 330ml", 12000),
    "can_cafe": can("can_cafe", "Cà Phê Sữa Đá Lon 330ml", 15000),
    "can_cam": can("can_cam", "Cam Ép Vui 330ml", 11000),
    "instant_noodle_pack": instant_noodle_pack,
    "noodle_cup": noodle_cup,
    "snack_bag": snack_bag,
    "water_bottle": water_bottle,
    "cardboard_box_closed": cardboard_box_closed,
    "cardboard_box_open": cardboard_box_open,
    "mop": mop,
    "mop_bucket": mop_bucket,
    "barcode_scanner": barcode_scanner,
    "cash_register": cash_register,
    "plastic_basket": plastic_basket,
    "gas_stove": gas_stove,
    "pot": pot,
    "kettle": kettle,
    "standing_fan": standing_fan,
    "bed_mattress": bed_mattress,
    "small_desk": small_desk(0.72),
    "small_desk_low": small_desk(0.32),
    "laptop": laptop,
    "plastic_wardrobe": plastic_wardrobe,
    "mini_fridge": mini_fridge,
    "ladder_wood": ladder_wood,
    "broom": broom,
    "incense_bundle": incense_bundle(False),
    "incense_bundle_lit": incense_bundle(True),
    "incense_bowl": incense_bowl,
    "oil_lamp": oil_lamp,
    "old_photo_frame": old_photo_frame,
    "joss_paper": joss_paper,
    "joss_paper_sheet": joss_paper_sheet,
    "phone": phone,
    "plastic_stool": plastic_stool,
    "plastic_chair": plastic_chair,
    "dirt_stain": dirt_stain,
}


# ----------------------------------------------------------------------------------------------
def material_for(tex, mats):
    if tex in mats:
        return mats[tex]
    m = bpy.data.materials.new("prop_" + tex)
    if m.node_tree is None:
        m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = bpy.data.images.load(os.path.join(TEX, tex + ".png"), check_existing=True)
    node.interpolation = "Closest"
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    if tex in ALPHA_TEX:
        nt.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 1.0
    m.use_backface_culling = tex not in ALPHA_TEX
    mats[tex] = m
    return m


def build(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    spec = PROPS[name]()
    mats = {}
    objs = []
    tris = 0
    root = None
    for pname, pb, loc in spec["parts"]:
        oname = name if pname == "root" else pname
        me = bpy.data.meshes.new(oname)
        me.from_pydata([tuple(v) for v in pb.verts], [], [f[0] for f in pb.faces])
        me.update()
        uvl = me.uv_layers.new(name="UVMap")
        tex_order = []
        for f in pb.faces:
            if f[2] not in tex_order:
                tex_order.append(f[2])
        for t in tex_order:
            me.materials.append(material_for(t, mats))
        for pi, poly in enumerate(me.polygons):
            poly.material_index = tex_order.index(pb.faces[pi][2])
            poly.use_smooth = False
            for j, li in enumerate(poly.loop_indices):
                uvl.data[li].uv = pb.faces[pi][1][j]
        tris += sum(len(p.vertices) - 2 for p in me.polygons)
        ob = bpy.data.objects.new(oname, me)
        bpy.context.scene.collection.objects.link(ob)
        if root is None:
            root = ob
        else:
            ob.parent = root
            if loc is not None:
                ob.location = loc
        objs.append(ob)
    for k, v in spec.get("extras", {}).items():
        root[k] = v
    root["tris"] = tris
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_animations=False, export_extras=True,
                              export_image_format="NONE", export_materials="EXPORT", export_cameras=False,
                              export_lights=False)
    textures = {"prop_" + t: os.path.join(TEX, t + ".png") for t in mats}
    glbpost.postprocess(path, textures=textures, alpha_materials={"prop_" + t for t in spec.get("alpha", set())})
    print(f"[prop] {name}: {tris} tris -> {path}")
    return tris


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or list(PROPS)
    rep = {n: build(n) for n in names}
    print("[prop] TRIS", json.dumps(rep))
    over = {k: v for k, v in rep.items() if v > 300}
    if over:
        print("[prop] OVER BUDGET", over)


if __name__ == "__main__":
    main()
