"""Reusable low-poly env pieces (used inline by the level builders and exported standalone).
All functions build in the env's *current* transform; local frame = Godot axes.
"""
import math
import random

WALLS = ["wall_yellow", "wall_green", "wall_white", "wall_blue", "wall_pink"]
SHUTTERS = ["shutter_grey", "shutter_green", "shutter_blue"]


# ------------------------------------------------------------------ small props
def stool(env, pos, yaw=0.0, mat="plastic_red", h=0.27):
    with env.at(pos, yaw=yaw):
        env.box((-0.15, h - 0.03, -0.15), (0.15, h, 0.15), mat)
        for sx in (-1, 1):
            for sz in (-1, 1):
                env.box((sx * 0.13 - 0.025, 0, sz * 0.13 - 0.025), (sx * 0.13 + 0.025, h - 0.03, sz * 0.13 + 0.025),
                        mat, skip=("+y", "-y"))


def potted_plant(env, pos, scale=1.0, yaw=0.0):
    with env.at(pos, yaw=yaw, scale=scale):
        env.cyl((0, 0, 0), 0.16, 0.34, "terracotta", segs=6, r_top=0.21, caps=(False, False))
        env.cyl((0, 0.30, 0), 0.20, 0.0, "grass_dirt", segs=6, caps=(False, True))
        env.cross_cards((0, 0.65, 0), 0.75, 0.7, "leaves@cut", n=3)


def motorbike(env, pos, yaw=0.0, paint="bike_paint", lean=4.0):
    """Very low-poly step-through underbone scooter (fictional Dream-like). Front = local -z.
    Length 1.85 m, width 0.7 m, height ~1.05 m."""
    with env.at(pos, yaw=yaw, roll=lean):
        for wz in (-0.62, 0.62):
            with env.at((0.05, 0.29, wz), roll=90):
                env.cyl((0, 0, 0), 0.29, 0.1, "rubber", segs=6)
        env.box((-0.03, 0.29, -0.66), (0.03, 0.98, -0.58), "metal_alu")                 # fork
        env.box((-0.2, 0.36, -0.52), (0.2, 0.95, -0.36), paint)                          # leg shield
        env.box((-0.08, 0.32, -0.38), (0.08, 0.48, 0.15), paint)                         # underbone
        env.box((-0.15, 0.18, -0.15), (0.15, 0.45, 0.25), "metal_dark")                  # engine
        env.box((-0.16, 0.48, 0.0), (0.16, 0.8, 0.75), paint)                            # rear body
        env.box((-0.15, 0.8, -0.08), (0.15, 0.9, 0.68), "rubber")                        # seat
        env.box((-0.12, 0.62, 0.55), (0.12, 0.7, 1.0), paint)                            # rear fender
        env.box((-0.13, 0.55, -0.78), (0.13, 0.62, -0.5), paint)                         # front fender
        env.box((-0.36, 0.98, -0.62), (0.36, 1.03, -0.56), "metal_dark")                 # handlebar
        env.box((-0.1, 0.88, -0.72), (0.1, 1.04, -0.56), "metal_alu",
                mats={"-z": "lamp_bulb"})                                                # headlight
        env.box((-0.06, 0.7, 0.98), (0.06, 0.76, 1.03), "plastic_red")                  # tail light
        env.box((0.18, 0.05, 0.05), (0.21, 0.35, 0.09), "metal_dark")                   # side stand


def ac_unit(env, pos, yaw=0.0):
    """Outdoor AC condenser hanging on a wall; pos = wall point (bottom centre), unit sticks out +z."""
    with env.at(pos, yaw=yaw):
        env.box((-0.38, 0, 0.02), (0.38, 0.55, 0.3), "metal_alu", mats={"+z": "ac_unit"},
                rects={"+z": (0, 0, 1, 1)})
        env.box((-0.4, -0.04, 0.0), (0.4, 0.0, 0.32), "metal_dark", skip=("-z",))


def crate_stack(env, pos, yaw=0.0, n=3, rng=None):
    rng = rng or random.Random(1)
    with env.at(pos, yaw=yaw):
        y = 0.0
        for i in range(n):
            w = rng.uniform(0.45, 0.6)
            d = rng.uniform(0.35, 0.45)
            h = rng.uniform(0.3, 0.42)
            ox = rng.uniform(-0.05, 0.05)
            env.box((-w / 2 + ox, y, -d / 2), (w / 2 + ox, y + h, d / 2), "cardboard",
                    rects={"+z": (0, 0, 1, 1), "-z": (0, 0, 1, 1), "+x": (0, 0, 1, 1), "-x": (0, 0, 1, 1)})
            y += h


def trash_bin(env, pos, yaw=0.0):
    with env.at(pos, yaw=yaw):
        env.box((-0.3, 0.1, -0.3), (0.3, 1.0, 0.3), "plastic_green")
        env.box((-0.32, 1.0, -0.32), (0.32, 1.06, 0.32), "plastic_green")
        for sx in (-0.2, 0.2):
            with env.at((sx, 0.1, 0.32), roll=90):
                env.cyl((0, 0, 0), 0.1, 0.06, "rubber", segs=6)


def water_tank(env, pos):
    """Stainless rooftop water tank on a stand (classic Hanoi roof clutter)."""
    with env.at(pos):
        env.box((-0.5, 0, -0.4), (0.5, 0.5, 0.4), "metal_dark", skip=("-y",))
        with env.at((-0.7, 1.0, 0), roll=-90):
            env.cyl((0, 0, 0), 0.5, 1.4, "metal_alu", segs=8)


# ------------------------------------------------------------------ lights
def tube_fixture(env, pos, name, length=1.2, along="z"):
    """Ceiling fluorescent fixture hanging from ceiling point `pos` (y = ceiling).
    Emissive tube object `<name>_emit`. Returns the light position (just below tube)."""
    x, y, z = pos
    yaw = 0.0 if along == "z" else 90.0
    with env.at((x, y, z), yaw=yaw):
        env.box((-0.08, -0.07, -length / 2 - 0.03), (0.08, 0.0, length / 2 + 0.03), "metal_alu", skip=("+y",))
        with env.obj(name + "_emit"):
            env.quad((-0.04, -0.075, length / 2), (0.08, 0, 0), (0, 0, -length), "fluoro_tube@emit", uv="fit",
                     rect=(0, 0, 1, 1))
    return (x, y - 0.15, z)


def bulb(env, pos, name, wire=0.3, shade=True):
    """Bare hanging bulb (or wall bulb). pos = attachment point. Returns light position."""
    x, y, z = pos
    with env.at((x, y, z)):
        env.box((-0.005, -wire, -0.005), (0.005, 0, 0.005), "rubber", skip=("+y", "-y"))
        if shade:
            env.cyl((0, -wire - 0.06, 0), 0.14, 0.06, "metal_paint", segs=6, r_top=0.03, caps=(False, False))
        with env.obj(name + "_emit"):
            env.cyl((0, -wire - 0.12, 0), 0.04, 0.08, "lamp_bulb@emit", segs=4, caps=(True, False), uv_v=(0, 1))
    return (x, y - wire - 0.12, z)


def wall_lamp(env, pos, yaw, name):
    """Small bracket lamp on a wall: pos = wall point, lamp sticks out local +z. Returns light pos."""
    import mathutils
    with env.at(pos, yaw=yaw):
        env.box((-0.03, -0.03, 0), (0.03, 0.03, 0.35), "metal_dark")
        env.box((-0.1, -0.08, 0.25), (0.1, 0.0, 0.45), "metal_paint", skip=("-y",))
        with env.obj(name + "_emit"):
            env.quad((-0.08, -0.081, 0.43), (0.16, 0, 0), (0, 0, -0.16), "lamp_bulb@emit", uv="fit")
        lamp = env.M @ mathutils.Vector((0, -0.2, 0.35))
    return tuple(lamp)


def streetlight(env, pos, yaw=0.0, name="streetlight", height=6.6, arm=1.6, tilt=0.0, tilt_roll=0.0):
    """Tall sodium streetlight. Pole base at pos, arm reaches toward local -z (yaw 0 = arm points -Z).
    Emissive lens object `<name>_lamp_emit`. Returns world position of the lamp (for the light marker)."""
    import mathutils
    with env.at(pos, yaw=yaw, pitch=tilt, roll=tilt_roll):
        env.box((-0.2, 0, -0.2), (0.2, 0.5, 0.2), "concrete_dark", skip=("-y",))
        env.cyl((0, 0.5, 0), 0.11, height - 0.5, "metal_paint", segs=6, r_top=0.07, caps=(False, True))
        # curved arm: 3 segments
        pts = [(0, height - 0.3, 0), (0, height + 0.15, -arm * 0.3), (0, height + 0.32, -arm * 0.7), (0, height + 0.35, -arm)]
        for a, b in zip(pts[:-1], pts[1:]):
            dz, dy = b[2] - a[2], b[1] - a[1]
            L = math.hypot(dz, dy)
            ang = math.degrees(math.atan2(dy, -dz))
            with env.at(a, pitch=ang):
                env.box((-0.04, -0.03, -L), (0.04, 0.03, 0.0), "metal_paint")
        hx, hy, hz = pts[-1]
        env.box((-0.16, hy - 0.08, hz - 0.62), (0.16, hy + 0.06, hz + 0.05), "metal_dark")
        with env.obj(name + "_lamp_emit"):
            env.quad((-0.12, hy - 0.085, hz - 0.55), (0.24, 0, 0), (0, 0, 0.55), "lamp_sodium@emit", uv="fit")
        lamp = env.M @ mathutils.Vector((hx, hy - 0.25, hz - 0.28))
    return tuple(lamp)


def electric_pole(env, pos, height=8.0):
    with env.at(pos):
        env.box((-0.13, 0, -0.13), (0.13, height, 0.13), "concrete", skip=("-y",))
        env.box((-0.6, height - 0.8, -0.05), (0.6, height - 0.7, 0.05), "metal_dark")
        env.box((-0.25, height - 2.2, 0.13), (0.25, height - 1.6, 0.45), "metal_dark")   # transformer-ish box
        env.cyl((0, height - 3.0, 0), 0.3, 0.5, "cables@cut", segs=6, caps=(False, False), uv_v=(0.1, 0.9))


def cables_between(env, a, b, y, n=4, sag=0.6, rng=None, spread=0.35):
    """n sagging cable ribbons between points a and b (x, z), top at height y."""
    rng = rng or random.Random(7)
    for i in range(n):
        dy = rng.uniform(-spread, spread)
        oa = (a[0] + rng.uniform(-0.15, 0.15), a[1] + rng.uniform(-0.15, 0.15))
        ob = (b[0] + rng.uniform(-0.15, 0.15), b[1] + rng.uniform(-0.15, 0.15))
        v0 = rng.choice([0.0, 0.25, 0.5])
        env.strip(oa, ob, y + dy - 0.25, y + dy, "cables@cut", uv="fit", rect=(0, v0, max(1, round(math.hypot(b[0] - a[0], b[1] - a[1]) / 2)), v0 + 0.25),
                  sag=sag * rng.uniform(0.6, 1.3), segs=4)


def ceiling_fan(env, hub, name, drop=0.45):
    """Ceiling fan; hub = ceiling point. Separate object `name` with pivot on the rotation axis."""
    x, y, z = hub
    with env.at((x, y, z)):
        with env.obj(name):
            env.box((-0.015, -drop, -0.015), (0.015, 0, 0.015), "metal_paint", skip=("+y", "-y"))
            env.cyl((0, -drop - 0.1, 0), 0.13, 0.1, "metal_paint", segs=6)
            for k in range(3):
                with env.at((0, -drop - 0.06, 0), yaw=120 * k):
                    env.box((-0.06, -0.008, -0.72), (0.06, 0.008, -0.12), "metal_alu")


def fence_railing(env, a, b, y0, h, mat="railing@cut", col=True, cat="railing", post=True):
    """Cutout railing panel between ground points a, b (x, z) from y0 to y0+h, with posts."""
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    env.strip(a, b, y0, y0 + h, mat, uv="fit", rect=(0, 0, max(1, round(L)), 1))
    if post:
        for p in (a, b):
            env.box((p[0] - 0.04, y0, p[1] - 0.04), (p[0] + 0.04, y0 + h + 0.05, p[1] + 0.04), "metal_paint")
        env.box((min(a[0], b[0]) - 0.03, y0 + h, min(a[1], b[1]) - 0.03),
                (max(a[0], b[0]) + 0.03, y0 + h + 0.05, max(a[1], b[1]) + 0.03), "metal_paint")
    if col:
        env.col((min(a[0], b[0]) - 0.05, y0, min(a[1], b[1]) - 0.05),
                (max(a[0], b[0]) + 0.05, y0 + max(h, 1.0), max(a[1], b[1]) + 0.05), cat)


# ------------------------------------------------------------------ trees
def small_tree(env, pos, h=4.0, scale=1.0):
    with env.at(pos, scale=scale):
        env.cyl((0, 0, 0), 0.14, h * 0.6, "bark", segs=5, r_top=0.09, caps=(False, False))
        for k, (yy, s) in enumerate([(h * 0.55, 2.4), (h * 0.75, 2.0), (h * 0.95, 1.4)]):
            env.cross_cards((0, yy, 0), s, s * 0.8, "leaves@cut", n=2, yaw=25 * k)
            with env.at((0, yy - 0.1, 0), pitch=-90):
                env.quad((-s / 2, -s / 2, 0), (s, 0, 0), (0, s, 0), "leaves@cut", uv="fit")


def banyan(env, pos, scale=1.0, rng=None, cloth=True):
    """Giant banyan (cây đa): thick fluted trunk, root flares, leaning limbs, aerial roots and a
    broad canopy of leaf cards. ~12 m wide, ~11 m tall at scale 1."""
    rng = rng or random.Random(42)
    with env.at(pos, scale=scale):
        env.cyl((0, 0, 0), 1.25, 3.2, "bark", segs=9, r_top=0.85, caps=(False, False))
        env.cyl((0, 3.2, 0), 0.85, 2.2, "bark", segs=8, r_top=0.6, caps=(False, True))
        for k in range(6):  # root flares / buttresses
            with env.at((0, 0, 0), yaw=k * 60 + rng.uniform(-12, 12)):
                env.face([(-0.18, 0, -1.2), (0.18, 0, -1.2), (0.12, 0, -2.4), (0, 1.5, -1.0)], "bark")
                env.face([(-0.18, 0, -1.2), (0, 1.5, -1.0), (0.12, 0, -2.4)][::-1], "bark")
                env.face([(0.18, 0, -1.2), (0, 1.5, -1.0), (0.12, 0, -2.4)], "bark")
        limbs = []
        for k in range(5):
            yaw = k * 72 + rng.uniform(-20, 20)
            with env.at((0, 4.0 + rng.uniform(-0.5, 1.0), 0), yaw=yaw, pitch=-55 + rng.uniform(-10, 10)):
                ln = rng.uniform(4.0, 5.5)
                with env.at((0, 0, 0), pitch=90):
                    env.cyl((0, 0, 0), 0.4, ln, "bark", segs=6, r_top=0.18, caps=(False, True))
            limbs.append((yaw, ln))
        for yaw, ln in limbs:  # aerial roots hanging from limbs
            a = math.radians(yaw)
            for t in (0.45, 0.8):
                d = ln * t * 0.82
                x, z = -math.sin(a) * d, -math.cos(a) * d
                top = 4.2 + ln * t * 0.55
                env.cyl((x, 0, z), 0.06, top, "bark", segs=4, r_top=0.03, caps=(False, False))
        # canopy: layered horizontal + upright leaf cards
        for k in range(16):
            a = rng.uniform(0, math.tau)
            r = rng.uniform(0.5, 5.5)
            x, z = math.sin(a) * r, math.cos(a) * r
            y = rng.uniform(6.0, 10.0) - r * 0.25
            s = rng.uniform(3.5, 5.0)
            with env.at((x, y, z), yaw=rng.uniform(0, 360), pitch=-90 + rng.uniform(-25, 25)):
                env.quad((-s / 2, -s / 2, 0), (s, 0, 0), (0, s, 0), "leaves@cut", uv="fit", rect=(0, 0, 2, 2))
        for k in range(10):
            a = rng.uniform(0, math.tau)
            r = rng.uniform(2.0, 5.5)
            x, z = math.sin(a) * r, math.cos(a) * r
            env.cross_cards((x, rng.uniform(5.5, 8.5), z), rng.uniform(3, 4.5), rng.uniform(2.5, 3.5), "leaves@cut",
                            n=2, yaw=rng.uniform(0, 90), rect=(0, 0, 2, 1.5))
        if cloth:  # red cloth tied around the sacred tree
            env.cyl((0, 1.2, 0), 1.13, 0.22, "lacquer_red", segs=9, r_top=1.11, caps=(False, False))
    env.col((pos[0] - 0.9 * scale, 0, pos[2] - 0.9 * scale), (pos[0] + 0.9 * scale, 4.0, pos[2] + 0.9 * scale), "props")


# ------------------------------------------------------------------ facades
def tube_house(env, pos, width, yaw=0.0, storeys=3, wall=None, ground="shutter", sign=None, rng=None,
               depth=6.0, storey_h=3.3, balcony=None, ac=None, col=True, ground_h=None, upper_windows=True,
               side_walls=True, roof=True, lit_window=False, name=None, door_tex="door_wood", sign_emit=False):
    """Narrow Hanoi tube house. Local frame: facade at z=0 facing +z, x 0..width, house goes to -z.
    ground: 'shutter' | 'door' | 'gate' | 'wall' | 'window' | 'none'"""
    rng = rng or random.Random(int(pos[0] * 13 + pos[2] * 7 + width * 3))
    wall = wall or rng.choice(WALLS)
    H = storeys * storey_h + rng.uniform(-0.2, 0.4)
    gh = ground_h or storey_h
    uvo = (rng.uniform(0, 2), rng.uniform(0, 2))
    tint_v = rng.uniform(0.82, 1.0)
    tint = (tint_v, tint_v * rng.uniform(0.96, 1.02), tint_v * rng.uniform(0.92, 1.0))
    with env.at(pos, yaw=yaw):
        skip = ["-y", "-z"] + ([] if side_walls else ["+x", "-x"])
        env.box((0, 0, -depth), (width, H, 0), wall, skip=skip, uvoff=uvo, tint=tint, seg=3.3)
        if roof:
            env.box((0, H, -depth), (width, H + 0.6, 0.0), wall, skip=["-y", "-z"], uvoff=uvo, tint=tint)
            env.box((0.12, H + 0.6, -depth), (width - 0.12, H + 0.62, -0.12), "concrete_dark", skip=["-y"])
        f = 0.02  # overlay offset in front of facade
        m = 0.3   # side margin
        if ground == "shutter":
            st = rng.choice(SHUTTERS)
            env.quad((m, 0, f), (width - 2 * m, 0, 0), (0, 2.6, 0), st)
            env.box((m - 0.05, 2.6, 0), (width - m + 0.05, 2.85, 0.18), "metal_dark")   # shutter box
        elif ground == "door":
            dw = min(1.6, width - 0.8)
            dx = rng.uniform(0.4, width - dw - 0.4)
            env.quad((dx, 0, f), (dw, 0, 0), (0, 2.3, 0), door_tex, uv="fit", rect=(0, 0, 2 if dw > 1.2 else 1, 1))
            if width - dw > 2.0:
                wx = dx + dw + 0.4 if dx + dw + 1.4 < width else 0.4
                env.quad((wx, 1.0, f), (0.9, 0, 0), (0, 1.1, 0), "window_bars", uv="fit")
        elif ground == "gate":
            env.quad((m, 0, f), (width - 2 * m, 0, 0), (0, 2.4, 0), "iron_gate@cut", uv="fit",
                     rect=(0, 0, max(1, round(width - 2 * m)), 2.4))
            env.quad((m, 0, -0.3), (width - 2 * m, 0, 0), (0, 2.4, 0), "concrete_dark")
        elif ground == "window":
            env.quad((width / 2 - 0.5, 1.0, f), (1.0, 0, 0), (0, 1.1, 0), "window_bars", uv="fit")
        if sign:
            sw = width - 0.4
            env.box((0.2, 2.9, 0.0), (0.2 + sw, 3.6, 0.15), "metal_dark", skip=("+z",))
            mat = sign + ("@emit" if sign_emit else "")
            if sign_emit:
                with env.obj((name or "sign") + "_" + sign + "_emit"):
                    env.quad((0.2, 2.9, 0.15), (sw, 0, 0), (0, 0.7, 0), mat, uv="fit")
            else:
                env.quad((0.2, 2.9, 0.15), (sw, 0, 0), (0, 0.7, 0), mat, uv="fit")
        # upper floors
        y = gh
        bal = rng.random() < 0.5 if balcony is None else balcony
        acs = rng.random() < 0.6 if ac is None else ac
        fl = 1
        while y + 2.0 < H and upper_windows:
            nwin = max(1, int(width // 2.2))
            for i in range(nwin):
                wx = (i + 0.5) * width / nwin - 0.55
                lit = lit_window and rng.random() < 0.25
                env.quad((wx, y + 0.9, f), (1.1, 0, 0), (0, 1.3, 0), "window_lit" if lit else "window_bars", uv="fit")
            if bal and fl == 1:
                env.box((0.1, y - 0.1, 0), (width - 0.1, y + 0.05, 1.0), "concrete_dark")
                env.quad((0.1, y + 0.05, 1.0), (width - 0.2, 0, 0), (0, 1.0, 0), "railing@cut", uv="fit",
                         rect=(0, 0, max(1, round(width - 0.2)), 1))
                env.box((0.1, y + 1.05, 0.95), (width - 0.1, y + 1.1, 1.02), "metal_paint")
                if rng.random() < 0.6:
                    potted_plant(env, (width - 0.5, y + 0.05, 0.6), 0.9)
                # corrugated awning over the balcony
                env.face([(0, y + 2.9, 0), (width, y + 2.9, 0), (width, y + 2.6, 1.2), (0, y + 2.6, 1.2)][::-1], "shutter_grey")
                env.face([(0, y + 2.9, 0), (width, y + 2.9, 0), (width, y + 2.6, 1.2), (0, y + 2.6, 1.2)], "shutter_grey")
            elif acs and rng.random() < 0.7:
                ac_unit(env, (rng.uniform(0.6, width - 0.6), y + 2.2, 0))
            y += storey_h
            fl += 1
    if col:
        import mathutils
        with env.at(pos, yaw=yaw):
            env.col((0, 0, -min(depth, 3.0)), (width, 4.0, 0), "buildings")
    return H


def shopfront_row(env, x0, x1, z, facing, rng, signs=(), storeys=(2, 4), widths=(3.4, 5.0), depth=8.0, **kw):
    """Row of tube houses along x from x0 to x1 with facades at z.
    facing=+1: facades face +z (houses extend to -z); facing=-1: face -z."""
    x = x0
    i = 0
    signs = list(signs)
    out = []
    while x < x1 - 0.5:
        w = min(rng.uniform(*widths), x1 - x)
        if x1 - (x + w) < 2.0:
            w = x1 - x
        s = signs.pop(0) if signs and rng.random() < 0.7 else None
        st = rng.randint(*storeys)
        if facing > 0:
            H = tube_house(env, (x, 0, z), w, yaw=0, storeys=st, sign=s, rng=rng, depth=depth, **kw)
        else:
            H = tube_house(env, (x + w, 0, z), w, yaw=180, storeys=st, sign=s, rng=rng, depth=depth, **kw)
        out.append((x, x + w, H))
        x += w
        i += 1
    return out
