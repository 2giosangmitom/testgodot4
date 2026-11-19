"""shrine.glb — dead-end lane past the dorm + small square with the banyan, the abandoned shrine (miếu)
and THE streetlight (Scene 3, level coordinates). Lane z -15..-35 narrowing 2.0 -> 1.5 m
(left side z -15..-31.6 is the dorm facade from dorm.glb), square x -3..3, z -35..-41.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lowpoly_env as L  # noqa: E402
import props_env as P  # noqa: E402
import streetkit as S  # noqa: E402

env = L.Env("shrine")
rng = random.Random(1313)

# ================================================================== lane z -15 .. -35
env.floor(-1.1, -15.0, 1.3, -35.0, 0.0, "concrete")
S.puddles(env, rng, (-0.8, -16.0, 0.3, -34.0), 4)
rows = []
for (line, a0, a1) in ((1.0, -22.0, -15.0), (0.8, -29.0, -22.0), (0.55, -35.0, -29.0)):
    rows += S.alley_side(env, "-x", line, a0, a1, rng, jitter=0.08, storeys=(2, 4), grounds=("door", "wall", "window", "gate"))
S.alley_side(env, "+x", -1.0, -35.0, -31.6, rng, jitter=0.0, storeys=(3, 3), grounds=("wall",))
z = -15.5
while z > -34.5:
    P.cables_between(env, (-1.0, z), (0.9, z + rng.uniform(-1.5, 1.5)), rng.uniform(4.0, 7.0), n=rng.randint(1, 3), sag=0.4, rng=rng)
    z -= rng.uniform(2.5, 4.0)
P.cables_between(env, (0.6, -15.0), (0.6, -35.0), 4.6, n=3, sag=0.5, rng=rng, spread=0.2)
P.potted_plant(env, (0.45, 0, -18.5), 0.9)
P.potted_plant(env, (0.3, 0, -27.0), 1.1)
env.cyl((0.15, 0, -31.5), 0.25, 0.7, "plastic_blue", segs=7, cap_mat="plastic_blue")
env.col((-0.1, 0, -31.75), (0.4, 0.7, -31.25), "props")
for k in range(5):  # dry leaves blown along the lane
    env.quad((rng.uniform(-0.8, 0.3), 0.008, rng.uniform(-30, -34.5)), (0.5, 0, 0), (0, 0, -0.5), "leaves_clump@cut", uv="fit")

# ================================================================== the square (x -3..3, z -35..-41)
SQX0, SQX1, SQZ0, SQZ1 = -3.0, 3.0, -35.0, -41.0
env.floor(SQX0, SQZ0, SQX1, SQZ1, 0.0, "grass_dirt")
env.quad((-0.6, 0.006, SQZ0), (1.4, 0, 0), (0, 0, -2.3), "concrete_dark", uv="world")
# crumbling brick boundary walls with old houses set back behind them
env.box((SQX0 - 0.2, 0, SQZ1), (SQX0, 2.3, SQZ0), "brick", skip=("-y",))
env.box((SQX1, 0, SQZ1), (SQX1 + 0.2, 2.1, SQZ0), "brick", skip=("-y",))
env.box((SQX0 - 0.2, 0, SQZ1 - 0.2), (SQX1 + 0.2, 2.5, SQZ1), "brick", skip=("-y",))
env.col((SQX0 - 0.2, 0, SQZ1), (SQX0, 3.0, SQZ0), "walls")
env.col((SQX1, 0, SQZ1), (SQX1 + 0.2, 3.0, SQZ0), "walls")
env.col((SQX0 - 0.2, 0, SQZ1 - 0.2), (SQX1 + 0.2, 3.0, SQZ1), "walls")
P.tube_house(env, (SQX0 - 1.2, 0, SQZ0), 6.0, yaw=90, storeys=3, ground="wall", rng=rng, depth=4, col=False, balcony=False)
P.tube_house(env, (SQX1 + 1.2, 0, SQZ1), 6.0, yaw=-90, storeys=2, ground="wall", rng=rng, depth=4, col=False)
P.tube_house(env, (SQX0 - 1.2, 0, SQZ1 - 1.2), 8.4, yaw=0, storeys=4, ground="wall", rng=rng, depth=4, col=False)
for (a, b) in (((SQX0 - 1.2, -36.0), (SQX1 + 1.2, -39.0)), ((SQX0 - 1.2, -40.0), (SQX1 + 1.2, -37.0))):
    P.cables_between(env, a, b, 6.5, n=2, sag=0.8, rng=rng)

# ================================================================== banyan + its little root altar
TREE = (-1.55, 0.0, -39.3)
P.banyan(env, TREE, scale=0.85, rng=random.Random(9), canopy_min=7.6)
env.cyl((-0.42, 0.0, -38.55), 0.13, 0.16, "terracotta", segs=6, r_top=0.15, cap_mat="incense_ash")
env.marker("banyan", (-0.4, 0.0, -38.3), yaw=-60)

# ================================================================== the shrine (miếu), centre (1.55, -38.95), faces +z
SC = (1.55, 0.0, -38.95)
with env.at(SC):
    H0 = 0.35
    env.box((-1.25, 0, -1.25), (1.25, H0, 1.25), "brick", mats={"+y": "concrete_dark"}, skip=("-y",))
    env.box((-0.6, 0, 1.25), (0.6, 0.17, 1.55), "concrete", skip=("-y", "-z"), tint=(0.8, 0.8, 0.78))
    env.col((-1.25, 0, -1.25), (1.25, H0, 1.25), "floor")
    env.col_ramp((0, 0, 1.75), (0, H0, 1.2), 1.2, cat="stairs")
    old = (0.62, 0.58, 0.5)
    env.box((-1.1, H0, -1.15), (1.1, 2.3, -0.95), "wall_yellow", tint=old)
    for sx in (-1, 1):
        x0, x1 = (-1.15, -0.95) if sx < 0 else (0.95, 1.15)
        env.box((x0, H0, -1.15), (x1, 2.3, 0.15), "wall_yellow", tint=old)
        env.col((x0, H0, -1.15), (x1, 2.3, 0.15), "walls")
        env.box((sx * 1.05 - 0.08, H0, 0.97), (sx * 1.05 + 0.08, 2.3, 1.13), "lacquer_red")
        env.col((sx * 1.05 - 0.08, H0, 0.97), (sx * 1.05 + 0.08, 2.3, 1.13), "walls")
    env.col((-1.1, H0, -1.15), (1.1, 2.3, -0.95), "walls")
    env.box((-1.15, 2.1, 0.97), (1.15, 2.3, 1.13), "lacquer_red")
    env.box((-0.45, 1.84, 1.13), (0.45, 2.1, 1.17), "lacquer_red", mats={"+z": "altar"}, rects={"+z": (0.1, 0.35, 0.9, 0.65)})
    env.ceiling(-1.15, -1.15, 1.15, 1.13, 2.3, "wood_dark")
    # curved hip roof with upturned corners
    ey, ry, o, rx = 2.35, 3.35, 1.65, 0.6
    E = {(-1, 1): (-o, ey, o), (1, 1): (o, ey, o), (1, -1): (o, ey, -o), (-1, -1): (-o, ey, -o)}
    R0, R1 = (-rx, ry, 0.0), (rx, ry, 0.0)

    def mid(a, b, t=0.5, dip=0.13):
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t - dip, a[2] + (b[2] - a[2]) * t)
    M = {(-1, 1): mid(E[(-1, 1)], R0), (1, 1): mid(E[(1, 1)], R1), (1, -1): mid(E[(1, -1)], R1), (-1, -1): mid(E[(-1, -1)], R0)}
    roof = "roof_tiles"
    env.face([E[(-1, 1)], E[(1, 1)], M[(1, 1)], M[(-1, 1)]], roof)
    env.face([M[(-1, 1)], M[(1, 1)], R1, R0], roof)
    env.face([E[(1, -1)], E[(-1, -1)], M[(-1, -1)], M[(1, -1)]], roof)
    env.face([M[(1, -1)], M[(-1, -1)], R0, R1], roof)
    env.face([E[(-1, -1)], E[(-1, 1)], M[(-1, 1)], M[(-1, -1)]], roof)
    env.face([M[(-1, -1)], M[(-1, 1)], R0], roof)
    env.face([E[(1, 1)], E[(1, -1)], M[(1, -1)], M[(1, 1)]], roof)
    env.face([M[(1, 1)], M[(1, -1)], R1], roof)
    env.quad((-o, ey - 0.01, -o), (2 * o, 0, 0), (0, 0, 2 * o), "wood_dark")                     # soffit
    env.box((-rx - 0.05, ry - 0.06, -0.08), (rx + 0.05, ry + 0.08, 0.08), roof)
    for sx in (-1, 1):
        with env.at((sx * (rx + 0.05), ry - 0.02, 0), roll=-sx * 35):
            env.box((-0.05, 0, -0.05), (0.05, 0.38, 0.05), "lacquer_red")
    for (sx, sz), p in E.items():
        with env.at(p, yaw=math.degrees(math.atan2(sx, sz)), pitch=55):
            env.cyl((0, 0, 0), 0.07, 0.42, roof, segs=4, r_top=0.015, caps=(False, False))
    # altar (two tiers), incense bowl, broken oil lamp, cracked photo, vases
    env.box((-0.75, H0, -0.95), (0.75, 1.15, -0.45), "lacquer_red", mats={"+z": "altar"}, rects={"+z": (0, 0, 1, 1)})
    env.box((-0.6, 1.15, -0.95), (0.6, 1.42, -0.78), "lacquer_red")
    env.col((-0.75, H0, -0.95), (0.75, 1.42, -0.45), "props")
    env.cyl((0, 1.15, -0.63), 0.11, 0.12, "terracotta", segs=7, r_top=0.13, cap_mat="incense_ash")
    for k in range(5):
        a = k * 1.3
        with env.at((math.sin(a) * 0.06, 1.27, -0.63 + math.cos(a) * 0.05), pitch=rng.uniform(-15, 15), roll=rng.uniform(-15, 15)):
            env.box((-0.006, 0, -0.006), (0.006, rng.uniform(0.04, 0.12), 0.006), "plastic_red", skip=("-y",))
    env.cyl((-0.45, 1.15, -0.62), 0.07, 0.03, "metal_alu", segs=6, tint=(0.9, 0.75, 0.4))
    env.cyl((-0.45, 1.18, -0.62), 0.03, 0.05, "metal_alu", segs=5, tint=(0.9, 0.75, 0.4))
    with env.obj("shrine_lamp_glass"):
        env.cyl((-0.45, 1.23, -0.62), 0.045, 0.06, "glass_dirty@glass", segs=6, caps=(False, False))
        with env.at((-0.2, 1.155, -0.4), yaw=30):
            env.quad((-0.04, 0, 0.03), (0.08, 0, 0), (0, 0, -0.06), "glass_dirty@glass", uv="fit")
    with env.at((0.42, 1.15, -0.7), pitch=-14):
        env.box((-0.12, 0, -0.015), (0.12, 0.3, 0.015), "wood_dark", mats={"+z": "photo_cracked"}, rects={"+z": (0, 0, 1, 1)})
    for vx in (-0.68, 0.68):
        env.cyl((vx, 1.15, -0.8), 0.05, 0.18, "terracotta", segs=5, r_top=0.035)
        for k in range(3):
            with env.at((vx, 1.33, -0.8), yaw=k * 120, pitch=rng.uniform(10, 30)):
                env.box((-0.004, 0, -0.004), (0.004, 0.2, 0.004), "wood_dark", skip=("-y",))
    env.card((0, 1.75, -0.94), 0.8, 0.5, "altar", rect=(0.15, 0.15, 0.85, 0.85))
    # outdoor stone incense urn in front
    env.cyl((0, 0, 1.95), 0.24, 0.45, "concrete", segs=7, r_top=0.3, cap_mat="incense_ash", tint=(0.7, 0.7, 0.68))
    env.col((-0.3, 0, 1.65), (0.3, 0.45, 2.25), "props")
    # fallen joss paper on the plinth and the ground
    for k in range(14):
        on_plinth = k < 6
        y = H0 + 0.004 if on_plinth else 0.008
        x = rng.uniform(-1.0, 1.0) if on_plinth else rng.uniform(-2.5, 1.2)
        z = rng.uniform(-0.3, 1.1) if on_plinth else rng.uniform(1.3, 3.5)
        with env.at((x, y, z), yaw=rng.uniform(0, 90)):
            env.quad((-0.08, 0, 0.08), (0.16, 0, 0), (0, 0, -0.16), "joss_paper", uv="fit")
env.marker("incense_bowl", (SC[0], 1.28, SC[2] - 0.63), yaw=0)
env.marker("shrine_lamp", (SC[0] - 0.45, 1.25, SC[2] - 0.62), yaw=0)
env.marker("photo_frame", (SC[0] + 0.42, 1.3, SC[2] - 0.68), yaw=0)
env.marker("shrine_altar", (SC[0], 0.35, SC[2] + 0.3), yaw=0)
env.marker("shrine_front", (SC[0], 0.0, SC[2] + 2.0), yaw=0)

# ================================================================== THE streetlight (old, slightly bent), behind-right of the shrine
BASE = (2.55, 0.0, -40.55)
with env.obj("the_streetlight", origin=BASE):
    lamp = P.streetlight(env, BASE, yaw=145, name="the_streetlight", height=5.7, arm=1.7, tilt=-4.0, tilt_roll=3.0)
env.col((BASE[0] - 0.22, 0, BASE[2] - 0.22), (BASE[0] + 0.22, 5.0, BASE[2] + 0.22), "props")
env.marker("the_streetlight", lamp, pitch=-90)
env.marker("the_streetlight_base", BASE, yaw=145)
env.card((BASE[0] - 0.12, 1.5, BASE[2] + 0.12), 0.3, 0.42, "poster_lost", yaw=-35)

# ================================================================== markers / cameras
env.marker("spawn_shrine", (0.0, 0.0, -33.5), yaw=0)
env.marker("lane_mid", (0.0, 0.0, -25.0), yaw=0)
env.marker_look("cam_shrine_wide", (-0.4, 2.3, -33.6), (1.3, 1.3, -39.6))
env.marker_look("cam_streetlight_low", (-0.1, 0.3, -36.0), lamp)
env.marker_look("cam_lane_to_shrine", (0.0, 1.6, -16.0), (0.8, 2.5, -40.0))
env.export()
