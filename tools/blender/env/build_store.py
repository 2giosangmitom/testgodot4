"""store.glb — "Tiện Lợi 24h Ánh Dương" convenience store + storeroom + street front.
Level coordinates (docs/level_layouts.md, Scene 2). Store floor y=0, ceiling 2.8.
Interior x -5..5, z 0..-8; storeroom x 1..5, z -8..-12; street z 0..+12 (road y -0.15).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lowpoly_env as L  # noqa: E402
import props_env as P  # noqa: E402
import streetkit as S  # noqa: E402

env = L.Env("store")
rng = random.Random(2024)
H = 2.8

# ------------------------------------------------------------------ shell
env.floor(-5, 0, 5, -8, 0.0, "tile_beige")
env.ceiling(-5, 0, 5, -8, H, "ceiling_panel")
# skirting tiles strip (darker band at the bottom of walls)
env.wall("z", -5.1, 0, -8.2, 0, H, "wall_white")                      # left
env.wall("z", 5.1, 0, -8.0, 0, H, "wall_white")                        # right
env.wall("x", -8.1, -5.2, 5.2, 0, H, "wall_white",
         openings=[(3.55, 4.45, 0, 2.1, "door")])                      # back wall + storeroom door
for x0, x1 in ((-5.0, 3.55), (4.45, 5.0)):
    env.quad((x0, 0, -7.999), (x1 - x0, 0, 0), (0, 0.12, 0), "tile_red", tint=(0.8, 0.8, 0.8))
env.box((-5.2, H, -8.2), (5.2, 3.6, 0.0), "concrete_dark", skip=("-y",))  # slab above ceiling

# glass front at z = 0 with door opening x 3.05..3.95
mull = [-5.0, -3.4, -1.7, 0.0, 1.7, 3.05, 3.95, 5.0]
for x in mull:
    env.box((x - 0.04, 0, -0.05), (x + 0.04, H, 0.05), "metal_alu")
for xa, xb in ((-5.0, 3.05), (3.95, 5.0)):
    env.box((xa, 0, -0.05), (xb, 0.15, 0.05), "metal_alu")
env.box((-5.0, 2.12, -0.05), (5.0, 2.2, 0.05), "metal_alu")           # transom bar (door head)
env.box((-5.0, H - 0.08, -0.05), (5.0, H, 0.05), "metal_alu")
with env.obj("store_front_glass"):
    for xa, xb in zip(mull[:-1], mull[1:]):
        if xa == 3.05:
            env.quad((xa + 0.04, 2.2, 0), (xb - xa - 0.08, 0, 0), (0, H - 0.08 - 2.2, 0), "glass@glass", uv="fit")
            continue
        env.quad((xa + 0.04, 0.15, 0), (xb - xa - 0.08, 0, 0), (0, 2.12 - 0.15, 0), "glass@glass", uv="fit")
        env.quad((xa + 0.04, 2.2, 0), (xb - xa - 0.08, 0, 0), (0, H - 0.08 - 2.2, 0), "glass@glass", uv="fit")
env.card((2.3, 1.45, 0.012), 0.6, 0.3, "sticker_open")
env.card((2.3, 1.45, -0.012), 0.6, 0.3, "sticker_open", yaw=180)
env.card((-4.2, 1.2, 0.012), 0.3, 0.42, "poster_lost")
env.col((-5.0, 0, -0.06), (3.05, H, 0.06), "walls")
env.col((3.95, 0, -0.06), (5.0, H, 0.06), "walls")
env.col((3.05, 2.12, -0.06), (3.95, H, 0.06), "walls")
env.marker("door_shop", (3.05, 0, 0), yaw=0)

# sign box above the glass + building above
env.box((-5.2, H, 0.0), (5.2, 3.7, 0.45), "metal_paint", skip=("-z",))
with env.obj("store_sign_emit"):
    env.quad((-1.9, 2.85, 0.452), (3.8, 0, 0), (0, 0.8, 0), "sign_store@emit", uv="fit")
for x in (-4.3, 2.9):  # side lightboxes "24h"
    with env.obj("store_sign_emit"):
        env.quad((x, 2.95, 0.452), (1.4, 0, 0), (0, 0.6, 0), "sticker_open@emit", uv="fit")
uvo = (0.3, 0.7)
env.box((-5.2, 3.7, -8.2), (5.2, 10.2, 0.0), "wall_white", skip=("-y", "-z"), uvoff=uvo, tint=(0.9, 0.9, 0.86), seg=3.3)
for fl, y in enumerate((4.5, 7.6)):
    for i, x in enumerate((-3.6, -0.6, 2.4)):
        env.quad((x, y, 0.02), (1.2, 0, 0), (0, 1.3, 0), "window_lit" if (fl, i) == (1, 2) else "window_bars", uv="fit")
    P.ac_unit(env, (4.3, y + 1.6, 0))
env.box((-5.0, 6.75, 0), (-0.2, 6.9, 0.9), "concrete_dark")            # balcony 3rd floor
env.quad((-5.0, 6.9, 0.9), (4.8, 0, 0), (0, 1.0, 0), "railing@cut", uv="fit", rect=(0, 0, 5, 1))
P.potted_plant(env, (-4.4, 6.9, 0.5), 1.0)
P.potted_plant(env, (-3.6, 6.9, 0.5), 0.8)
env.box((-5.2, 10.2, -8.2), (5.2, 10.8, 0.0), "wall_white", skip=("-y", "-z"), tint=(0.85, 0.85, 0.8))
P.water_tank(env, (2.5, 10.8, -3.0))

# ------------------------------------------------------------------ fixtures: fluorescent tubes
k = 1
for x in (-2.4, 0.8):
    for z in (-1.6, -4.0, -6.4):
        lp = P.tube_fixture(env, (x, H, z), f"tube_{k}", length=1.2, along="z")
        env.marker(f"light_tube_{k}", lp, pitch=-90)
        k += 1


# ------------------------------------------------------------------ gondolas
def gondola(x, z0, z1, stocked=True, slots=False, top_goods=True):
    zl, zh = min(z0, z1), max(z0, z1)
    Lz = zh - zl
    env.box((x - 0.25, 0, zl), (x + 0.25, 0.1, zh), "metal_dark")
    env.box((x - 0.04, 0.1, zl), (x + 0.04, 1.6, zh), "shelf_metal", skip=("-y",))
    for y in (0.5, 0.9, 1.3):
        env.box((x - 0.25, y, zl), (x + 0.25, y + 0.025, zh), "shelf_metal")
    env.box((x - 0.26, 1.58, zl - 0.02), (x + 0.26, 1.62, zh + 0.02), "metal_alu")
    for zz, f in ((zl, "-z"), (zh, "+z")):  # end panels
        zA, zB = (zz - 0.03, zz) if f == "-z" else (zz, zz + 0.03)
        env.box((x - 0.27, 0, zA), (x + 0.27, 1.62, zB), "metal_alu", mats={f: "shelf_metal"}, rects={f: (0, 0, 0.5, 1)})
    levels = [(0.1, 0), (0.525, 1), (0.925, 2), (1.325, 3)]
    for side in (-1, 1):
        for li, (y, row) in enumerate(levels):
            if not stocked and li > 0:
                continue
            h = 0.32 if li < 3 else 0.24
            xa, xb = (x + 0.04, x + 0.22) if side > 0 else (x - 0.22, x - 0.04)
            f = "+x" if side > 0 else "-x"
            v0, v1 = (3 - row) / 4.0, (3 - row) / 4.0 + h / 0.4 * 0.25
            env.box((xa, y, zl + 0.03), (xb, y + h, zh - 0.03), "shelf_goods", skip=("-y", "-x" if side > 0 else "+x", "+z", "-z"),
                    rects={f: (0, v0, Lz, v1)})
    env.col((x - 0.27, 0, zl - 0.03), (x + 0.27, 1.62, zh + 0.03), "props")
    if slots:
        n = 4
        for side, base in ((-1, 0), (1, 4)):
            for row, y in ((1, 0.525), (2, 0.925), (3, 1.325)):
                for i in range(n):
                    z = zh - (i + 0.5) * Lz / n
                    env.marker(f"slot_{row}_{base + i + 1}", (x + side * 0.14, y, z), yaw=(-90 if side > 0 else 90))


GZ0, GZ1 = -2.3, -6.1
for gi, gx in enumerate((-3.2, -1.6, 0.0, 1.6)):
    gondola(gx, GZ0, GZ1, stocked=(gi != 1), slots=(gi == 1))
# a few boxes waiting to be stocked next to gondola 2
P.crate_stack(env, (-0.8, 0, -6.6), yaw=10, n=2, rng=rng)

# ------------------------------------------------------------------ drink fridges on the back wall
FX0, FX1 = -4.95, 2.25
units = 6
uw = (FX1 - FX0) / units
env.box((FX0, 0, -8.0), (FX1, 0.2, -7.25), "metal_dark", skip=("-y", "-z"))
env.box((FX0, 1.85, -8.0), (FX1, 2.15, -7.25), "metal_alu", skip=("-z",), mats={"+z": "plastic_blue"})
env.box((FX0, 2.15, -8.0), (FX1, 2.8, -7.6), "wall_white", skip=("-y", "-z"))
for i in range(units + 1):
    x = FX0 + i * uw
    env.box((x - 0.03, 0.2, -8.0), (x + 0.03, 1.85, -7.25), "metal_alu", skip=("-z",))
with env.obj("fridge_inside_emit"):
    for i in range(units):
        x = FX0 + i * uw
        env.quad((x + 0.03, 0.2, -7.9), (uw - 0.06, 0, 0), (0, 1.65, 0), "fridge_back@emit", uv="fit")
        env.quad((x + 0.03, 0.2, -7.3), (uw - 0.06, 0, 0), (0, 0, -0.6), "fridge_back@emit", uv="fit",
                 rect=(0, 0, 1, 0.1))
for i in range(units):  # inner side walls of each bay, dim
    x = FX0 + i * uw
    env.quad((x + 0.03, 0.2, -7.3), (0, 0, -0.6), (0, 1.65, 0), "metal_alu", tint=(0.9, 0.95, 1.0))
    env.quad((x + uw - 0.03, 0.2, -7.9), (0, 0, 0.6), (0, 1.65, 0), "metal_alu", tint=(0.9, 0.95, 1.0))
with env.obj("fridge_glass"):
    for i in range(units):
        x = FX0 + i * uw
        for d in range(2):
            env.quad((x + 0.03 + d * (uw - 0.06) / 2, 0.2, -7.26), ((uw - 0.06) / 2, 0, 0), (0, 1.65, 0), "glass@glass", uv="fit")
for i in range(units):
    x = FX0 + i * uw + uw / 2
    env.box((x - 0.012, 0.25, -7.26), (x + 0.012, 1.8, -7.24), "metal_alu", skip=("-z",))
    for hx in (x - 0.08, x + 0.06):
        env.box((hx, 0.8, -7.25), (hx + 0.02, 1.3, -7.2), "metal_dark")
env.col((FX0, 0, -8.0), (FX1, 2.15, -7.2), "props")
# water packs + ice-cream chest between fridges and the storeroom door
P.crate_stack(env, (2.85, 0, -7.6), n=3, rng=rng)
env.box((2.3, 0, -6.9), (3.3, 0.85, -6.3), "metal_alu", mats={"+y": "glass_dirty", "+z": "plastic_blue"})
env.col((2.3, 0, -7.9), (3.3, 0.85, -6.3), "props")

# ------------------------------------------------------------------ counter + register + rack
CX0, CX1, CZ0, CZ1 = 2.6, 5.0, -1.8, -2.4
env.box((CX0, 0, CZ1), (CX1, 0.95, CZ0), "wood_dark", mats={"+z": "plastic_green", "+y": "metal_alu"}, skip=("+x",))
env.box((CX0 - 0.05, 0.95, CZ1 - 0.05), (CX1, 1.0, CZ0 + 0.08), "metal_alu", skip=("+x",))
env.quad((CX0, 0.12, CZ0 + 0.001), (CX1 - CX0, 0, 0), (0, 0.6, 0), "sticker_open", uv="fit")
env.col((CX0, 0, CZ1 - 0.05), (CX1, 1.0, CZ0 + 0.08), "props")
# register + monitor + scanner
env.box((3.4, 1.0, -2.25), (3.8, 1.12, -1.9), "metal_dark")
with env.at((3.6, 1.12, -2.2), yaw=0):
    env.box((-0.18, 0.05, -0.02), (0.18, 0.3, 0.02), "metal_dark", mats={"+z": "screen", "-z": "screen"},
            rects={"+z": (0, 0, 1, 1), "-z": (0, 0, 1, 1)})
    env.box((-0.02, 0, -0.02), (0.02, 0.05, 0.02), "metal_dark")
env.box((4.2, 1.0, -2.2), (4.4, 1.08, -1.95), "metal_dark")
env.box((2.8, 1.0, -2.3), (3.2, 1.25, -1.9), "metal_alu", mats={"+z": "rack_goods"}, rects={"+z": (0, 0, 1, 0.5)})  # gum display
# cigarette / phone-card rack behind the counter (faces +z, toward the door)
env.box((CX0, 0, -3.9), (4.9, 1.95, -3.55), "metal_dark", mats={"+z": "rack_goods"}, rects={"+z": (0, 0, 3, 2.5)})
env.col((CX0, 0, -3.9), (4.9, 1.95, -3.55), "props")
env.card((3.8, 2.3, -3.54), 0.9, 0.45, "poster_rent")  # shift notice taped above the rack
env.marker("hide_counter", (3.8, 0, -2.95), yaw=180)
env.marker("register", (3.6, 1.12, -2.05), yaw=180)

# ------------------------------------------------------------------ storeroom (x 1..5, z -8..-12)
SH = 2.6
env.floor(1.0, -8.0, 5.0, -12.0, 0.0, "concrete")
env.ceiling(1.0, -8.2, 5.0, -12.0, SH, "concrete")
env.wall("z", 0.9, -8.2, -12.2, 0, SH, "wall_green")
env.wall("z", 5.1, -8.0, -12.2, 0, SH, "wall_green")
env.wall("x", -12.1, 0.8, 5.2, 0, SH, "wall_green", openings=[(3.95, 4.85, 0, 2.1, "door")])
env.quad((1.0, SH, -8.2), (4.0, 0, 0), (0, H - SH, 0), "concrete_dark")   # step-down soffit seen from store
env.box((0.8, SH, -12.2), (5.2, 3.6, -8.2), "concrete_dark", skip=("-y",))
env.marker("door_storeroom", (3.55, 0, -8.0), yaw=0)
env.marker("door_back", (3.95, 0, -12.0), yaw=0)
for i, z in enumerate((-8.7, -9.5, -10.3, -11.1)):
    P.crate_stack(env, (1.35, 0, z), yaw=rng.uniform(-8, 8), n=rng.randint(2, 4), rng=rng)
    P.crate_stack(env, (1.9, 0, z - 0.1), yaw=rng.uniform(-8, 8), n=rng.randint(1, 3), rng=rng)
env.col((1.0, 0, -11.6), (2.25, 1.6, -8.3), "props")
# metal shelving on the right wall
env.box((4.45, 0, -11.2), (5.0, 1.9, -10.0), "shelf_metal", mats={"-x": "shelf_goods"}, rects={"-x": (0, 0, 1.2, 1)})
env.col((4.45, 0, -11.2), (5.0, 1.9, -10.0), "props")
# mop bucket + mop
env.cyl((2.9, 0, -11.6), 0.2, 0.32, "plastic_blue", segs=6, r_top=0.23, caps=(True, False))
env.cyl((2.9, 0.25, -11.6), 0.2, 0.0, "puddle", segs=6, caps=(False, True))
with env.at((3.0, 0.0, -11.5), roll=-12):
    env.box((-0.015, 0.05, -0.015), (0.015, 1.4, 0.015), "wood_planks")
# breaker box on the right wall (x = 5.0 inner face)
env.box((4.88, 1.35, -9.35), (5.0, 1.85, -8.95), "metal_alu", mats={"-x": "metal_dark"})
env.box((4.86, 1.4, -9.3), (4.88, 1.8, -9.0), "ac_unit", skip=("+x",))
env.marker("breaker", (4.85, 1.6, -9.15), yaw=90)
lp = P.bulb(env, (3.0, SH, -10.0), "storeroom_bulb", wire=0.2)
env.marker("light_storeroom", lp, pitch=-90)
env.card((4.7, 1.0, -8.21), 0.4, 0.5, "notice_paper", yaw=180)

# ------------------------------------------------------------------ street front (z 0 .. +12)
SX0, SX1 = -20.0, 20.0
S.street(env, SX0, SX1, 0.0, 3.0, 9.0, 11.5)
# neighbours either side of the store (closed shutters at night)
P.tube_house(env, (-9.2, 0, 0), 4.0, storeys=3, ground="shutter", rng=rng, wall="wall_yellow", sign="sign_suaxe")
P.tube_house(env, (-13.0, 0, 0), 3.8, storeys=4, ground="shutter", rng=rng, wall="wall_blue")
P.tube_house(env, (-16.6, 0, 0), 3.6, storeys=2, ground="door", rng=rng, wall="wall_pink")
P.tube_house(env, (-20.5, 0, 0), 3.9, storeys=3, ground="shutter", rng=rng, wall="wall_green")
P.tube_house(env, (5.2, 0, 0), 3.6, storeys=4, ground="shutter", rng=rng, wall="wall_green")
P.tube_house(env, (8.8, 0, 0), 4.2, storeys=3, ground="gate", rng=rng, wall="wall_white")
P.tube_house(env, (13.0, 0, 0), 3.5, storeys=2, ground="shutter", rng=rng, wall="wall_yellow", sign="sign_pho")
P.tube_house(env, (16.5, 0, 0), 4.0, storeys=3, ground="shutter", rng=rng, wall="wall_blue")
# far side houses (facades at z 11.5 facing -z)
S_rows = P.shopfront_row(env, SX0 - 0.5, SX1 + 0.5, 11.5, -1, rng, signs=["sign_taphoa", "sign_pho"], depth=6.0)
# street ends (cross facades)
P.tube_house(env, (SX0 - 0.6, 0, 11.5), 11.5, yaw=90, storeys=3, ground="shutter", rng=rng, depth=4)
P.tube_house(env, (SX1 + 0.6, 0, 0.0), 11.5, yaw=-90, storeys=3, ground="shutter", rng=rng, depth=4)
env.col((SX0 - 0.7, -0.5, 0), (SX0, 4, 11.5), "bounds")
env.col((SX1, -0.5, 0), (SX1 + 0.7, 4, 11.5), "bounds")

# streetlights at x -10 / +10 on the store-side curb, arms over the road
for i, x in enumerate((-10.0, 10.0)):
    lamp = P.streetlight(env, (x, 0, 2.65), yaw=180, name=f"streetlight_{i + 1}")
    env.marker(f"streetlight_{i + 1}", lamp, pitch=-90)
    env.col((x - 0.2, 0, 2.45), (x + 0.2, 6.5, 2.85), "props")
# electric poles + cable tangles on the far side, cables to the facades
poles = [(-15.0, 10.9), (-3.0, 10.9), (9.0, 10.9), (19.0, 10.9)]
for px, pz in poles:
    P.electric_pole(env, (px, 0, pz))
    env.col((px - 0.15, 0, pz - 0.15), (px + 0.15, 8, pz + 0.15), "props")
for (ax, az), (bx, bz) in zip(poles[:-1], poles[1:]):
    P.cables_between(env, (ax, az), (bx, bz), 7.2, n=4, sag=0.8, rng=rng)
for px, pz in poles:
    P.cables_between(env, (px, pz), (px + rng.uniform(-3, 3), 0.2), 6.8, n=2, sag=0.5, rng=rng)
P.cables_between(env, (-5.2, 0.3), (5.2, 0.3), 3.9, n=3, sag=0.25, rng=rng, spread=0.15)

# sidewalk clutter (keep x -1..2.5 in front of the glass clear for the Gazer)
P.motorbike(env, (-3.6, 0, 1.9), yaw=95)
P.motorbike(env, (-2.2, 0, 2.0), yaw=85, paint="plastic_blue")
env.col((-4.6, 0, 1.5), (-1.2, 1.0, 2.4), "props")
P.stool(env, (6.2, 0, 1.0))
P.stool(env, (6.7, 0, 1.4), mat="plastic_blue")
env.box((6.2, 0, 1.6), (6.9, 0.45, 2.1), "plastic_blue")  # low plastic table
P.trash_bin(env, (4.6, 0, 0.6))
env.col((4.25, 0, 0.25), (4.95, 1.0, 0.95), "props")
P.potted_plant(env, (-4.7, 0, 0.45))
P.potted_plant(env, (12.0, 0, 0.5), 1.2)
# store A-board sign on the sidewalk
with env.at((3.0, 0, 1.4), yaw=-15):
    env.box((-0.38, 0.45, -0.02), (0.38, 0.85, 0.02), "metal_alu", mats={"+z": "sticker_open", "-z": "sticker_open"},
            rects={"+z": (0, 0, 1, 1), "-z": (0, 0, 1, 1)})
    for lx in (-0.34, 0.3):
        env.box((lx, 0, -0.02), (lx + 0.04, 0.45, 0.02), "metal_alu", skip=("-y",))
S.puddles(env, rng, (-18, 3.6, 18, 8.4), 7, y=-0.144)

# ------------------------------------------------------------------ markers
# Gazer approach: far sidewalk -> road -> near the glass (faces the store, yaw 0 = -Z)
gz = [(-6.0, 0.0, 10.4), (-3.5, -0.15, 8.0), (-1.6, -0.15, 5.5), (-0.2, -0.15, 3.6), (0.6, 0.0, 1.8), (0.9, 0.0, 0.35)]
for i, p in enumerate(gz):
    env.marker_look(f"gazer_{i + 1}", p, (p[0] * 0.5 + 1.8, p[1], -3.0))
env.marker("spawn_default", (3.8, 0, -2.95), yaw=180)
env.marker("spawn_door", (3.5, 0, -0.9), yaw=0)
env.marker_look("cam_store_wide", (-4.6, 2.5, -0.4), (2.2, 0.6, -6.6))
env.marker_look("cam_outside_glass", (1.0, 1.5, 7.0), (1.0, 1.1, -2.0))
env.marker_look("cam_counter_pov", (3.8, 1.55, -3.1), (0.6, 1.2, 6.0))
env.marker_look("cam_storeroom", (1.3, 2.2, -8.4), (4.5, 0.6, -11.8))
env.export()
