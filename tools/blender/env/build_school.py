"""school.glb — Giảng đường & sân trường (Scene 1, level coordinates).
Street z 0..+14 (road y -0.15), gate at z 0, courtyard z -0..-18, building z -18..-28
(ground floor + corridor at y 0.45, floor 2 visible only), Classroom A x -5..5, z -21..-28.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lowpoly_env as L  # noqa: E402
import props_env as P  # noqa: E402
import streetkit as S  # noqa: E402

env = L.Env("school")
rng = random.Random(1975)
FY = 0.45           # ground-floor level of the building (3 steps up)
CH = 3.2            # classroom clear height
F2 = FY + CH        # floor 2 underside 3.65

# ================================================================== street (z 0 .. 14)
S.street(env, -40.0, 40.0, 0.0, 3.5, 9.5, 13.0)
P.shopfront_row(env, -40.5, -12.2, 0.0, 1, rng, storeys=(2, 4), depth=8.0)
P.shopfront_row(env, 12.2, 40.5, 0.0, 1, rng, storeys=(2, 4), depth=8.0)
P.shopfront_row(env, -40.5, 40.5, 13.0, -1, rng, signs=["sign_pho", "sign_suaxe", "sign_taphoa"], depth=6.0)
P.tube_house(env, (-40.6, 0, 13.0), 13.0, yaw=90, storeys=3, ground="shutter", rng=rng, depth=4)
P.tube_house(env, (40.6, 0, 0.0), 13.0, yaw=-90, storeys=3, ground="shutter", rng=rng, depth=4)
env.col((-40.7, -0.5, 0), (-40.0, 4, 13), "bounds")
env.col((40.0, -0.5, 0), (40.7, 4, 13), "bounds")

for i, x in enumerate((-30.0, -10.0, 10.0, 30.0)):
    lamp = P.streetlight(env, (x, 0, 3.15), yaw=180, name=f"streetlight_{i + 1}")
    env.marker(f"streetlight_{i + 1}", lamp, pitch=-90)
    env.col((x - 0.2, 0, 2.95), (x + 0.2, 6.5, 3.35), "props")
poles = [(-36.0, 12.4), (-24.0, 12.4), (-12.0, 12.4), (0.0, 12.4), (12.0, 12.4), (24.0, 12.4), (36.0, 12.4)]
for px, pz in poles:
    P.electric_pole(env, (px, 0, pz))
    env.col((px - 0.15, 0, pz - 0.15), (px + 0.15, 8, pz + 0.15), "props")
for (ax, az), (bx, bz) in zip(poles[:-1], poles[1:]):
    P.cables_between(env, (ax, az), (bx, bz), 7.2, n=4, sag=0.9, rng=rng)
for px, pz in poles[::2]:
    P.cables_between(env, (px, pz), (px + rng.uniform(-4, 4), 0.3), 6.9, n=2, sag=0.6, rng=rng)
# street banner hung across the road
env.strip((-20.0, 3.4), (-20.0, 12.6), 5.4, 6.2, "banner_street", uv="fit")
env.strip((-20.0, 12.6), (-20.0, 3.4), 5.4, 6.2, "banner_street", uv="fit")
env.box((-20.05, 0, 3.3), (-19.95, 6.4, 3.4), "metal_paint")

# bus stop shelter at x +12 (near sidewalk, facing the road)
BX0, BX1, BZ0, BZ1 = 10.5, 13.5, 1.6, 3.0
for x in (BX0, BX1):
    env.box((x - 0.05, 0, BZ0 - 0.05), (x + 0.05, 2.5, BZ0 + 0.05), "metal_alu")
    env.box((x - 0.05, 0, BZ1 - 0.15), (x + 0.05, 2.4, BZ1 - 0.05), "metal_alu")
env.face([(BX0 - 0.1, 2.5, BZ0 - 0.1), (BX1 + 0.1, 2.5, BZ0 - 0.1), (BX1 + 0.1, 2.35, BZ1 + 0.1), (BX0 - 0.1, 2.35, BZ1 + 0.1)][::-1], "metal_alu")
env.face([(BX0 - 0.1, 2.5, BZ0 - 0.1), (BX1 + 0.1, 2.5, BZ0 - 0.1), (BX1 + 0.1, 2.35, BZ1 + 0.1), (BX0 - 0.1, 2.35, BZ1 + 0.1)], "plastic_blue")
with env.obj("bus_stop_glass"):
    env.quad((BX0 + 0.05, 0.3, BZ0), (BX1 - BX0 - 0.1, 0, 0), (0, 1.9, 0), "glass_dirty@glass", uv="fit", rect=(0, 0, 3, 2))
env.box((BX0 + 0.2, 0.42, BZ0 + 0.05), (BX1 - 0.2, 0.47, BZ0 + 0.4), "metal_alu")
for x in (BX0 + 0.4, BX1 - 0.4):
    env.box((x - 0.03, 0, BZ0 + 0.15), (x + 0.03, 0.42, BZ0 + 0.3), "metal_dark")
env.box((BX1 - 0.04, 2.4, BZ1 - 0.12), (BX1 + 0.04, 3.0, BZ1 - 0.08), "metal_alu")
env.card((BX1, 2.75, BZ1 - 0.06), 0.6, 0.3, "sign_bus")
env.card((BX1, 2.75, BZ1 - 0.14), 0.6, 0.3, "sign_bus", yaw=180)
env.card((BX0 + 1.0, 1.4, BZ0 + 0.06), 0.42, 0.6, "poster_lost")
env.col((BX0 - 0.1, 0, BZ0 - 0.1), (BX1 + 0.1, 2.5, BZ0 + 0.1), "props")
env.col((BX0 + 0.2, 0, BZ0 + 0.05), (BX1 - 0.2, 0.47, BZ0 + 0.4), "props")
env.marker("bus_stop", (12.0, 0, 2.3), yaw=180)

# far-sidewalk clutter
for (x, yaw) in ((-16.0, 92), (-14.9, 88), (6.0, 95), (22.5, 85)):
    P.motorbike(env, (x, 0, 11.6), yaw=yaw, paint=rng.choice(["bike_paint", "plastic_blue", "metal_paint"]))
    env.col((x - 0.35, 0, 10.7), (x + 0.35, 1.0, 12.5), "props")
for (x, z, m) in ((18.0, 11.8, "plastic_red"), (18.5, 12.2, "plastic_blue"), (19.1, 11.7, "plastic_red"), (-28.0, 12.2, "plastic_red")):
    P.stool(env, (x, 0, z), yaw=rng.uniform(0, 90), mat=m)
for x in (-25.0, 27.0):
    P.trash_bin(env, (x, 0, 12.3))
    env.col((x - 0.35, 0, 11.95), (x + 0.35, 1.0, 12.65), "props")
P.small_tree(env, (-6.0, 0, 2.8), h=4.5)
P.small_tree(env, (20.0, 0, 2.8), h=5.0)
env.box((-6.6, 0, 2.2), (-5.4, 0.15, 3.4), "brick")
env.box((19.4, 0, 2.2), (20.6, 0.15, 3.4), "brick")
env.col((-6.2, 0, 2.6), (-5.8, 3, 3.0), "props")
env.col((19.8, 0, 2.6), (20.2, 3, 3.0), "props")
S.puddles(env, rng, (-38, 4.0, 38, 9.0), 10, y=-0.144)

# ================================================================== front fence + gate
GX = 3.25  # gate pillar centres at +-GX
for x in (-GX, GX):
    env.box((x - 0.3, 0, -0.3), (x + 0.3, 3.0, 0.3), "wall_yellow", tint=(0.9, 0.85, 0.8))
    env.box((x - 0.36, 3.0, -0.36), (x + 0.36, 3.15, 0.36), "concrete_dark")
    env.col((x - 0.3, 0, -0.3), (x + 0.3, 3.0, 0.3), "walls")
# name arch over the gate
env.box((-GX - 0.3, 3.15, -0.15), (GX + 0.3, 3.95, 0.15), "wall_yellow", mats={"+z": "sign_school", "-z": "banner_school"},
        rects={"+z": (0, 0, 1, 1), "-z": (0, 0, 1, 1)})
for xa, xb in ((-12.0, -GX - 0.3), (GX + 0.3, 12.0)):
    env.box((xa, 0, -0.12), (xb, 0.6, 0.12), "wall_yellow", tint=(0.85, 0.8, 0.75))
    P.fence_railing(env, (xa, 0.0), (xb, 0.0), 0.6, 1.6, col=False)
    env.col((xa, 0, -0.12), (xb, 2.2, 0.12), "walls")
    for x in range(int(xa) + 3, int(xb), 3):
        env.box((x - 0.15, 0, -0.15), (x + 0.15, 2.3, 0.15), "wall_yellow", tint=(0.9, 0.85, 0.8))
# sliding gate parked open behind the right fence
with env.obj("school_gate_slide"):
    env.box((GX + 0.35, 0.0, -0.45), (GX + 6.3, 0.08, -0.37), "metal_paint")
    env.box((GX + 0.35, 2.0, -0.45), (GX + 6.3, 2.08, -0.37), "metal_paint")
    for k in range(5):
        x = GX + 0.35 + k * (5.95 / 4)
        env.box((x - 0.04, 0, -0.45), (x + 0.04, 2.1, -0.37), "metal_paint")
    env.quad((GX + 0.35, 0.08, -0.41), (5.95, 0, 0), (0, 1.92, 0), "iron_gate@cut", uv="fit", rect=(0, 0, 6, 2))
    for k in range(4):
        with env.at((GX + 1.0 + k * 1.5, 0.07, -0.41), roll=90):
            env.cyl((0, -0.03, 0), 0.07, 0.06, "rubber", segs=6)
env.col((GX + 0.35, 0, -0.47), (GX + 6.3, 2.1, -0.35), "props")
env.marker("door_gate", (-GX + 0.3, 0, -0.41), yaw=0)
env.marker("gate_slide_open", (GX + 0.35, 0, -0.41), yaw=0)

# ================================================================== guard booth (x -7..-5, z -2.2..-0.3)
B0x, B1x, B0z, B1z, BH = -7.0, -5.0, -2.3, -0.4, 2.5
env.floor(B0x, B0z, B1x, B1z, 0.02, "tile_red", col=False)
env.wall("x", B1z, B0x, B1x, 0, BH, "wall_white", t=0.1, openings=[(-6.6, -5.4, 0.9, 1.9, "window")])
env.wall("x", B0z, B0x, B1x, 0, BH, "wall_white", t=0.1, openings=[(-6.7, -5.9, 0, 2.05, "door")])
env.wall("z", B1x, B0z + 0.05, B1z - 0.05, 0, BH, "wall_white", t=0.1, openings=[(-2.0, -0.7, 0.9, 1.9, "window")])
env.wall("z", B0x, B0z + 0.05, B1z - 0.05, 0, BH, "wall_white", t=0.1)
env.box((B0x - 0.25, BH, B0z - 0.25), (B1x + 0.25, BH + 0.15, B1z + 0.25), "concrete_dark")
env.ceiling(B0x + 0.05, B0z + 0.05, B1x - 0.05, B1z - 0.05, BH - 0.01, "wall_white")
with env.obj("booth_glass"):
    env.quad((-6.6, 0.9, B1z), (1.2, 0, 0), (0, 1.0, 0), "glass_dirty@glass", uv="fit")
    env.quad((B1x, 0.9, -0.7), (0, 0, -1.3), (0, 1.0, 0), "glass_dirty@glass", uv="fit")
env.box((-6.9, 0, -0.95), (-5.6, 0.75, -0.5), "wood_dark", mats={"+y": "desk_wood"})        # little table
env.box((-6.2, 0.75, -0.75), (-6.0, 0.95, -0.55), "plastic_red")                                # thermos
env.box((-6.6, 0.75, -0.8), (-6.35, 0.88, -0.6), "metal_dark")                                  # radio
P.stool(env, (-6.1, 0, -1.4), mat="plastic_blue", h=0.45)
P.stool(env, (-4.3, 0, -1.2), mat="plastic_red", h=0.45)
env.card((B0x + 0.06, 1.5, -1.3), 0.5, 0.5, "notice_paper", yaw=90)
lp = P.bulb(env, (-6.0, BH, -1.3), "booth_bulb", wire=0.15, shade=False)
env.marker("light_booth", lp, pitch=-90)
env.marker("guard_booth", (-6.1, 0, -1.4), yaw=-90)

# ================================================================== courtyard (x -11.5..11.5, z 0..-18)
env.floor(-11.5, 0.0, -1.5, -18.0, 0.0, "concrete")
env.floor(1.5, 0.0, 11.5, -18.0, 0.0, "concrete")
env.floor(-1.5, 0.0, 1.5, -17.1, 0.0, "tile_red")
for x in (-11.7, 11.7):
    env.wall("z", x, 0.1, -18.0, 0, 2.6, "wall_yellow", t=0.3, tint=(0.85, 0.82, 0.75))
# neighbours overlooking the courtyard (tall blank-ish facades above the compound walls)
for (x, yaw, z0) in ((-11.9, 90, 0.0), (11.9, -90, -18.0)):
    zz = z0
    while (zz > -18.0 if yaw == 90 else zz < 0.0):
        w = min(rng.uniform(4.0, 6.0), (zz + 18.0) if yaw == 90 else -zz)
        P.tube_house(env, (x, 0, zz), w, yaw=yaw, storeys=rng.randint(3, 5), ground="wall", rng=rng, depth=4,
                     balcony=False, col=False)
        zz += -w if yaw == 90 else w
# flagpole
env.box((-0.6, 0, -7.6), (0.6, 0.4, -6.4), "concrete", tint=(0.85, 0.85, 0.85))
env.cyl((0, 0.4, -7.0), 0.06, 9.0, "metal_alu", segs=5, r_top=0.035)
env.strip((0.05, -7.0), (1.6, -7.0), 7.9, 8.9, "flag", uv="fit", sag=0.08, segs=3)
env.strip((1.6, -7.0), (0.05, -7.0), 7.9, 8.9, "flag", uv="fit", rect=(1, 0, 0, 1), sag=0.08, segs=3)
env.col((-0.6, 0, -7.6), (0.6, 0.4, -6.4), "props")
env.col((-0.08, 0, -7.08), (0.08, 3, -6.92), "props")
env.marker("flagpole", (0, 0.4, -6.2), yaw=0)
# two trees in brick planters
for tx in (-6.0, 6.0):
    env.box((tx - 0.8, 0, -10.8), (tx + 0.8, 0.5, -9.2), "brick", skip=("+y", "-y"))
    env.quad((tx - 0.8, 0.45, -9.2), (1.6, 0, 0), (0, 0, -1.6), "grass_dirt", uv="fit")
    env.box((tx - 0.82, 0.5, -10.82), (tx + 0.82, 0.56, -9.18), "concrete", skip=("-y",))
    P.small_tree(env, (tx, 0.45, -10.0), h=5.5, scale=1.25)
    env.col((tx - 0.8, 0, -10.8), (tx + 0.8, 0.56, -9.2), "props")
# stone bench
env.box((3.0, 0.4, -14.25), (5.0, 0.5, -13.75), "concrete", tint=(0.9, 0.9, 0.88))
for x in (3.2, 4.6):
    env.box((x, 0, -14.15), (x + 0.2, 0.4, -13.85), "concrete", skip=("+y", "-y"))
env.col((3.0, 0, -14.25), (5.0, 0.5, -13.75), "props")
# notice board on legs
with env.at((-7.5, 0, -16.6), yaw=0):
    env.box((-0.9, 0.9, -0.04), (0.9, 2.0, 0.04), "wood_dark", mats={"+z": "cork"})
    for k, x in enumerate((-0.6, -0.1, 0.45)):
        env.card((x, 1.45 + 0.1 * (k % 2), 0.045), 0.35, 0.42, ["notice_paper", "poster_lost", "poster_rent"][k])
    for x in (-0.85, 0.8):
        env.box((x, 0, -0.03), (x + 0.05, 0.9, 0.03), "wood_dark")
    env.col((-0.9, 0, -0.05), (0.9, 2.0, 0.05), "props")
for x in (-10.8, 10.8):
    P.trash_bin(env, (x, 0, -16.8))
    env.col((x - 0.35, 0, -17.15), (x + 0.35, 1.0, -16.45), "props")

# bike / motorbike shed along the left wall (x -11.5 .. -9)
SX0, SX1, SZ0, SZ1 = -11.5, -9.0, -3.0, -14.0
for z in (SZ0, -6.67, -10.33, SZ1):
    env.box((SX1 - 0.06, 0, z - 0.06), (SX1 + 0.06, 2.55, z + 0.06), "metal_paint")
    env.col((SX1 - 0.07, 0, z - 0.07), (SX1 + 0.07, 2.5, z + 0.07), "props")
env.box((SX1 - 0.06, 2.5, SZ1), (SX1 + 0.06, 2.6, SZ0), "metal_paint")
roof = [(SX0, 2.95, SZ1), (SX0, 2.95, SZ0), (SX1 + 0.3, 2.55, SZ0), (SX1 + 0.3, 2.55, SZ1)]
env.face(roof, "shutter_grey")
env.face(roof[::-1], "shutter_grey")
for i, z in enumerate((-4.0, -5.4, -6.8, -8.2, -9.6, -11.0, -12.6)):
    if i == 3:
        continue
    P.motorbike(env, (-10.3, 0, z), yaw=90, paint=rng.choice(["bike_paint", "plastic_blue", "metal_paint", "bike_paint"]),
                lean=rng.uniform(2, 6))
env.col((-11.4, 0, -13.2), (-9.3, 1.0, -3.4), "props")

# ================================================================== building (z -18..-28, x -15..15)
BXL, BXR, BZF, BZB = -15.0, 15.0, -18.0, -28.0
# plinth / ground slab front face + steps
env.box((BXL, 0, BZB), (BXR, FY, BZF), "concrete", skip=("+y", "-y", "-z"), tint=(0.8, 0.8, 0.78))
for k in range(3):
    z0 = -17.1 - 0.3 * k
    env.box((-1.5, 0, z0 - 0.3), (1.5, 0.15 * (k + 1), z0), "concrete", skip=("-y", "-z"), tint=(0.9, 0.9, 0.9))
env.col_ramp((0, 0.0, -16.95), (0, FY, -18.05), 3.0, cat="stairs")
# corridor (z -18..-21) floor
env.floor(BXL, BZF, BXR, -20.9, FY, "tile_checker", cat="floor")
env.ceiling(BXL, BZF, BXR, -20.9, F2, "wall_white", tint=(0.8, 0.8, 0.78))
# columns along the front
for x in (-14.85, -9.9, -5.0, 5.0, 9.9, 14.85):
    env.box((x - 0.18, 0, BZF - 0.18), (x + 0.18, 7.35, BZF + 0.18), "wall_yellow", tint=(0.92, 0.9, 0.85))
    env.col((x - 0.18, 0, BZF - 0.18), (x + 0.18, 7.35, BZF + 0.18), "walls")
# front railing of the corridor (gap for the steps)
for xa, xb in ((BXL, -1.5), (1.5, BXR)):
    env.box((xa, FY, BZF - 0.08), (xb, FY + 0.35, BZF + 0.08), "wall_yellow", tint=(0.8, 0.78, 0.7))
    P.fence_railing(env, (xa, BZF), (xb, BZF), FY + 0.35, 0.6, col=False, post=False)
    env.box((xa, FY + 0.95, BZF - 0.06), (xb, FY + 1.0, BZF + 0.06), "metal_paint")
    env.col((xa, FY, BZF - 0.1), (xb, FY + 1.0, BZF + 0.1), "railing")
for x in (-1.5, 1.5):
    P.potted_plant(env, (x + (-0.4 if x < 0 else 0.4), FY, -18.45), 1.1)
# end walls
for x in (BXL - 0.1, BXR + 0.1):
    env.wall("z", x, BZF, BZB - 0.1, 0, 8.0, "wall_yellow", t=0.2, tint=(0.88, 0.85, 0.8))
# back wall of the corridor = classroom front walls (z -21), y FY..F2
DOOR_A = (-3.0, -2.1)
win_A = [(-1.4, 0.4), (1.1, 2.9), (3.4, 4.6)]
ops = [(DOOR_A[0], DOOR_A[1], FY, FY + 2.1, "door")] + [(a, b, FY + 0.9, FY + 2.3, "window") for a, b in win_A]
env.wall("x", -21.0, BXL, BXR, FY, F2, "wall_yellow", t=0.2, openings=ops, tint=(0.95, 0.92, 0.85))
for a, b in win_A:  # bars + glass-less wooden frame
    env.quad((a, FY + 0.9, -20.99), (b - a, 0, 0), (0, 1.4, 0), "iron_gate@cut", uv="fit", rect=(0, 0, round(b - a), 1.4))
    env.box((a, FY + 0.88, -21.12), (b, FY + 0.92, -20.88), "wood_dark")
env.marker("door_classA", (DOOR_A[0], FY, -21.0), yaw=0)
env.floor(DOOR_A[0], -20.9, DOOR_A[1], -21.1, FY, "concrete_dark", cat="floor")
# decorative closed doors + windows of rooms 1 and 3 (and floor 2)
for (dx, wins) in ((-12.6, (-11.2, -9.0, -7.0)), (6.0, (7.6, 9.8, 12.2))):
    env.quad((dx, FY, -20.89), (0.9, 0, 0), (0, 2.1, 0), "door_wood", uv="fit")
    for wx in wins:
        env.quad((wx, FY + 0.9, -20.89), (1.6, 0, 0), (0, 1.4, 0), "window_bars", uv="fit", rect=(0, 0, 2, 1))
# corridor lights
for i, x in enumerate((-9.0, 0.0, 9.0)):
    lp = P.tube_fixture(env, (x, F2, -19.5), f"corridor_tube_{i + 1}", length=1.2, along="x")
    env.marker(f"light_corridor_{i + 1}", lp, pitch=-90)
for i, x in enumerate((-9.9, 9.9)):
    lp = P.wall_lamp(env, (x, 3.0, BZF + 0.18), 0, f"courtyard_lamp_{i + 1}")
    env.marker(f"light_courtyard_{i + 1}", lp, pitch=-90)

# floor 2 (visible only): slab, railing, banner, closed doors & windows, roof, parapet + sign
env.box((BXL - 0.1, F2, BZB - 0.1), (BXR + 0.1, F2 + 0.2, BZF + 0.25), "concrete", skip=("+y", "-y"), tint=(0.85, 0.85, 0.82))
env.quad((BXL, F2 + 0.2, BZF), (BXR - BXL, 0, 0), (0, 0, -3.0), "tile_checker", seg=4)
env.box((BXL, F2 + 0.2, BZF - 0.08), (BXR, F2 + 0.55, BZF + 0.08), "wall_yellow", tint=(0.8, 0.78, 0.7))
P.fence_railing(env, (BXL, BZF), (BXR, BZF), F2 + 0.55, 0.6, col=False, post=False)
env.box((BXL, F2 + 1.15, BZF - 0.06), (BXR, F2 + 1.2, BZF + 0.06), "metal_paint")
env.quad((-6.0, F2 + 0.2, BZF + 0.1), (12.0, 0, 0), (0, 1.0, 0), "banner_school", uv="fit")
F2T = F2 + 0.2 + CH
env.quad((BXL, F2 + 0.2, -21.0), (BXR - BXL, 0, 0), (0, CH, 0), "wall_yellow", seg=3.3, tint=(0.9, 0.88, 0.8))
for x in (-12.6, -3.6, 6.0):
    env.quad((x, F2 + 0.2, -20.98), (0.9, 0, 0), (0, 2.1, 0), "door_wood", uv="fit")
for x in (-11.2, -9.0, -7.0, -2.0, 0.4, 2.8, 7.6, 9.8, 12.2):
    env.quad((x, F2 + 1.1, -20.98), (1.6, 0, 0), (0, 1.4, 0), "window_bars", uv="fit", rect=(0, 0, 2, 1))
env.ceiling(BXL, BZF, BXR, -21.0, F2T, "wall_white", tint=(0.75, 0.75, 0.72))
env.box((BXL - 0.1, F2T, BZB - 0.1), (BXR + 0.1, F2T + 0.25, BZF + 0.25), "concrete", skip=("-y",), tint=(0.8, 0.8, 0.78))
env.box((BXL - 0.1, F2T + 0.25, BZF + 0.05), (BXR + 0.1, F2T + 1.1, BZF + 0.25), "wall_yellow", tint=(0.9, 0.86, 0.78),
        mats={"+z": "wall_yellow"})
env.quad((-6.0, F2T + 0.3, BZF + 0.26), (12.0, 0, 0), (0, 0.75, 0), "sign_school", uv="fit")
P.water_tank(env, (10.0, F2T + 0.25, -24.0))
for x in (-9.0, 0.0, 9.0):
    P.bulb(env, (x, F2T, -19.5), f"f2_bulb_{int(x + 20)}", wire=0.1)
# building back wall (closes the volume)
env.wall("x", BZB - 0.1, BXL - 0.2, BXR + 0.2, 0, F2T + 0.25, "wall_yellow", t=0.2, tint=(0.8, 0.78, 0.72))

# ================================================================== Classroom A (x -5..5, z -21..-28)
CX0, CX1, CZ0, CZ1 = -4.9, 4.9, -21.1, -28.0
env.floor(CX0, CZ0, CX1, CZ1, FY, "tile_pattern", cat="floor")
env.ceiling(CX0, CZ0, CX1, CZ1, F2, "wall_white", tint=(0.92, 0.92, 0.88))
env.wall("z", -5.0, -21.1, -28.0, FY, F2, "wall_yellow", t=0.2)
env.wall("z", 5.0, -21.1, -28.0, FY, F2, "wall_yellow", t=0.2)
# dado band (painted lower wall) inside the classroom
env.quad((CX0 + 0.005, FY, CZ0), (0, 0, CZ1 - CZ0), (0, 1.0, 0), "wall_green", tint=(0.7, 0.8, 0.75))     # -x wall faces +x
env.quad((CX1 - 0.005, FY, CZ1), (0, 0, CZ0 - CZ1), (0, 1.0, 0), "wall_green", tint=(0.7, 0.8, 0.75))     # +x wall faces -x
env.quad((CX0, FY, CZ1 + 0.005), (CX1 - CX0, 0, 0), (0, 1.0, 0), "wall_green", tint=(0.7, 0.8, 0.75))     # back wall faces +z
# blackboard + teacher platform + desk
env.box((CX0, FY + 0.85, -26.5), (CX0 + 0.06, FY + 2.15, -22.5), "wood_dark", mats={"+x": "chalkboard"},
        rects={"+x": (0, 0, 1, 1)})
env.box((CX0, FY + 0.82, -26.55), (CX0 + 0.14, FY + 0.86, -22.45), "wood_dark")
env.box((CX0, FY + 2.3, -26.0), (CX0 + 0.03, FY + 2.65, -23.0), "metal_dark", mats={"+x": "banner_class"},
        rects={"+x": (0, 0, 1, 1)})
with env.obj("classroom_clock"):
    env.box((CX1 - 0.04, FY + 2.35, -24.75), (CX1, FY + 2.75, -24.35), "metal_dark", mats={"-x": "clock_face"},
            rects={"-x": (0, 0, 1, 1)})
env.marker("clock", (CX1 - 0.05, FY + 2.55, -24.55), yaw=90)
env.box((CX0, FY, CZ1), (-3.7, FY + 0.2, CZ0), "wood_planks", skip=("-y", "-x"))
env.col((CX0, FY, CZ1), (-3.7, FY + 0.2, CZ0), "floor")
env.col_ramp((-3.3, FY, -24.55), (-3.72, FY + 0.2, -24.55), 6.85, cat="stairs")
env.box((-4.6, FY + 0.2, -25.1), (-4.0, FY + 0.95, -23.9), "wood_dark", mats={"+y": "desk_wood"}, skip=("-y",))
env.col((-4.6, FY + 0.2, -25.1), (-4.0, FY + 0.95, -23.9), "props")
P.stool(env, (-4.75, FY + 0.2, -24.5), mat="plastic_red", h=0.45)
# 5 rows x 2 columns of 2-seat desks, students face -x
ROWS = (-2.4, -1.0, 0.4, 1.8, 3.2)
COLS = (-23.2, -25.9)
for c in ROWS:
    for zc in COLS:
        za, zb = zc - 0.6, zc + 0.6
        y = FY
        env.box((c - 0.225, y + 0.71, za), (c + 0.225, y + 0.75, zb), "desk_wood")                        # top
        env.box((c - 0.225, y + 0.3, za), (c - 0.205, y + 0.71, zb), "desk_wood", skip=("+y", "-y"))      # front panel
        for zz in (za, zb - 0.03):
            env.box((c - 0.225, y, zz), (c + 0.2, y + 0.71, zz + 0.03), "desk_wood", skip=("+y", "-y"))  # side panels
        env.box((c - 0.2, y + 0.45, za + 0.03), (c + 0.2, y + 0.47, zb - 0.03), "desk_wood", skip=("-y",))  # book shelf
        env.box((c + 0.38, y + 0.42, za), (c + 0.68, y + 0.46, zb), "desk_wood")                           # bench seat
        for zz in (za + 0.05, zb - 0.09):
            env.box((c + 0.5, y, zz), (c + 0.56, y + 0.42, zz + 0.04), "wood_dark", skip=("+y", "-y"))
            env.box((c + 0.2, y + 0.05, zz), (c + 0.5, y + 0.09, zz + 0.04), "wood_dark", skip=("-y",))
        env.col((c - 0.225, y, za), (c + 0.225, y + 0.75, zb), "props")      # desk
        env.col((c + 0.38, y, za), (c + 0.68, y + 0.46, zb), "props")         # bench (sittable)
env.marker("seat_nam", (0.4 + 0.53, FY + 0.46, -22.9), yaw=90)
env.marker("spawn_classroom", (0.4 + 0.53, FY, -21.85), yaw=90)        # aisle beside Nam's seat
env.marker("hide_desk_teacher", (-4.3, FY + 0.2, -24.5), yaw=90)
# fans + tube lights
for i, x in enumerate((-1.8, 0.6, 3.0)):
    P.ceiling_fan(env, (x, F2, -24.5), f"ceiling_fan_{i + 1}", drop=0.55)
    env.marker(f"fan_{i + 1}", (x, F2 - 0.6, -24.5))
k = 1
for x in (-2.0, 2.4):
    for z in (-22.7, -26.3):
        lp = P.tube_fixture(env, (x, F2, z), f"class_tube_{k}", length=1.2, along="x")
        env.marker(f"light_class_{k}", lp, pitch=-90)
        k += 1
# misc: trash basket, broom, poster on back wall
env.cyl((4.4, FY, -27.5), 0.17, 0.35, "plastic_blue", segs=6, r_top=0.2, caps=(True, False))
with env.at((4.75, FY, -27.7), roll=10):
    env.box((-0.02, 0, -0.02), (0.02, 1.2, 0.02), "wood_planks")
    env.box((-0.12, 0, -0.04), (0.12, 0.3, 0.04), "cork")
env.card((2.0, FY + 1.7, CZ1 + 0.01), 1.6, 0.8, "notice_paper")

# ================================================================== markers / crowd spots / cameras
env.marker("spawn_default", (0.0, 0.0, -2.5), yaw=0)
env.marker("spawn_street", (-35.0, -0.15, 6.5), yaw=-90)
crowd = [(11.2, 0, 2.2, 180), (12.4, 0, 2.5, 200), (13.1, 0, 2.1, 170), (-22.0, 0, 1.6, 150), (-8.0, -0.15, 7.5, 90),
         (3.0, 0, 11.0, 10), (-3.0, 0, -9.5, 30), (7.5, 0, -13.0, -60), (-9.8, 0, -15.5, 120), (0.5, FY, -19.6, -90)]
for i, (x, y, z, yaw) in enumerate(crowd):
    env.marker(f"crowd_{i + 1}", (x, y, z), yaw=yaw)
env.marker_look("cam_courtyard_wide", (10.6, 4.6, -1.0), (-3.0, 1.0, -17.5))
env.marker_look("cam_classroom", (-4.3, FY + 2.0, -24.5), (4.5, FY + 0.6, -24.5))
env.marker_look("cam_gate", (5.0, 2.2, 7.5), (0.0, 1.6, -2.0))
env.marker_look("cam_street_long", (-38.0, 3.0, 11.0), (10.0, 1.5, 4.0))
env.marker_look("cam_corridor", (14.0, FY + 1.9, -19.5), (-10.0, FY + 0.8, -19.6))
env.export()
