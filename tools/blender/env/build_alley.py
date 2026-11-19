"""alley.glb — the winding alley behind the store (Scene 2, level coordinates).
Path: storeroom back door (4.4, -12) -> south 16 m -> west 18 m -> south 24 m -> exit (-14, -52).
Lane 1.8-2.5 m wide between 3-4 storey tube houses; open sky; ground y = 0.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lowpoly_env as L  # noqa: E402
import props_env as P  # noqa: E402
import streetkit as S  # noqa: E402

env = L.Env("alley")
rng = random.Random(77)

# ------------------------------------------------------------------ ground
env.floor(3.0, -12.0, 5.8, -26.7, 0.0, "concrete")
env.floor(-15.3, -26.7, 5.8, -29.3, 0.0, "concrete")
env.floor(-15.3, -29.3, -12.7, -56.0, 0.0, "concrete")
env.floor(-30.0, -56.0, 2.0, -63.5, -0.05, "asphalt", col=False)
env.col((-15.3, -0.3, -56.0), (-12.7, 0.0, -54.0), "floor")
# drain gutters
env.quad((5.0, 0.004, -12.0), (0.22, 0, 0), (0, 0, -14.6), "concrete_dark", seg=4)
env.quad((-15.0, 0.004, -29.3), (0.22, 0, 0), (0, 0, -26.6), "concrete_dark", seg=4)
S.puddles(env, rng, (3.6, -13, 5.2, -26), 4)
S.puddles(env, rng, (-12.5, -27.4, 3.0, -28.6), 4)
S.puddles(env, rng, (-14.6, -30, -13.4, -52), 5)

# ------------------------------------------------------------------ walls (tube-house facades)
rows = {}
rows["A_w"] = S.alley_side(env, "+x", 3.5, -12.0, -27.1, rng)
rows["A_e"] = S.alley_side(env, "-x", 5.3, -12.0, -28.9, rng)
rows["B_n"] = S.alley_side(env, "-z", -27.1, -14.9, 3.5, rng)
rows["B_s"] = S.alley_side(env, "+z", -28.9, -13.1, 5.3, rng)
rows["C_e"] = S.alley_side(env, "-x", -13.1, -56.0, -28.9, rng)
rows["C_w"] = S.alley_side(env, "+x", -14.9, -56.0, -27.1, rng)
# back of the store building above the storeroom (seen when looking back toward the store)
env.box((0.6, 2.62, -12.35), (5.7, 10.4, -12.2), "wall_white", skip=("+z", "-y"), tint=(0.8, 0.82, 0.78), uvoff=(0.4, 0.2))
for y in (4.3, 7.4):
    env.quad((1.6, y, -12.37), (-1.0, 0, 0), (0, 1.2, 0), "window_bars", uv="fit")
    env.quad((4.4, y, -12.37), (-1.0, 0, 0), (0, 1.2, 0), "window_bars", uv="fit")
P.ac_unit(env, (2.8, 6.0, -12.35), yaw=180)
env.box((3.8, 2.3, -12.95), (5.0, 2.38, -12.2), "concrete_dark")             # little awning over back door
env.col((0.6, 0.0, -12.35), (3.0, 4.0, -12.2), "walls")

# ------------------------------------------------------------------ cross street at the exit (seen through fog)
for x0, x1 in ((-30.0, -14.9), (-13.1, 2.0)):
    xs = x0
    while xs < x1 - 0.5:
        w = min(rng.uniform(3.4, 4.6), x1 - xs)
        P.tube_house(env, (xs + w, 0, -56.0), w, yaw=180, storeys=rng.randint(3, 4), ground="shutter", rng=rng, depth=4)
        xs += w
P.shopfront_row(env, -30.0, 2.0, -63.5, 1, rng, storeys=(2, 4), depth=4.0, lit_window=True)
lamp = P.streetlight(env, (-15.2, 0, -62.6), yaw=160, name="alley_far_streetlight")
env.marker("alley_far_light", lamp, pitch=-90)
env.col((-15.3, 0, -54.6), (-12.7, 4.0, -54.4), "bounds")   # invisible: level ends at the exit

# ------------------------------------------------------------------ wall lamps every ~12 m
lamp_spots = [("A_e", "-x", 5.3, -18.0), ("B_n", "-z", -27.1, -1.0), ("B_s", "+z", -28.9, -11.0),
              ("C_w", "+x", -14.9, -40.0), ("C_e", "-x", -13.1, -50.0)]
for i, (rk, fc, line, along) in enumerate(lamp_spots):
    sb = S.setback_at(rows[rk], along)
    p = S.facade_point(fc, line, along, sb, 2.75)
    yaw = S.FACING[fc][0]
    lp = P.wall_lamp(env, p, yaw, f"alley_lamp_{i + 1}")
    env.marker(f"alley_lamp_{i + 1}", lp, pitch=-90)

# ------------------------------------------------------------------ household altar niche (bàn thờ ông Địa) in the B north wall
along = -6.5
sb = S.setback_at(rows["B_n"], along)
p = S.facade_point("-z", -27.1, along, sb, 0.0)
with env.at(p, yaw=180):
    env.box((-0.45, 0.0, 0.0), (0.45, 0.75, 0.42), "tile_red")               # plinth
    env.box((-0.42, 0.75, 0.0), (0.42, 0.8, 0.45), "lacquer_red")
    env.box((-0.42, 0.8, 0.0), (-0.38, 1.45, 0.42), "lacquer_red")
    env.box((0.38, 0.8, 0.0), (0.42, 1.45, 0.42), "lacquer_red")
    env.box((-0.48, 1.45, 0.0), (0.48, 1.52, 0.5), "roof_tiles")
    env.quad((-0.38, 0.8, 0.01), (0.76, 0, 0), (0, 0.65, 0), "altar", uv="fit")
    env.cyl((0, 0.8, 0.25), 0.08, 0.1, "terracotta", segs=6, r_top=0.1, cap_mat="incense_ash")
    env.cyl((-0.25, 0.8, 0.25), 0.04, 0.12, "lamp_bulb", segs=5)
    env.cyl((0.25, 0.8, 0.25), 0.04, 0.12, "lamp_bulb", segs=5)
    with env.obj("alley_altar_lamp_emit"):
        env.quad((-0.12, 1.25, 0.02), (0.24, 0, 0), (0, 0.12, 0), "lamp_bulb@emit", uv="fit")
    env.card((0.0, 1.62, 0.0), 0.5, 0.06, "joss_paper")
    env.col((-0.45, 0, 0), (0.45, 1.5, 0.45), "props")
    env.marker("alley_altar", (0, 0.85, 0.3), yaw=0)

# ------------------------------------------------------------------ clutter
def bike(x, z, yaw, paint="bike_paint"):
    P.motorbike(env, (x, 0, z), yaw=yaw, paint=paint)
    with env.at((x, 0, z), yaw=yaw):
        env.col((-0.33, 0, -0.95), (0.33, 1.0, 0.95), "props")


bike(4.85, -15.0, 0)
bike(4.85, -22.6, 180, "plastic_blue")
bike(-7.0, -28.45, 92)
bike(-14.45, -44.0, 3, "metal_paint")
for (x, z, s) in ((3.75, -13.2, 1.0), (3.75, -19.5, 0.8), (5.0, -27.3, 1.1), (-2.0, -27.45, 0.9), (-9.5, -28.6, 1.0),
                  (-13.45, -33.0, 0.9), (-14.55, -37.5, 1.2), (-13.45, -47.0, 1.0)):
    P.potted_plant(env, (x, 0, z), s, yaw=rng.uniform(0, 90))
# water drums, trash bags, stools
for (x, z) in ((3.8, -24.5), (-12.0, -27.5), (-13.5, -40.5)):
    env.cyl((x, 0, z), 0.28, 0.75, "plastic_blue", segs=7, cap_mat="plastic_blue")
    env.col((x - 0.28, 0, z - 0.28), (x + 0.28, 0.75, z + 0.28), "props")
for (x, z) in ((5.0, -20.0), (-4.5, -28.6), (-14.5, -49.5)):
    with env.at((x, 0, z), yaw=rng.uniform(0, 90)):
        env.box((-0.25, 0, -0.2), (0.25, 0.4, 0.2), "rubber")
        env.box((-0.15, 0.4, -0.1), (0.1, 0.48, 0.12), "rubber")
P.stool(env, (3.8, 0, -16.5))
P.stool(env, (3.85, 0, -16.9), mat="plastic_blue")
P.stool(env, (-13.4, 0, -36.0))
P.crate_stack(env, (-14.5, 0, -30.5), n=2, rng=rng)
# blue tarp awnings sagging over the lane (cramped)
env.face([(3.4, 3.2, -19.5), (5.4, 2.9, -19.5), (5.4, 2.9, -22.0), (3.4, 3.2, -22.0)][::-1], "tarp", uv="world")
env.face([(3.4, 3.2, -19.5), (5.4, 2.9, -19.5), (5.4, 2.9, -22.0), (3.4, 3.2, -22.0)], "tarp", uv="world")
env.face([(-15.0, 3.0, -41.0), (-13.0, 3.3, -41.0), (-13.0, 3.3, -43.5), (-15.0, 3.0, -43.5)][::-1], "tarp", uv="world")
env.face([(-15.0, 3.0, -41.0), (-13.0, 3.3, -41.0), (-13.0, 3.3, -43.5), (-15.0, 3.0, -43.5)], "tarp", uv="world")
# laundry poles between balconies
for (a, b, y) in (((3.5, -16.0), (5.3, -16.6), 3.6), ((-8.0, -27.1), (-8.4, -28.9), 3.5), ((-14.9, -46.0), (-13.1, -46.4), 3.4)):
    env.strip(a, b, y - 0.04, y, "metal_alu", uv="fit")
    env.strip(a, b, y - 0.55, y - 0.05, "fabric", uv="fit", rect=(0, 0, 4, 1.5))

# ------------------------------------------------------------------ overhead cables
def cross(fc_a, line_a, fc_b, line_b, rk_a, rk_b, along, axis):
    if axis == "z":
        pa, pb = (line_a, along), (line_b, along + rng.uniform(-1.5, 1.5))
    else:
        pa, pb = (along, line_a), (along + rng.uniform(-1.5, 1.5), line_b)
    P.cables_between(env, pa, pb, rng.uniform(3.8, 7.0), n=rng.randint(2, 4), sag=rng.uniform(0.2, 0.6), rng=rng)


z = -13.5
while z > -28:
    cross("+x", 3.4, "-x", 5.4, "A_w", "A_e", z, "z")
    z -= rng.uniform(2.0, 3.5)
x = 3.0
while x > -14.5:
    cross("-z", -27.0, "+z", -29.0, "B_n", "B_s", x, "x")
    x -= rng.uniform(2.0, 3.5)
z = -29.5
while z > -55:
    cross("+x", -15.0, "-x", -13.0, "C_w", "C_e", z, "z")
    z -= rng.uniform(2.0, 3.5)
# bundles running along the walls
P.cables_between(env, (3.42, -12.0), (3.42, -27.0), 4.2, n=3, sag=0.4, rng=rng, spread=0.15)
P.cables_between(env, (3.5, -27.05), (-14.9, -27.05), 4.6, n=3, sag=0.5, rng=rng, spread=0.15)
P.cables_between(env, (-13.15, -29.0), (-13.15, -55.0), 4.4, n=3, sag=0.5, rng=rng, spread=0.15)

# ------------------------------------------------------------------ markers
env.marker("spawn_alley_start", (4.4, 0, -12.8), yaw=0)
for i, p in enumerate([(4.4, 0, -12.5), (4.4, 0, -28.0), (-14.0, 0, -28.0), (-14.0, 0, -52.0)]):
    env.marker(f"alley_path_{i + 1}", p)
env.marker("alley_exit", (-14.0, 0, -52.5), yaw=0)
env.marker_look("cam_alley", (5.0, 2.3, -13.0), (4.2, 1.0, -26.0))
env.marker_look("cam_alley_corner", (4.6, 1.7, -28.4), (-12.0, 1.4, -27.9))
env.marker_look("cam_alley_exit", (-14.2, 1.6, -30.0), (-14.0, 2.0, -58.0))
env.export()
