"""Parametric low-poly PS1-style human generator (headless Blender 5.x).

Usage:
  blender -b --factory-startup -P tools/blender/chars/build_character.py -- [names...] [--out DIR]
  (no names = all characters in CHARACTERS)

Each character -> assets/models/chars/<name>.glb : one skinned mesh "<name>_mesh" (rigid per-part
weights, 2 materials: head atlas + body atlas), armature "<name>_rig" with bones
  root hips spine chest neck head shoulder_L/R upper_arm_L/R lower_arm_L/R hand_L/R
  upper_leg_L/R lower_leg_L/R foot_L/R
shape keys neck_tilt / long_arms / face_distort and the animations listed in ANIMS.
Character faces -Y in Blender = +Z in Godot (glTF model front). Origin = between the feet on the floor.
"""
import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector, Matrix, Quaternion, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX = os.path.join(ROOT, "assets", "textures", "chars")
OUT_DIR = os.path.join(ROOT, "assets", "models", "chars")
LAYOUT = json.load(open(os.path.join(ROOT, "tools", "textures", "chars", "atlas_layout.json")))
CELLS = LAYOUT["cells"]
FPS = 30

# --------------------------------------------------------------------------------------------
# Character table
# --------------------------------------------------------------------------------------------
DEFAULT = dict(height=1.68, build=1.0, sex="m", hair="messy", hat=None, scarf=False, backpack=False,
               skirt=None, arm_scale=1.0, neck_extra=0.0, head_tilt=0.0, gaunt=0.0, head_scale=1.0,
               head_tex=None, body_tex=None, belly=0.0, stoop=0.0)


def C(**kw):
    d = dict(DEFAULT)
    d.update(kw)
    return d


CHARACTERS = {
    "nam": C(height=1.69, hair="messy"),
    "hung": C(height=1.66, build=1.12, hair="buzz", belly=0.4, head_scale=1.04),
    "linh": C(height=1.57, sex="f", hair="long"),
    "bac_tu": C(height=1.63, build=0.88, hair="gray_thin", gaunt=0.4, stoop=0.35),
    "chi_hanh": C(height=1.56, sex="f", build=1.03, hair="bun"),
    "thay_khai": C(height=1.67, build=1.05, hair="side_part", belly=0.35),
    "ba_cu": C(height=1.48, sex="f", build=0.9, hair="none", scarf=True, stoop=0.7, gaunt=0.3),
    "student_m1": C(height=1.71, build=0.95, hair="short", backpack=True),
    "student_m2": C(height=1.65, build=1.0, hair="side_part", backpack=True),
    "student_f1": C(height=1.58, sex="f", hair="ponytail", backpack=True),
    "student_f2": C(height=1.55, sex="f", hair="bob", skirt="skirt"),
    "passerby_m1": C(height=1.66, build=1.08, hair="short", skirt="raincoat"),
    "passerby_m2": C(height=1.70, build=1.0, hair="messy"),
    "passerby_f1": C(height=1.54, sex="f", build=1.02, hair="bun", hat="non_la"),
    # Gazer: 20% taller than average, gaunt, elongated limbs/neck.
    "gazer": C(height=2.02, build=0.8, gaunt=1.0, hair="short", arm_scale=1.12, neck_extra=0.05),
    # Mimics: originals with long arms + tilted neck baked into the rest pose.
    "mimic_hung": C(height=1.66, build=1.12, hair="buzz", belly=0.4, head_scale=1.04, arm_scale=1.38,
                    head_tilt=24.0, neck_extra=0.03),
    "mimic_linh": C(height=1.57, sex="f", hair="long", arm_scale=1.42, head_tilt=-24.0, neck_extra=0.04),
}

# --------------------------------------------------------------------------------------------
# Mesh accumulator
# --------------------------------------------------------------------------------------------
class MB:
    def __init__(self):
        self.verts = []   # Vector
        self.groups = []  # bone name per vertex
        self.tags = []    # part tag per vertex (for shape keys)
        self.faces = []   # (indices, uvs, mat)

    def v(self, co, group, tag):
        self.verts.append(Vector(co))
        self.groups.append(group)
        self.tags.append(tag)
        return len(self.verts) - 1

    def f(self, idx, uvs, mat, outward=None):
        if outward is not None:
            p = [self.verts[i] for i in idx]
            n = Vector((0, 0, 0))
            for i in range(len(p)):  # Newell normal
                a, b = p[i], p[(i + 1) % len(p)]
                n.x += (a.y - b.y) * (a.z + b.z)
                n.y += (a.z - b.z) * (a.x + b.x)
                n.z += (a.x - b.x) * (a.y + b.y)
            if n.dot(outward) < 0:
                idx = list(reversed(idx))
                uvs = list(reversed(uvs))
        self.faces.append((list(idx), list(uvs), mat))


def cell_uv(cell, u, v, inset=0.5):
    x0, y0, x1, y1 = CELLS[cell]
    W, H = LAYOUT["size"]
    px = x0 + inset + u * (x1 - x0 - 2 * inset)
    py = y0 + inset + v * (y1 - y0 - 2 * inset)
    return (px / W, 1.0 - py / H)


def tube(mb, group, tag, p0, p1, rings, sides, cell, side_hint=Vector((1, 0, 0)), front_hint=Vector((0, -1, 0)),
         cap0=True, cap1=True, cap_uv=(0.25, 0.5), mat=1, skip_faces=()):
    """rings: list of (t, rx, ry, front_offset). t along p0->p1. Ring 0 maps to the cell top."""
    p0, p1 = Vector(p0), Vector(p1)
    axis = (p1 - p0)
    a = axis.normalized()
    s = (side_hint - a * side_hint.dot(a)).normalized()
    fr = (front_hint - a * front_hint.dot(a) - s * front_hint.dot(s)).normalized()
    ids = []
    ts = [r[0] for r in rings]
    tmin, tmax = min(ts), max(ts)
    for (t, rx, ry, fo) in rings:
        c = p0 + axis * t + fr * fo
        ring = []
        for k in range(sides):
            th = math.radians(-180 + (k + 0.5) * 360 / sides)
            co = c + s * math.sin(th) * rx + fr * math.cos(th) * ry
            ring.append((mb.v(co, group, tag), 0.5 + math.degrees(th) / 360.0))
        vv = (t - tmin) / (tmax - tmin) if tmax > tmin else 0
        if a.z > 0.5:  # upward tubes: top ring maps to the top of the cell
            vv = 1.0 - vv
        ids.append((ring, vv, c))
    for r in range(len(ids) - 1):
        ra, va, ca = ids[r]
        rb, vb, cb = ids[r + 1]
        for k in range(sides):
            if (r, k) in skip_faces:
                continue
            k2 = (k + 1) % sides
            ua, ub = ra[k][1], ra[k2][1]
            if k2 == 0:
                ub += 1.0
            out = (mb.verts[ra[k][0]] + mb.verts[ra[k2][0]]) * 0.5 - (ca + cb) * 0.5
            mb.f([ra[k][0], ra[k2][0], rb[k2][0], rb[k][0]],
                 [cell_uv(cell, ua, va), cell_uv(cell, ub, va), cell_uv(cell, ub, vb), cell_uv(cell, ua, vb)],
                 mat, outward=out)
    for capi, use, sign in ((0, cap0, -1), (len(ids) - 1, cap1, 1)):
        if not use:
            continue
        ring = ids[capi][0]
        uvs = []
        for k in range(sides):
            th = math.radians(-180 + (k + 0.5) * 360 / sides)
            uvs.append(cell_uv(cell, cap_uv[0] + 0.04 * math.sin(th), cap_uv[1] + 0.04 * math.cos(th)))
        mb.f([x[0] for x in ring], uvs, mat, outward=a * sign)
    return ids


def box(mb, group, tag, center, size, cell, mat=1, rot=None):
    """Axis-aligned box UV-mapped onto a cell (all faces share it)."""
    cx, cy, cz = center
    sx, sy, sz = (size[0] / 2, size[1] / 2, size[2] / 2)
    corners = [Vector((cx + dx * sx, cy + dy * sy, cz + dz * sz)) for dz in (-1, 1) for dy in (-1, 1) for dx in (-1, 1)]
    if rot is not None:
        corners = [Vector(center) + rot @ (c - Vector(center)) for c in corners]
    ids = [mb.v(c, group, tag) for c in corners]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    uv = [cell_uv(cell, 0.05, 0.05), cell_uv(cell, 0.95, 0.05), cell_uv(cell, 0.95, 0.95), cell_uv(cell, 0.05, 0.95)]
    for q in quads:
        cen = sum((corners[i] for i in q), Vector()) / 4
        mb.f([ids[i] for i in q], uv, mat, outward=cen - Vector(center))


# --------------------------------------------------------------------------------------------
# Head (octagonal, front 3 faces planar-projected onto the face texture)
# --------------------------------------------------------------------------------------------
HEAD_RINGS = [  # z above chin, rx, ry, y shift (negative = forward)
    (0.000, 0.034, 0.040, -0.038),
    (0.045, 0.064, 0.080, -0.014),
    (0.115, 0.0775, 0.095, 0.0),
    (0.175, 0.075, 0.094, 0.004),
    (0.215, 0.054, 0.072, 0.010),
]
HEAD_TOP = 0.232
ZTOP = 0.215  # top of front projection
HAIR_PATCH = (80, 0, 112, 14)  # head atlas pixels (128x64)


def head_uv_front(x, z, hw):
    u = (x / (2 * hw) + 0.5)
    v = z / ZTOP
    u = min(max(u, 0.004), 0.996)
    v = min(max(v, 0.004), 0.996)
    return (u * 0.5, v)


def head_uv_wrap(theta_deg, z):
    psi = theta_deg % 360.0
    u = (psi - 67.5) / 225.0
    u = min(max(u, 0.0), 1.0)
    v = min(max(z / ZTOP, 0.004), 0.996)
    return (0.5 + (u * 62 + 1) / 128.0, v)


def hair_uv(x, y, rx, ry):
    x0, y0, x1, y1 = HAIR_PATCH
    u = (x0 + (min(max(x / (2 * rx) + 0.5, 0), 1)) * (x1 - x0)) / 128
    v = 1 - (y0 + (min(max(y / (2 * ry) + 0.5, 0), 1)) * (y1 - y0)) / 64
    return (u, v)


def build_head(mb, base, sc, tag="head"):
    """base: Vector chin position (center at chin height). sc: head scale."""
    n = 8
    rings = []
    hw = HEAD_RINGS[2][1] * sc
    for (z, rx, ry, ys) in HEAD_RINGS:
        ring = []
        for k in range(n):
            th = -157.5 + 45 * k
            r = math.radians(th)
            x = math.sin(r) * rx * sc
            y = -math.cos(r) * ry * sc + ys * sc
            ring.append((mb.v(base + Vector((x, y, z * sc)), "head", tag), th, x, z * sc))
        rings.append(ring)
    for r in range(len(rings) - 1):
        A, B = rings[r], rings[r + 1]
        for k in range(n):
            k2 = (k + 1) % n
            center_th = -135 + 45 * k
            quad = [A[k], A[k2], B[k2], B[k]]
            if center_th in (-45, 0, 45):
                uvs = [head_uv_front(q[2], q[3] / sc * 1.0, hw) for q in quad]
            else:
                ths = [q[1] for q in quad]
                if k2 == 0:  # face between 157.5 and -157.5 (back)
                    ths = [ths[0], ths[1] + 360, ths[2] + 360, ths[3]]
                uvs = [head_uv_wrap(t, q[3] / sc) for t, q in zip(ths, quad)]
            mid = sum((mb.verts[q[0]] for q in quad), Vector()) / 4
            cen = base + Vector((0, 0, (HEAD_RINGS[r][0] + HEAD_RINGS[r + 1][0]) * 0.5 * sc))
            mb.f([q[0] for q in quad], uvs, 0, outward=mid - cen)
    # top: fan to an apex
    apex = mb.v(base + Vector((0, 0.012 * sc, HEAD_TOP * sc)), "head", tag)
    top = rings[-1]
    rx4, ry4 = HEAD_RINGS[-1][1] * sc, HEAD_RINGS[-1][2] * sc
    for k in range(n):
        k2 = (k + 1) % n
        a, b = top[k], top[k2]
        pa, pb = mb.verts[a[0]] - base, mb.verts[b[0]] - base
        mb.f([a[0], b[0], apex], [hair_uv(pa.x, pa.y, rx4, ry4), hair_uv(pb.x, pb.y, rx4, ry4), hair_uv(0, 0, rx4, ry4)],
             0, outward=Vector((0, 0, 1)))
    # chin cap
    chin = rings[0]
    mb.f([c[0] for c in chin], [(0.25 + 0.02 * math.sin(math.radians(c[1])), 0.012) for c in chin], 0,
         outward=Vector((0, 0, -1)))
    return rings


def hair_shell(mb, base, sc, style):
    """Low-poly hair volume over the skull, UV on the always-hair patch."""
    if style in ("none", "buzz"):
        return
    n = 8
    grow = {"messy": 1.13, "short": 1.08, "side_part": 1.08, "gray_thin": 1.05, "long": 1.1, "bun": 1.07,
            "ponytail": 1.07, "bob": 1.12}[style]
    # (z front, z back, scale) rings from the hairline up
    rings_def = [(0.165, 0.10, grow), (0.205, 0.19, grow * 1.02), (0.232, 0.232, grow * 0.86)]
    if style == "bob":
        rings_def = [(0.06, 0.04, grow), (0.15, 0.12, grow), (0.205, 0.19, grow * 1.02), (0.232, 0.232, grow * 0.86)]
    import random
    rnd = random.Random(7)
    rings = []
    for (zf, zb, g) in rings_def:
        ring = []
        for k in range(n):
            th = -157.5 + 45 * k
            r = math.radians(th)
            front = (math.cos(r) + 1) * 0.5  # 1 front, 0 back
            z = zb + (zf - zb) * front
            # interpolate head radius at that z
            rx, ry, ys = head_profile(z)
            jit = (rnd.uniform(-0.012, 0.012) if style == "messy" else 0.0)
            x = math.sin(r) * rx * g * sc + jit
            y = -math.cos(r) * ry * g * sc + ys * sc + jit
            ring.append(mb.v(base + Vector((x, y, z * sc + (abs(jit) * 1.5 if style == "messy" else 0))), "head",
                             "hair"))
        rings.append(ring)
    rx4, ry4 = 0.1 * sc, 0.12 * sc
    for r in range(len(rings) - 1):
        for k in range(n):
            th = -135 + 45 * k
            if style == "bob" and r == 0 and th in (-45, 0, 45):
                continue
            if style == "bob" and r == 1 and th == 0:
                continue
            k2 = (k + 1) % n
            q = [rings[r][k], rings[r][k2], rings[r + 1][k2], rings[r + 1][k]]
            uvs = [hair_uv((mb.verts[i] - base).x, (mb.verts[i] - base).y + (r * 0.03), rx4, ry4) for i in q]
            mid = sum((mb.verts[i] for i in q), Vector()) / 4
            cen = base + Vector((0, 0, 0.13 * sc))
            mb.f(q, uvs, 0, outward=mid - cen)
    apex = mb.v(base + Vector((0, 0.01 * sc, (HEAD_TOP + 0.02) * sc)), "head", "hair")
    for k in range(n):
        k2 = (k + 1) % n
        q = [rings[-1][k], rings[-1][k2], apex]
        mb.f(q, [hair_uv((mb.verts[i] - base).x, (mb.verts[i] - base).y, rx4, ry4) for i in q], 0,
             outward=Vector((0, 0, 1)))
    back = base + Vector((0, 0.09 * sc, 0))
    hp = lambda u, v: ((HAIR_PATCH[0] + u * (HAIR_PATCH[2] - HAIR_PATCH[0])) / 128,
                       1 - (HAIR_PATCH[1] + v * (HAIR_PATCH[3] - HAIR_PATCH[1])) / 64)
    if style == "long":
        # hanging panel behind the head down to the shoulder blades (4-sided tube along -Z)
        top = back + Vector((0, 0.005, 0.2 * sc))
        bot = back + Vector((0, 0.03, -0.36 * sc))
        ids = tube_hair(mb, top, bot, [(0.0, 0.085, 0.03), (0.45, 0.09, 0.03), (1.0, 0.075, 0.018)], sc, hp)
    elif style == "ponytail":
        top = back + Vector((0, 0.01, 0.17 * sc))
        bot = back + Vector((0, 0.05, -0.12 * sc))
        tube_hair(mb, top, bot, [(0.0, 0.03, 0.03), (0.3, 0.035, 0.03), (1.0, 0.012, 0.012)], sc, hp)
    elif style == "bun":
        c = back + Vector((0, 0.03 * sc, 0.17 * sc))
        bi = len(mb.verts)
        box(mb, "head", "hair", c, (0.07 * sc, 0.06 * sc, 0.065 * sc), "black", mat=1)
        for f in mb.faces[-6:]:
            f[1][:] = [hp(0.3, 0.3), hp(0.7, 0.3), hp(0.7, 0.7), hp(0.3, 0.7)]
            f_mat = f
        mb.faces[-6:] = [(f[0], f[1], 0) for f in mb.faces[-6:]]


def tube_hair(mb, p0, p1, rings, sc, hp):
    n = 4
    ids = []
    a = (p1 - p0)
    for (t, hw, hd) in rings:
        c = p0 + a * t
        ring = []
        for k in range(n):
            th = math.radians(45 + 90 * k)
            ring.append(mb.v(c + Vector((math.sin(th) * hw * sc * 1.4, math.cos(th) * hd * sc, 0)), "head", "hair"))
        ids.append((ring, c))
    for r in range(len(ids) - 1):
        for k in range(n):
            k2 = (k + 1) % n
            q = [ids[r][0][k], ids[r][0][k2], ids[r + 1][0][k2], ids[r + 1][0][k]]
            mid = sum((mb.verts[i] for i in q), Vector()) / 4
            mb.f(q, [hp(0.2, 0.1), hp(0.8, 0.1), hp(0.8, 0.9), hp(0.2, 0.9)], 0, outward=mid - (ids[r][1] + ids[r + 1][1]) / 2)
    mb.f(ids[-1][0], [hp(0.3, 0.5), hp(0.6, 0.5), hp(0.6, 0.6), hp(0.3, 0.6)], 0, outward=(p1 - p0))
    return ids


def head_profile(z):
    """Interpolated head ring (rx, ry, yshift) at height z above chin."""
    R = HEAD_RINGS
    if z <= R[0][0]:
        return R[0][1:]
    for i in range(len(R) - 1):
        if R[i][0] <= z <= R[i + 1][0]:
            t = (z - R[i][0]) / (R[i + 1][0] - R[i][0])
            return tuple(R[i][j] * (1 - t) + R[i + 1][j] * t for j in (1, 2, 3))
    return R[-1][1:]


def scarf(mb, base, sc):
    """Headscarf (khăn): hood shell with an open front, knot under the chin."""
    n = 8
    rd = [(-0.01, -0.03, 1.22), (0.08, 0.06, 1.2), (0.17, 0.15, 1.15), (0.215, 0.215, 1.1), (0.25, 0.25, 0.75)]
    rings = []
    for (zf, zb, g) in rd:
        ring = []
        for k in range(n):
            th = -157.5 + 45 * k
            r = math.radians(th)
            front = (math.cos(r) + 1) * 0.5
            z = zb + (zf - zb) * front
            rx, ry, ys = head_profile(max(z, 0.03))
            ring.append(mb.v(base + Vector((math.sin(r) * rx * g * sc, -math.cos(r) * ry * g * sc + ys * sc, z * sc)),
                             "head", "hair"))
        rings.append(ring)
    for r in range(len(rings) - 1):
        for k in range(n):
            th = -135 + 45 * k
            if r < 2 and th in (-45, 0, 45):
                continue  # face opening
            if r == 2 and th == 0:
                continue
            k2 = (k + 1) % n
            q = [rings[r][k], rings[r][k2], rings[r + 1][k2], rings[r + 1][k]]
            u0 = (k / n)
            uvs = [cell_uv("scarf", u0, 1 - r / 4), cell_uv("scarf", u0 + 1 / n, 1 - r / 4),
                   cell_uv("scarf", u0 + 1 / n, 1 - (r + 1) / 4), cell_uv("scarf", u0, 1 - (r + 1) / 4)]
            mid = sum((mb.verts[i] for i in q), Vector()) / 4
            mb.f(q, uvs, 1, outward=mid - (base + Vector((0, 0, 0.12 * sc))))
    apex = mb.v(base + Vector((0, 0.01, 0.262 * sc)), "head", "hair")
    for k in range(n):
        q = [rings[-1][k], rings[-1][(k + 1) % n], apex]
        mb.f(q, [cell_uv("scarf", 0.2, 0.1), cell_uv("scarf", 0.3, 0.1), cell_uv("scarf", 0.25, 0.0)], 1,
             outward=Vector((0, 0, 1)))


def non_la(mb, base, sc):
    """Conical hat: outer cone + inner (underside) cone so it reads from below."""
    n = 10
    top = base + Vector((0, 0.01, (HEAD_TOP + 0.17) * sc))
    rim_z = (HEAD_TOP - 0.035) * sc
    R = 0.24 * sc
    rim, inner = [], []
    for k in range(n):
        th = math.radians(k * 360 / n)
        rim.append(mb.v(base + Vector((math.sin(th) * R, -math.cos(th) * R + 0.01, rim_z)), "head", "hat"))
        inner.append(mb.v(base + Vector((math.sin(th) * R * 0.98, -math.cos(th) * R * 0.98 + 0.01, rim_z + 0.004)),
                          "head", "hat"))
    ap = mb.v(top, "head", "hat")
    ap2 = mb.v(top - Vector((0, 0, 0.02 * sc)), "head", "hat")
    for k in range(n):
        k2 = (k + 1) % n
        u0, u1 = k / n, (k + 1) / n
        mid = (mb.verts[rim[k]] + mb.verts[rim[k2]] + mb.verts[ap]) / 3
        mb.f([rim[k], rim[k2], ap], [cell_uv("hat", u0, 1), cell_uv("hat", u1, 1), cell_uv("hat", (u0 + u1) / 2, 0)], 1,
             outward=mid - (base + Vector((0, 0, rim_z - 0.2))))
        mb.f([inner[k], inner[k2], ap2], [cell_uv("hat", u0, 0.9), cell_uv("hat", u1, 0.9), cell_uv("hat", (u0 + u1) / 2, 0.1)],
             1, outward=Vector((0, 0, -1)))


# --------------------------------------------------------------------------------------------
# Body
# --------------------------------------------------------------------------------------------
def body_layout(p):
    """Joint positions (Blender coords, meters)."""
    H = p["height"]
    k = H / 1.70
    fem = p["sex"] == "f"
    w = p["build"] * (k ** 0.4) * (0.92 if fem else 1.0)
    head_sc = p["head_scale"] * (0.96 if fem else 1.0) * (k ** 0.25 if H < 1.9 else 1.03)
    J = {}
    J["k"], J["w"], J["fem"], J["head_sc"] = k, w, fem, head_sc
    head_h = HEAD_TOP * head_sc
    J["chin"] = Vector((0, -0.005, H - head_h))
    J["neck_top"] = Vector((0, 0.01, H - head_h + 0.01))
    neck_len = 0.075 * k + p["neck_extra"]
    J["neck_base"] = Vector((0, 0.012, J["neck_top"].z - neck_len))
    J["shoulder_z"] = J["neck_base"].z + 0.005
    J["chest_base"] = 1.17 * k
    J["waist"] = 1.0 * k
    J["hip_joint"] = 0.885 * k
    J["knee"] = 0.47 * k
    J["ankle"] = 0.075 * k
    sh = (0.165 if not fem else 0.148) * w
    J["shoulder_x"] = sh
    J["hip_x"] = 0.085 * w * (1.06 if fem else 1.0)
    al = p["arm_scale"]
    J["upper_arm_len"] = 0.29 * k * (al ** 0.9)
    J["lower_arm_len"] = 0.245 * k * al
    J["hand_len"] = 0.17 * k * (al ** 0.7)
    return J


def build_body(mb, p, J):
    k, w, fem = J["k"], J["w"], J["fem"]
    g = 1.0 - 0.18 * p["gaunt"]
    belly = p["belly"]
    # hips (pelvis)
    hz = J["hip_joint"]
    hipw = (0.15 if not fem else 0.168) * w
    tube(mb, "hips", "hips", (0, 0, hz - 0.07 * k), (0, 0, J["waist"] + 0.02),
         [(0.0, hipw * 0.82, 0.085 * w, 0.0), (0.45, hipw, 0.105 * w, 0.0), (1.0, hipw * 0.93 * g, 0.1 * w * g, 0.0)],
         8, "hips", cap0=True, cap1=False, cap_uv=(0.5, 0.85))
    # abdomen (spine)
    tube(mb, "spine", "spine", (0, 0, J["waist"] - 0.02), (0, 0, J["chest_base"] + 0.03),
         [(0.0, 0.138 * w * g, 0.098 * w * g, 0.0), (0.5, (0.142 + 0.03 * belly) * w * g, (0.1 + 0.03 * belly) * w * g, -0.012 * belly),
          (1.0, 0.148 * w * g, 0.1 * w * g, 0.0)], 8, "abdomen", cap0=False, cap1=False)
    # chest
    sz = J["shoulder_z"]
    cb = J["chest_base"]
    chest_ry = (0.11 if not fem else 0.118) * w * g
    tube(mb, "chest", "chest", (0, 0.0, cb), (0, 0.01, sz + 0.03),
         [(0.0, 0.15 * w * g, 0.1 * w * g, 0.0), (0.45, 0.16 * w * (g ** 0.5), chest_ry, -0.006 if fem else 0.0),
          (0.82, J["shoulder_x"] + 0.02, 0.095 * w * g, 0.008), (1.0, 0.07 * w, 0.055 * w, 0.01)],
         8, "chest", cap0=False, cap1=True, cap_uv=(0.25, 0.4))
    # neck
    nt, nb = J["neck_top"], J["neck_base"]
    tube(mb, "neck", "neck", nb - Vector((0, 0, 0.02)), nt + Vector((0, 0, 0.03)),
         [(0.0, 0.05 * w * g, 0.052 * w * g, 0.0), (1.0, 0.043 * g, 0.046 * g, 0.0)], 6, "neck",
         cap0=False, cap1=False)
    # arms, legs, hands, feet for both sides
    for side, sx in (("L", 1), ("R", -1)):
        sh = Vector((sx * J["shoulder_x"], 0.01, sz - 0.03))
        elbow = sh + Vector((sx * 0.025, 0.02, -J["upper_arm_len"]))
        wrist = elbow + Vector((sx * 0.012, -0.025, -J["lower_arm_len"]))
        tip = wrist + Vector((sx * 0.005, -0.008, -J["hand_len"]))
        J["arm_" + side] = (sh, elbow, wrist, tip)
        ar = g * w ** 0.6
        tube(mb, "upper_arm_" + side, "arm", sh + Vector((0, 0, 0.035)), elbow - Vector((0, 0, 0.015)),
             [(0.0, 0.043 * ar, 0.048 * ar, 0.0), (0.3, 0.047 * ar, 0.048 * ar, 0.0), (1.0, 0.037 * ar, 0.04 * ar, 0.0)],
             6, "upper_arm", cap0=True, cap1=True, cap_uv=(0.25, 0.2))
        tube(mb, "lower_arm_" + side, "forearm", elbow + Vector((0, 0, 0.012)), wrist,
             [(0.0, 0.036 * ar, 0.038 * ar, 0.0), (0.35, 0.037 * ar, 0.04 * ar, 0.0), (1.0, 0.026 * ar, 0.03 * ar, 0.0)],
             6, "lower_arm", cap0=False, cap1=True, cap_uv=(0.5, 0.9))
        # mitten hand: 4-sided, flat (thin along X)
        hw = 0.95 if fem else 1.0
        tube(mb, "hand_" + side, "hand", wrist + Vector((0, 0, 0.01)), tip,
             [(0.0, 0.018 * hw, 0.03 * hw, 0.0), (0.45, 0.02 * hw, 0.045 * hw, -0.004), (1.0, 0.012 * hw, 0.03 * hw, -0.006)],
             4, "hand", cap0=False, cap1=True, cap_uv=(0.5, 0.9))
        # legs
        hip = Vector((sx * J["hip_x"], 0.0, J["hip_joint"]))
        knee = Vector((sx * J["hip_x"] * 0.95, -0.01, J["knee"]))
        ankle = Vector((sx * J["hip_x"] * 0.92, 0.01, J["ankle"]))
        J["leg_" + side] = (hip, knee, ankle)
        lg = g * w ** 0.7
        thigh = 0.078 if not fem else 0.074
        tube(mb, "upper_leg_" + side, "leg", hip + Vector((0, 0, 0.06)), knee - Vector((0, 0, 0.02)),
             [(0.0, thigh * lg, (thigh + 0.005) * lg, 0.0), (0.4, (thigh - 0.008) * lg, thigh * lg, -0.005),
              (1.0, 0.05 * lg, 0.055 * lg, 0.0)], 6, "upper_leg", cap0=False, cap1=True, cap_uv=(0.5, 0.95))
        tube(mb, "lower_leg_" + side, "shin", knee + Vector((0, 0, 0.02)), ankle - Vector((0, 0, 0.01)),
             [(0.0, 0.05 * lg, 0.053 * lg, 0.0), (0.3, 0.052 * lg, 0.06 * lg, 0.008), (1.0, 0.032 * lg, 0.035 * lg, 0.0)],
             6, "lower_leg", cap0=False, cap1=True, cap_uv=(0.5, 0.97))
        # foot: tube from heel to toe, "front" = top of foot
        fs = k ** 0.8 * (0.92 if fem else 1.0)
        heel = Vector((ankle.x, 0.045 * fs, 0.0))
        toe = Vector((ankle.x + sx * 0.012, -0.175 * fs, 0.0))
        J["foot_" + side] = (heel, toe)
        tube(mb, "foot_" + side, "foot", heel, toe,
             [(0.0, 0.032, 0.035, 0.04), (0.35, 0.042, 0.042, 0.042), (0.75, 0.047, 0.022, 0.024),
              (1.0, 0.036, 0.016, 0.017)], 4, "foot", side_hint=Vector((1, 0, 0)), front_hint=Vector((0, 0, 1)),
             cap0=True, cap1=True, cap_uv=(0.5, 0.9))
    # flared skirt / raincoat
    if p["skirt"]:
        rc = p["skirt"] == "raincoat"
        top_z = (J["waist"] + 0.02) if not rc else J["chest_base"]
        bot_z = J["knee"] + (0.04 if not rc else -0.05)
        tube(mb, "hips", "skirt", (0, 0, top_z), (0, 0, bot_z),
             [(0.0, hipw * 0.98, 0.112 * w, 0.0), (1.0, hipw * (1.45 if not rc else 1.7), 0.2 * w if not rc else 0.22 * w, 0.01)],
             8, "skirt", cap0=False, cap1=False)
        # inner copy with flipped winding so the flare isn't hollow from below
        n0 = len(mb.faces)
        tube(mb, "hips", "skirt", (0, 0, top_z), (0, 0, bot_z + 0.004),
             [(0.0, hipw * 0.95, 0.108 * w, 0.0), (1.0, hipw * (1.42 if not rc else 1.66), 0.19 * w if not rc else 0.21 * w, 0.01)],
             8, "skirt", cap0=False, cap1=False)
        for i in range(n0, len(mb.faces)):
            idx, uv, m = mb.faces[i]
            mb.faces[i] = (list(reversed(idx)), list(reversed(uv)), m)
    if p["backpack"]:
        box(mb, "chest", "bag", (0, 0.11 * w + 0.07, J["chest_base"] + 0.1), (0.27 * w, 0.12, 0.36), "bag")


# --------------------------------------------------------------------------------------------
# Armature
# --------------------------------------------------------------------------------------------
def build_armature(name, J, p):
    arm_data = bpy.data.armatures.new(name + "_rig")
    arm = bpy.data.objects.new(name + "_rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(n, head, tail, parent=None, roll=0.0):
        b = eb.new(n)
        b.head, b.tail = Vector(head), Vector(tail)
        b.roll = roll
        if parent:
            b.parent = eb[parent]
        b.use_connect = False
        b.use_deform = n != "root"
        return b

    k = J["k"]
    bone("root", (0, 0, 0), (0, 0, 0.15 * k))
    bone("hips", (0, 0, J["hip_joint"] + 0.03), (0, 0, J["waist"]), "root")
    bone("spine", (0, 0, J["waist"]), (0, 0, J["chest_base"]), "hips")
    bone("chest", (0, 0, J["chest_base"]), (0, 0.01, J["neck_base"].z), "spine")
    bone("neck", J["neck_base"], J["neck_top"], "chest")
    bone("head", J["neck_top"], J["neck_top"] + Vector((0, 0, HEAD_TOP * J["head_sc"])), "neck")
    for side, sx in (("L", 1), ("R", -1)):
        sh, elbow, wrist, tip = J["arm_" + side]
        bone("shoulder_" + side, (sx * 0.03, 0.01, J["shoulder_z"] - 0.03), sh, "chest")
        bone("upper_arm_" + side, sh, elbow, "shoulder_" + side)
        bone("lower_arm_" + side, elbow, wrist, "upper_arm_" + side)
        bone("hand_" + side, wrist, tip, "lower_arm_" + side)
        hip, knee, ankle = J["leg_" + side]
        heel, toe = J["foot_" + side]
        bone("upper_leg_" + side, hip, knee, "hips")
        bone("lower_leg_" + side, knee, ankle, "upper_leg_" + side)
        bone("foot_" + side, ankle, Vector((ankle.x, toe.y + 0.04, 0.02)), "lower_leg_" + side)
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# --------------------------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------------------------
def make_mat(mname, img_path):
    m = bpy.data.materials.new(mname)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(img_path, check_existing=True)
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return m


# --------------------------------------------------------------------------------------------
# Shape keys
# --------------------------------------------------------------------------------------------
def rot_about(co, pivot, axis, deg):
    return pivot + Matrix.Rotation(math.radians(deg), 3, axis) @ (co - pivot)


def add_shape_keys(obj, mb, J):
    obj.shape_key_add(name="Basis", from_mix=False)
    # neck_tilt: head + hair + hat tilted ~25 deg sideways around the top of the neck
    sk = obj.shape_key_add(name="neck_tilt", from_mix=False)
    piv = J["neck_top"]
    for i, t in enumerate(mb.tags):
        if t in ("head", "hair", "hat"):
            sk.data[i].co = rot_about(mb.verts[i], piv, "Y", 25.0)
        elif t == "neck":
            sk.data[i].co = rot_about(mb.verts[i], J["neck_base"], "Y", 9.0)
    # long_arms: arms reach below the knees
    sk = obj.shape_key_add(name="long_arms", from_mix=False)
    for i, (gname, t) in enumerate(zip(mb.groups, mb.tags)):
        co = mb.verts[i]
        for side in ("L", "R"):
            sh, elbow, wrist, tip = J["arm_" + side]
            ua, la = 1.25, 1.55
            new_elbow = sh + (elbow - sh) * ua
            new_wrist = new_elbow + (wrist - elbow) * la
            if gname == "upper_arm_" + side:
                sk.data[i].co = sh + (co - sh) * Vector((1, 1, ua))
            elif gname == "lower_arm_" + side:
                d = co - elbow
                sk.data[i].co = new_elbow + Vector((d.x, d.y, d.z * la))
            elif gname == "hand_" + side:
                d = co - wrist
                sk.data[i].co = new_wrist + Vector((d.x, d.y, d.z * 1.35))
    # face_distort: eyes/mouth ring pushed out, jaw dropped & stretched
    sk = obj.shape_key_add(name="face_distort", from_mix=False)
    chin = J["chin"]
    hs = J["head_sc"]
    for i, t in enumerate(mb.tags):
        if t != "head":
            continue
        co = mb.verts[i]
        d = co - chin
        z = d.z / hs
        front = d.y < -0.02 * hs
        if not front:
            continue
        if z < 0.03:          # chin: drop & push forward
            sk.data[i].co = co + Vector((0, -0.02, -0.06)) * hs
        elif z < 0.08:        # mouth ring: wide
            sk.data[i].co = co + Vector((d.x * 0.45, -0.012, -0.03 * hs))
        elif z < 0.14:        # eye ring: bulge forward, slightly asymmetric
            sk.data[i].co = co + Vector((d.x * 0.15, -0.03 * hs, 0.012 * hs * (1 if d.x > 0 else -0.6)))
        else:
            sk.data[i].co = co + Vector((0, -0.008 * hs, 0.01 * hs))


# --------------------------------------------------------------------------------------------
# Animation
# --------------------------------------------------------------------------------------------
BONES = ["root", "hips", "spine", "chest", "neck", "head"] + [
    f"{b}_{s}" for s in ("L", "R") for b in ("shoulder", "upper_arm", "lower_arm", "hand", "upper_leg", "lower_leg", "foot")]


class Animator:
    """Poses are given as armature-space euler degrees relative to the rest pose (X: + bends top-pointing
    bones forward / swings down-pointing bones backward; Z: + turns toward character's left (+X);
    Y: side roll). For *_R bones the Y and Z components are mirrored automatically when using `sym`."""

    def __init__(self, arm):
        self.arm = arm
        self.rest = {b.name: b.matrix_local.to_3x3().normalized() for b in arm.data.bones}

    def local_quat(self, bname, euler_deg):
        Q = Euler([math.radians(a) for a in euler_deg], "XYZ").to_matrix()
        R = self.rest[bname]
        return (R.inverted() @ Q @ R).to_quaternion()

    def local_loc(self, bname, delta):
        R = self.rest[bname]
        return R.inverted() @ Vector(delta)

    def pose(self, frame, rots, locs=None, interp="LINEAR"):
        locs = locs or {}
        for b in BONES:
            pb = self.arm.pose.bones[b]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = self.local_quat(b, rots.get(b, (0, 0, 0)))
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if b in ("hips", "root"):
                pb.location = self.local_loc(b, locs.get(b, (0, 0, 0)))
                pb.keyframe_insert("location", frame=frame)

    def make(self, name, keys, interp="LINEAR"):
        ad = self.arm.animation_data or self.arm.animation_data_create()
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        ad.action = act
        for frame, rots, locs in keys:
            self.pose(frame, rots, locs)
        for fc in action_fcurves(act):
            for kp in fc.keyframe_points:
                kp.interpolation = interp
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, int(keys[0][0]), act)
        strip.name = name
        ad.action = None
        for pb in self.arm.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
        return act


def action_fcurves(act):
    if hasattr(act, "fcurves") and len(getattr(act, "fcurves", [])):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out


def sym(d):
    """Expand {'upper_arm': (x,y,z)} style entries with _L/_R mirrored; explicit keys win."""
    out = {}
    for k, v in d.items():
        if k.endswith("_L") or k.endswith("_R") or k in ("root", "hips", "spine", "chest", "neck", "head"):
            out[k] = v
        else:
            out[k + "_L"] = v
            out[k + "_R"] = (v[0], -v[1], -v[2])
    return out


def mirror_lr(d):
    out = {}
    for k, v in d.items():
        if k.endswith("_L"):
            out[k[:-2] + "_R"] = (v[0], -v[1], -v[2])
        elif k.endswith("_R"):
            out[k[:-2] + "_L"] = (v[0], -v[1], -v[2])
        else:
            out[k] = (v[0], -v[1], -v[2])
    return out


def build_anims(arm, J, p):
    A = Animator(arm)
    k = J["k"]
    arms_down = {"upper_arm_L": (0, -4, 0), "upper_arm_R": (0, 4, 0), "lower_arm_L": (-6, 0, 0), "lower_arm_R": (-6, 0, 0)}
    stoop = p["stoop"]
    base = dict(arms_down)
    if stoop:
        base.update({"spine": (6 * stoop, 0, 0), "chest": (12 * stoop, 0, 0), "neck": (-4 * stoop, 0, 0),
                     "head": (-6 * stoop, 0, 0)})

    def P(*dicts):
        out = dict(base)
        for d in dicts:
            out.update(d)
        return out

    # idle: breathing, 2 s
    A.make("idle", [
        (0, P({"chest": (base.get("chest", (0, 0, 0))[0] + 0, 0, 0)}), {}),
        (30, P({"chest": (base.get("chest", (0, 0, 0))[0] - 1.8, 0, 0), "spine": (base.get("spine", (0, 0, 0))[0] + 0.6, 0, 0),
                "shoulder_L": (0, 0, 0), "upper_arm_L": (1, -5, 0), "upper_arm_R": (1, 5, 0), "head": (-1, 0, 0)}),
         {"hips": (0, 0, 0.003)}),
        (60, P({}), {}),
    ])

    # walk: 1 s cycle
    def gait(L_fwd, knee_L, knee_R, arm_amp, elbow, lean, twist):
        legs = {"upper_leg_L": (-L_fwd, 0, 0), "upper_leg_R": (L_fwd, 0, 0),
                "lower_leg_L": (knee_L, 0, 0), "lower_leg_R": (knee_R, 0, 0),
                "foot_L": (-knee_L * 0.3, 0, 0), "foot_R": (-knee_R * 0.3, 0, 0),
                "upper_arm_L": (L_fwd * arm_amp, -5, 0), "upper_arm_R": (-L_fwd * arm_amp, 5, 0),
                "lower_arm_L": (-elbow - max(0, L_fwd) * 0.4, 0, 0), "lower_arm_R": (-elbow - max(0, -L_fwd) * 0.4, 0, 0),
                "spine": (lean * 0.5 + base.get("spine", (0, 0, 0))[0], 0, 0),
                "chest": (lean * 0.5 + base.get("chest", (0, 0, 0))[0], 0, -twist * L_fwd / 25),
                "hips": (0, 0, twist * L_fwd / 25)}
        return P(legs)

    W = [
        (0, gait(24, 6, 12, 0.7, 12, 3, 4), {"hips": (0, 0, -0.02 * k)}),
        (8, gait(0, 4, 42, 0.7, 12, 3, 4), {"hips": (0, 0, 0.0)}),
        (15, gait(-24, 12, 6, 0.7, 12, 3, 4), {"hips": (0, 0, -0.02 * k)}),
        (23, gait(0, 42, 4, 0.7, 12, 3, 4), {"hips": (0, 0, 0.0)}),
        (30, gait(24, 6, 12, 0.7, 12, 3, 4), {"hips": (0, 0, -0.02 * k)}),
    ]
    A.make("walk", W)

    R_ = [
        (0, gait(40, 15, 40, 1.0, 75, 12, 8), {"hips": (0, 0, -0.04 * k)}),
        (5, gait(0, 20, 95, 1.0, 80, 12, 8), {"hips": (0, 0, 0.01)}),
        (10, gait(-40, 40, 15, 1.0, 75, 12, 8), {"hips": (0, 0, -0.04 * k)}),
        (15, gait(0, 95, 20, 1.0, 80, 12, 8), {"hips": (0, 0, 0.01)}),
        (20, gait(40, 15, 40, 1.0, 75, 12, 8), {"hips": (0, 0, -0.04 * k)}),
    ]
    A.make("run", R_)

    # stiff_run: broken, too-regular, stepped at ~7.5 fps, knees locked, arms rigid at the sides
    def stiff(L):
        return {"upper_leg_L": (-L, 0, 0), "upper_leg_R": (L, 0, 0), "lower_leg_L": (3, 0, 0), "lower_leg_R": (3, 0, 0),
                "upper_arm_L": (-8, -3, 0), "upper_arm_R": (-8, 3, 0), "lower_arm_L": (0, 0, 0), "lower_arm_R": (0, 0, 0),
                "spine": (4, 0, 0), "chest": (4, 0, 0), "neck": (8, 0, 0), "head": (6, 0, 7 if L > 0 else -7),
                "hips": (0, 0, 0)}
    A.make("stiff_run", [
        (0, stiff(38), {"hips": (0, 0, 0.0)}),
        (4, stiff(0), {"hips": (0, 0, 0.035 * k)}),
        (8, stiff(-38), {"hips": (0, 0, 0.0)}),
        (12, stiff(0), {"hips": (0, 0, 0.035 * k)}),
        (16, stiff(38), {"hips": (0, 0, 0.0)}),
    ], interp="CONSTANT")

    # head turns: 0.5 s turn, hold to 1 s
    for nm, sgn in (("head_turn_left", 1), ("head_turn_right", -1)):
        A.make(nm, [
            (0, P({}), {}),
            (15, P({"neck": (0, 0, 18 * sgn), "head": (2, 0, 52 * sgn)}), {}),
            (30, P({"neck": (0, 0, 18 * sgn), "head": (2, 0, 52 * sgn)}), {}),
        ])

    # sit: on a 0.45 m stool at a desk, forearms resting forward
    drop = -(J["hip_joint"] - 0.47)
    sitp = {"upper_leg_L": (-88, -3, 0), "upper_leg_R": (-88, 3, 0), "lower_leg_L": (88, 0, 0), "lower_leg_R": (88, 0, 0),
            "foot_L": (0, 0, 0), "foot_R": (0, 0, 0), "spine": (6, 0, 0), "chest": (6, 0, 0), "head": (8, 0, 0),
            "upper_arm_L": (-32, -8, 0), "upper_arm_R": (-32, 8, 0), "lower_arm_L": (-62, 0, -10), "lower_arm_R": (-62, 0, 10)}
    sit2 = dict(sitp, chest=(7.5, 0, 0), head=(10, 0, 2))
    A.make("sit", [(0, sitp, {"hips": (0, 0.06, drop)}), (45, sit2, {"hips": (0, 0.06, drop)}),
                   (90, sitp, {"hips": (0, 0.06, drop)})])

    # sweep (chổi rơm): bent over, both hands low on a short broom, sweeping side to side
    def sw(t):
        return {"spine": (16, 0, 0), "chest": (22, 0, -14 * t), "neck": (-8, 0, 0), "head": (-6, 0, 8 * t),
                "upper_leg_L": (-12, 0, 0), "upper_leg_R": (-4, 0, 0), "lower_leg_L": (22, 0, 0), "lower_leg_R": (14, 0, 0),
                "upper_arm_L": (-30, 8, 12 * t), "upper_arm_R": (-42, -14, 14 * t),
                "lower_arm_L": (-24, 0, 0), "lower_arm_R": (-30, 0, 0), "hand_L": (0, 0, 0), "hand_R": (0, 0, 0),
                "hips": (0, 0, 6 * t)}
    A.make("sweep", [(0, sw(1), {"hips": (0, 0, -0.04)}), (22, sw(-1), {"hips": (0, 0, -0.05)}),
                     (45, sw(1), {"hips": (0, 0, -0.04)})])

    # wait: standing at a bus stop, left hand holding a phone, head down
    def wt(t):
        return P({"upper_arm_L": (-18, -4, 6), "lower_arm_L": (-96, 0, 18), "hand_L": (0, 0, 0),
                  "upper_arm_R": (0, 6, 0), "lower_arm_R": (-8, 0, 0),
                  "neck": (12, 0, 0), "head": (16, 0, 3 * t), "hips": (0, 2 * t, 0),
                  "upper_leg_L": (0, 2, 0), "upper_leg_R": (-2, 0, 0), "lower_leg_R": (5, 0, 0)})
    A.make("wait", [(0, wt(1), {"hips": (0.01, 0, 0)}), (45, wt(-0.3), {"hips": (0.005, 0, 0)}),
                    (90, wt(1), {"hips": (0.01, 0, 0)})])

    # knock: right fist knocks 3 times on a door in front at head height
    up = {"upper_arm_R": (-62, 10, 0), "lower_arm_R": (-70, 0, 0), "hand_R": (-10, 0, 0), "head": (4, 0, 0)}
    hit = {"upper_arm_R": (-58, 10, 0), "lower_arm_R": (-48, 0, 0), "hand_R": (-10, 0, 0), "head": (4, 0, 0)}
    A.make("knock", [(0, P({}), {}), (8, P(up), {}), (12, P(hit), {}), (16, P(up), {}), (20, P(hit), {}),
                     (24, P(up), {}), (28, P(hit), {}), (34, P(up), {}), (48, P({}), {})])

    # stand_stare: perfectly still, arms at the sides, chin slightly down
    st = {"upper_arm_L": (0, -1, 0), "upper_arm_R": (0, 1, 0), "head": (5, 0, 0)}
    A.make("stand_stare", [(0, st, {}), (60, st, {})], interp="CONSTANT")

    # death_fall: knees buckle, collapse backwards
    A.make("death_fall", [
        (0, P({}), {}),
        (10, P({"upper_leg_L": (-30, 0, 0), "upper_leg_R": (-26, 0, 0), "lower_leg_L": (55, 0, 0), "lower_leg_R": (50, 0, 0),
                "spine": (10, 0, 0), "head": (15, 0, 0)}), {"hips": (0, 0, -0.25 * k)}),
        (22, P({"hips": (-70, 0, 0), "upper_leg_L": (10, 0, 0), "upper_leg_R": (20, 0, 0), "lower_leg_L": (40, 0, 0),
                "lower_leg_R": (25, 0, 0), "upper_arm_L": (0, -40, 0), "upper_arm_R": (0, 50, 0), "head": (-20, 0, 10)}),
         {"hips": (0, 0.35, -0.68 * k)}),
        (30, P({"hips": (-88, 0, 0), "upper_leg_L": (12, 0, 0), "upper_leg_R": (22, 0, 0), "lower_leg_L": (10, 0, 0),
                "lower_leg_R": (5, 0, 0), "upper_arm_L": (0, -55, 0), "upper_arm_R": (0, 65, 0), "head": (-10, 0, 25)}),
         {"hips": (0, 0.45, -(J["hip_joint"] + 0.03 - 0.12))}),
        (45, P({"hips": (-88, 0, 0), "upper_leg_L": (12, 0, 0), "upper_leg_R": (22, 0, 0), "lower_leg_L": (10, 0, 0),
                "lower_leg_R": (5, 0, 0), "upper_arm_L": (0, -55, 0), "upper_arm_R": (0, 65, 0), "head": (-10, 0, 25)}),
         {"hips": (0, 0.45, -(J["hip_joint"] + 0.03 - 0.12))}),
    ])


ANIMS = ["idle", "walk", "run", "stiff_run", "head_turn_left", "head_turn_right", "sit", "sweep", "wait", "knock",
         "stand_stare", "death_fall"]


# --------------------------------------------------------------------------------------------
# Build + export
# --------------------------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def build(name, p, out_dir):
    reset_scene()
    J = body_layout(p)
    mb = MB()
    build_body(mb, p, J)
    chin = J["chin"]
    hs = J["head_sc"]
    build_head(mb, chin, hs)
    hair_shell(mb, chin, hs, p["hair"])
    if p["scarf"]:
        scarf(mb, chin, hs)
    if p["hat"] == "non_la":
        non_la(mb, chin, hs)
    # baked rest-pose head tilt (Mimic)
    if p["head_tilt"]:
        for i, t in enumerate(mb.tags):
            if t in ("head", "hair", "hat"):
                mb.verts[i] = rot_about(mb.verts[i], J["neck_top"], "Y", p["head_tilt"])

    me = bpy.data.meshes.new(name + "_mesh")
    me.from_pydata([tuple(v) for v in mb.verts], [], [f[0] for f in mb.faces])
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    li = 0
    for pi, poly in enumerate(me.polygons):
        poly.material_index = mb.faces[pi][2]
        for j, lidx in enumerate(poly.loop_indices):
            uvl.data[lidx].uv = mb.faces[pi][1][j]
        poly.use_smooth = False
    obj = bpy.data.objects.new(name + "_mesh", me)
    bpy.context.scene.collection.objects.link(obj)
    head_tex = os.path.join(TEX, f"head_{p['head_tex'] or name}.png")
    body_tex = os.path.join(TEX, f"body_{p['body_tex'] or name}.png")
    me.materials.append(make_mat(f"{name}_head", head_tex))
    me.materials.append(make_mat(f"{name}_body", body_tex))

    # triangulate (keeps PS1 look predictable; also gives exact tri count)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    tris = len(me.polygons)

    arm = build_armature(name, J, p)
    for gname in set(mb.groups):
        vg = obj.vertex_groups.new(name=gname)
    for i, gname in enumerate(mb.groups):
        obj.vertex_groups[gname].add([i], 1.0, "REPLACE")
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

    add_shape_keys(obj, mb, J)
    build_anims(arm, J, p)

    obj["character"] = name
    arm["character"] = name
    arm["height_m"] = round(p["height"], 3)

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    arm.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
        export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=False,
        export_optimize_animation_size=False, export_reset_pose_bones=True, export_def_bones=False,
        export_skins=True, export_morph=True, export_morph_normal=False, export_extras=True,
        export_image_format="AUTO", export_materials="EXPORT", export_cameras=False, export_lights=False,
        export_leaf_bone=False, export_anim_slide_to_zero=True)
    print(f"[char] {name}: {tris} tris, {len(mb.verts)} verts -> {path}")
    return tris


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = OUT_DIR
    if "--out" in argv:
        i = argv.index("--out")
        out = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    names = argv or list(CHARACTERS)
    report = {}
    for n in names:
        report[n] = build(n, CHARACTERS[n], out)
    print("[char] TRIS", json.dumps(report))


if __name__ == "__main__":
    main()
