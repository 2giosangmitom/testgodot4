"""dorm.glb — lane entrance + "Nhà trọ" (Scene 3, level coordinates).
Lane x -1..1 from z +3 to -15 (continues in shrine.glb). Dorm on the left of the lane:
x -1..-7.8, z -14..-31.6, 3 storeys of 3.2 m. Ground: gate hall + stair (0.9 m) at z -14.2..-15.1.
Floor 2 (y 3.2): open corridor x -1..-2.5 along the lane, rooms P.201..P.205 (3 x 5 m) to the west.
Only P.204 (z -25.1..-28.1) is built inside: loft at +1.9 m, WC, kitchen corner, desk.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lowpoly_env as L  # noqa: E402
import props_env as P  # noqa: E402
import streetkit as S  # noqa: E402

env = L.Env("dorm")
rng = random.Random(204)
SH = 3.2                 # storey height
F2 = SH                  # floor 2 level
F3 = 2 * SH
ROOF = 3 * SH
XF = -1.0                # lane-side face of the dorm
XC = -2.5                # corridor / room-front wall centre
XB = -7.7                # back wall centre
ZN, ZS = -14.0, -31.6    # dorm north / south ends

# ================================================================== lane (z +3 .. -15) + entrance stub
env.floor(-1.4, 3.0, 1.4, -15.0, 0.0, "concrete")
S.puddles(env, rng, (-0.8, 2.0, 0.8, -14.0), 4)
env.quad((0.75, 0.004, 3.0), (0.2, 0, 0), (0, 0, -18.0), "concrete_dark", seg=4)
rows_w = S.alley_side(env, "+x", -1.0, -14.0, 3.0, rng, jitter=0.3)
rows_e = S.alley_side(env, "-x", 1.0, -15.0, 3.0, rng, jitter=0.3)
P.shopfront_row(env, -6.0, 6.0, 9.0, -1, rng, storeys=(2, 3), depth=4.0, lit_window=True)
env.floor(-6.0, 3.0, 6.0, 9.0, -0.05, "asphalt", col=False)
env.col((-1.5, 0, 2.6), (1.5, 4.0, 2.8), "bounds")
lp = P.wall_lamp(env, S.facade_point("-x", 1.0, -6.0, S.setback_at(rows_e, -6.0), 2.7), -90, "lane_lamp_1")
env.marker("lane_lamp_1", lp, pitch=-90)
z = 2.0
while z > -15.0:
    P.cables_between(env, (-1.1, z), (1.1, z + rng.uniform(-1.5, 1.5)), rng.uniform(4.0, 6.5), n=rng.randint(2, 3), sag=0.4, rng=rng)
    z -= rng.uniform(2.0, 3.5)
P.cables_between(env, (-1.05, 3.0), (-1.05, -14.0), 4.3, n=3, sag=0.4, rng=rng, spread=0.15)
P.potted_plant(env, (0.7, 0, -3.5), 1.0)
P.potted_plant(env, (-0.7, 0, -9.0), 0.9)
P.motorbike(env, (0.62, 0, -11.0), yaw=180, paint="plastic_blue")
env.col((0.3, 0, -12.0), (1.1, 1.0, -10.0), "props")
env.marker("spawn_default", (0.0, 0.0, -1.0), yaw=0)

# ================================================================== dorm exterior shell
GATE = (-14.6, -16.6)
# ground-floor front wall along the lane (gate opening), y 0..3.0
env.wall("z", XF - 0.1, ZN, ZS, 0, F2 - 0.2, "wall_blue", t=0.2, openings=[(GATE[1], GATE[0], 0, 2.25, "door")],
         tint=(0.85, 0.85, 0.85))
env.marker("door_gate_l", (XF - 0.1, 0, GATE[0]), yaw=90)
env.marker("door_gate_r", (XF - 0.1, 0, GATE[1]), yaw=-90)
env.box((XF - 0.05, 2.35, GATE[0] + 0.2), (XF + 0.05, 3.0, GATE[1] - 0.2), "metal_dark", mats={"+x": "sign_dorm"},
        rects={"+x": (0, 0, 1, 1)})
for zz in (-20.0, -23.5, -27.0, -30.2):
    env.quad((XF + 0.01, 1.0, zz), (0, 0, -1.0), (0, 1.1, 0), "window_bars", uv="fit")
env.card((XF + 0.02, 1.4, -18.2), 0.35, 0.5, "poster_rent", yaw=90)
env.card((XF + 0.02, 1.5, -21.5), 0.35, 0.5, "poster_lost", yaw=90)
# electric meter cluster on the front wall
env.box((XF, 1.6, -17.0), (XF + 0.12, 2.3, -18.0), "metal_alu", mats={"+x": "ac_unit"}, rects={"+x": (0, 0, 1, 1)})
P.cables_between(env, (XF + 0.12, -17.5), (1.0, -13.0), 2.6, n=4, sag=0.3, rng=rng, spread=0.2)
# end walls / back wall
env.wall("x", ZN - 0.1, XB - 0.1, XF, 0, ROOF + 0.8, "wall_blue", t=0.2, tint=(0.75, 0.78, 0.8))
env.wall("x", ZS - 0.1, XB - 0.1, XF, 0, ROOF + 0.8, "wall_blue", t=0.2, tint=(0.75, 0.78, 0.8))
env.wall("z", XB, ZN - 0.1, ZS - 0.1, 0, ROOF + 0.8, "wall_blue", t=0.2, tint=(0.7, 0.72, 0.75), col=False)
env.col((XB - 0.1, 0, ZS), (XB + 0.1, ROOF, ZN), "walls")

# ================================================================== ground floor: gate hall (z -14.2..-20.9)
HZ0, HZ1 = -14.2, -21.0
env.floor(XB + 0.1, HZ0, XF - 0.2, HZ1, 0.0, "tile_red")
env.floor(XF - 0.2, GATE[0], XF, GATE[1], 0.0, "concrete_dark", cat="floor")
env.wall("x", HZ1 - 0.1, XB, XF - 0.2, 0, F2 - 0.2, "wall_white", t=0.2, tint=(0.8, 0.8, 0.75))
# hall ceiling with stairwell opening (x -2.6..-7.6, z -14.2..-15.2)
env.ceiling(XB + 0.1, -15.2, XF - 0.2, HZ1 + 0.1, F2 - 0.2, "wall_white", tint=(0.7, 0.7, 0.68))
env.ceiling(-2.6, HZ0, XF - 0.2, -15.2, F2 - 0.2, "wall_white", tint=(0.7, 0.7, 0.68))
# straight stair along the north wall, 18 risers, bottom at x -7.1, top at x -2.6
NST = 18
rise = F2 / NST
run = 4.5 / NST
SZ0, SZ1 = -14.2, -15.1
for i in range(NST):
    x0 = -7.1 + i * run
    y1 = (i + 1) * rise
    env.box((x0, y1 - 0.06, SZ1), (x0 + run, y1, SZ0), "concrete", skip=("+z",), tint=(0.85, 0.85, 0.82))
    env.box((x0, y1 - 0.06 - rise, SZ1), (x0 + 0.04, y1 - 0.06, SZ0), "concrete", skip=("+z", "-y", "+y"), tint=(0.7, 0.7, 0.7))
# stringer under the stair
env.face([(-7.1, 0.0, SZ1), (-2.6, F2 - 0.06, SZ1), (-2.6, F2 - 0.35, SZ1), (-6.7, 0.0, SZ1)], "concrete")
env.face([(-6.7, 0.0, SZ1), (-2.6, F2 - 0.35, SZ1), (-2.6, F2 - 0.35, SZ0), (-6.7, 0.0, SZ0)], "concrete_dark")
env.col_ramp((-7.25, 0.0, (SZ0 + SZ1) / 2), (-2.5, F2, (SZ0 + SZ1) / 2), 0.9, cat="stairs")
env.col((-7.1, 0, SZ1), (-5.6, 1.0, SZ0), "props")
# stair handrail (sloped cutout railing) + its collision
env.face([(-7.1, 0.05, SZ1 - 0.03), (-2.6, F2 + 0.05, SZ1 - 0.03), (-2.6, F2 + 0.95, SZ1 - 0.03), (-7.1, 0.95, SZ1 - 0.03)],
         "railing@cut", uvs=[(0, 0), (4.5, 0), (4.5, 1), (0, 1)])
env.col_ramp((-7.25, 1.0, SZ1 - 0.05), (-2.5, F2 + 1.0, SZ1 - 0.05), 0.06, thick=1.0, cat="railing")
# parking under the stair + in the hall
P.motorbike(env, (-3.6, 0, -14.65), yaw=-90, paint="bike_paint", lean=3)
P.motorbike(env, (-4.6, 0, -18.1), yaw=-90, paint="plastic_blue")
P.motorbike(env, (-4.4, 0, -19.9), yaw=-90, paint="metal_paint")
env.col((-4.6, 0, -15.05), (-2.6, 1.0, -14.25), "props")
env.col((-5.6, 0, -20.5), (-3.4, 1.0, -17.6), "props")
# notice board, mailbox, water meters, shoe rack
env.box((XB + 0.1, 1.1, -18.4), (XB + 0.16, 2.0, -16.9), "wood_dark", mats={"+x": "cork"})
env.card((XB + 0.17, 1.55, -17.25), 0.4, 0.4, "notice_paper", yaw=90)
env.card((XB + 0.17, 1.6, -17.85), 0.3, 0.42, "poster_lost", yaw=90)
env.marker("notice_board", (XB + 0.2, 1.55, -17.65), yaw=-90)
env.box((-3.4, 1.1, HZ1 + 0.1), (-2.3, 1.7, HZ1 + 0.3), "metal_alu", mats={"+z": "shelf_metal"})
env.marker("mailbox", (-2.85, 1.4, HZ1 + 0.32), yaw=180)
for k in range(3):
    env.box((XF - 0.32, 0.4 + k * 0.3, -17.0 - 0.3 * k), (XF - 0.2, 0.6 + k * 0.3, -17.25 - 0.3 * k), "metal_dark")
env.marker("water_meter", (XF - 0.33, 0.7, -17.3), yaw=90)
env.box((-7.5, 0, -20.85), (-6.3, 0.8, -20.5), "metal_alu", mats={"+z": "rack_goods"}, rects={"+z": (0, 0, 2, 1)})
env.col((-7.5, 0, -20.85), (-6.3, 0.8, -20.5), "props")
lp = P.bulb(env, (-4.5, F2 - 0.2, -17.5), "hall_bulb", wire=0.25)
env.marker("light_hall", lp, pitch=-90)

# ================================================================== floor 2: corridor + room fronts
env.box((XB, F2 - 0.2, ZS), (XF + 0.02, F2, ZN), "concrete", skip=("+y", "-y", "+z", "-z", "-x"), tint=(0.8, 0.8, 0.78))
# floor 2 walkable: landing over the hall (z -14.2..-15.4) + corridor x -1..-2.4
env.floor(-2.6, HZ0, XF, -15.4, F2, "tile_red", cat="floor")
env.floor(-2.4, -15.4, XF, ZS, F2, "tile_red", cat="floor")
env.col((-7.6, F2 - 0.3, -15.2), (-2.6, F2, HZ1), "floor")            # under-room slab (hall ceiling)
env.ceiling(-2.6, HZ0, XF, ZS, F3 - 0.2, "wall_white", tint=(0.65, 0.65, 0.62))
# landing guard rail around the stairwell top (z -15.2 side handled by room wall above)
P.fence_railing(env, (XF, HZ0 + 0.05), (XF, ZS + 0.05), F2, 1.0, col=False, post=False)
env.box((XF - 0.06, F2 + 1.0, ZS), (XF + 0.04, F2 + 1.05, ZN), "metal_paint")
env.box((XF - 0.08, F2, ZS), (XF + 0.04, F2 + 0.12, ZN), "concrete_dark")
for zz in range(-15, -32, -3):
    env.box((XF - 0.07, F2, zz - 0.03), (XF - 0.01, F2 + 1.0, zz + 0.03), "metal_paint")
env.col((XF - 0.1, F2, ZS), (XF + 0.05, F2 + 1.1, ZN), "railing")
# room walls: north wall of P.201 over the stairwell, corridor wall with doors/windows
ROOM_Z = [-15.4 - 3.2 * k for k in range(6)]          # partition wall centres
doors = {}
ops = []
for k in range(5):
    za = ROOM_Z[k] - 0.1                               # interior north edge of room k
    d0, d1 = za - 0.3, za - 1.2                        # door opening (z), hinge at d0
    w0, w1 = za - 1.6, za - 2.7
    ops.append((d1, d0, F2, F2 + 2.1, "door"))
    ops.append((w1, w0, F2 + 0.9, F2 + 2.1, "window"))
    doors[201 + k] = (d0, d1, w0, w1, za)
env.wall("z", XC, ROOM_Z[0] + 0.1, ROOM_Z[5] - 0.1, F2, F3 - 0.2, "wall_green", t=0.2, openings=ops, tint=(0.9, 0.95, 0.9))
env.wall("x", ROOM_Z[0], XB, XC - 0.1, F2, F3 - 0.2, "wall_green", t=0.2, tint=(0.85, 0.85, 0.85))
for num, (d0, d1, w0, w1, za) in doors.items():
    env.marker(f"door_{num}", (XC, F2, d0), yaw=90)
    # window: bars + frame (all rooms); dark curtain backing for the closed rooms
    env.quad((XC + 0.0, F2 + 0.9, w0), (0, 0, w1 - w0), (0, 1.2, 0), "iron_gate@cut", uv="fit", rect=(0, 0, 1, 1.2))
    env.box((XC - 0.1, F2 + 0.86, w1), (XC + 0.16, F2 + 0.9, w0), "wood_dark")
    if num != 204:
        env.quad((XC - 0.08, F2 + 0.9, w0), (0, 0, w1 - w0), (0, 1.2, 0), "fabric" if num != 205 else "concrete_dark",
                 uv="fit", tint=(0.45, 0.42, 0.4))
        # shallow closet behind the doorway so an open door never shows void
        env.box((XC - 0.45, F2, d1), (XC - 0.1, F2 + 2.1, d0), "concrete_dark", skip=("+x", "-y"), tint=(0.3, 0.3, 0.3))
        env.col((XC - 0.45, F2, d1), (XC - 0.1, F2 + 2.1, d0), "walls")
    # number plate placeholder above each door on the corridor wall
    env.marker(f"plate_{num}", (XC + 0.11, F2 + 2.25, (d0 + d1) / 2), yaw=-90)
# P.203: TV glow leaking under the door; P.205 padlocked
d0, d1, *_ = doors[203]
with env.obj("p203_tvglow_emit"):
    env.quad((XC + 0.1, F2 + 0.004, d0 - 0.05), (0.22, 0, 0), (0, 0, -(d0 - d1) + 0.1), "tv_glow@emit", uv="fit")
env.marker("p203_tv", (XC - 1.5, F2 + 0.6, (d0 + d1) / 2))
d0, d1, *_ = doors[205]
env.marker("padlock_205", (XC + 0.12, F2 + 1.15, d1 + 0.07), yaw=-90)
# corridor bulbs (one per two doors)
for i, zz in enumerate((ROOM_Z[1], ROOM_Z[3], ROOM_Z[5] + 0.5)):
    lp = P.bulb(env, (-1.75, F3 - 0.2, zz), f"corridor_bulb_{i + 1}", wire=0.3)
    env.marker(f"corridor_bulb_{i + 1}", lp, pitch=-90)
# clutter in the corridor: shoes, plants, a drying rack, plastic basin
for num, (d0, d1, w0, w1, za) in doors.items():
    env.box((XC + 0.15, F2, d0 - 0.1), (XC + 0.45, F2 + 0.08, d0 - 0.4), "rubber")
P.potted_plant(env, (-1.3, F2, -16.0), 0.8)
P.potted_plant(env, (-1.3, F2, -30.9), 1.0)
env.cyl((-1.4, F2, -23.6), 0.3, 0.15, "plastic_red", segs=7, r_top=0.35, caps=(True, False))
with env.at((-1.45, F2, -29.2)):
    for zz in (-0.4, 0.4):
        env.box((-0.02, 0, zz - 0.02), (0.02, 1.4, zz + 0.02), "metal_alu")
    env.box((-0.02, 1.35, -0.4), (0.02, 1.4, 0.4), "metal_alu")
    env.strip((0, -0.38), (0, 0.38), 0.75, 1.35, "fabric", uv="fit", rect=(0, 0, 1, 1))
    env.strip((0, 0.38), (0, -0.38), 0.75, 1.35, "fabric", uv="fit", rect=(0, 0, 1, 1))
env.col((-1.7, F2, -29.7), (-1.15, F2 + 1.4, -28.7), "props")

# ================================================================== P.204 interior
d0, d1, w0, w1, za = doors[204]
RZ0, RZ1 = za, za - 3.0                 # interior z range -25.1 .. -28.1
RX0, RX1 = XC - 0.1, XB + 0.1           # interior x range -2.6 .. -7.6
LOFT = F2 + 1.9
env.floor(RX1, RZ0, RX0, RZ1, F2, "tile_pattern", cat="floor")
env.floor(XC - 0.1, d0, XC + 0.1, d1, F2, "concrete_dark", cat="floor")
env.ceiling(RX1, RZ0, RX0, RZ1, F3 - 0.2, "wall_white", tint=(0.85, 0.85, 0.8))
env.wall("x", ROOM_Z[3], XB, XC - 0.1, F2, F3 - 0.2, "wall_white", t=0.2, tint=(0.95, 0.93, 0.85))
env.wall("x", ROOM_Z[4], XB, XC - 0.1, F2, F3 - 0.2, "wall_white", t=0.2, tint=(0.95, 0.93, 0.85))
env.quad((RX1 + 0.005, F2, RZ0), (0, 0, RZ1 - RZ0), (0, 1.0, 0), "wall_blue", tint=(0.6, 0.65, 0.7))   # back wall dado
# loft (gác xép) over the back half
LX = -5.1
env.box((RX1, LOFT - 0.12, RZ1), (LX, LOFT, RZ0), "wood_planks", tint=(0.85, 0.8, 0.75))
env.col((RX1, LOFT - 0.12, RZ1), (LX, LOFT, RZ0), "floor")
LAD0, LAD1 = -26.6, -27.1               # ladder gap in the loft rail
for za_, zb_ in ((RZ1, LAD1), (LAD0, RZ0)):
    env.box((LX - 0.05, LOFT, za_), (LX, LOFT + 0.5, zb_), "wood_dark", skip=("-y",))
    env.col((LX - 0.05, LOFT, za_), (LX + 0.02, LOFT + 0.6, zb_), "railing")
for zz in (RZ0 + 0.05, RZ1 - 0.05, -26.0, -27.6):  # posts under the loft edge
    env.box((LX - 0.05, F2, zz - 0.05), (LX + 0.05, LOFT - 0.12, zz + 0.05), "wood_dark", skip=("+y", "-y"))
# ladder: two rails + rungs, leaning from floor (x -4.55) to the loft edge (x -5.1)
with env.at((-4.55, F2, (LAD0 + LAD1) / 2), roll=-15):
    for zz in (-0.22, 0.18):
        env.box((-0.03, 0, zz), (0.03, 2.25, zz + 0.04), "wood_planks")
    for k in range(6):
        env.box((-0.02, 0.3 + k * 0.33, -0.2), (0.02, 0.34 + k * 0.33, 0.2), "wood_planks")
env.col((-4.9, F2, LAD1), (-4.45, F2 + 1.6, LAD0), "props")
env.marker("ladder_bottom", (-4.25, F2, (LAD0 + LAD1) / 2), yaw=90)
env.marker("loft", (-6.4, LOFT, -26.3), yaw=-90)
# loft furniture: mattress, pillow, low desk, clothes
env.box((-7.45, LOFT, -27.0), (-5.45, LOFT + 0.14, -25.3), "fabric")
env.box((-7.4, LOFT + 0.14, -25.9), (-6.9, LOFT + 0.24, -25.4), "wall_white")
env.box((-7.5, LOFT, -28.0), (-6.8, LOFT + 0.32, -27.3), "desk_wood")
env.box((-7.3, LOFT + 0.32, -27.85), (-6.95, LOFT + 0.34, -27.5), "screen")
env.col((-7.5, LOFT, -28.0), (-6.8, LOFT + 0.32, -27.3), "props")
# WC (back-left, under the loft): x -6.4..-7.6, z -25.1..-26.6
WX, WZ = -6.4, -26.6
env.wall("z", WX + 0.05, RZ0, WZ - 0.05, F2, LOFT - 0.12, "tile_bath", t=0.1, openings=[(-26.05, -25.3, F2, F2 + 1.75, "door")])
env.wall("x", WZ, RX1, WX + 0.1, F2, LOFT - 0.12, "tile_bath", t=0.1)
env.quad((RX1 + 0.005, F2, RZ0), (0, 0, WZ - RZ0), (0, LOFT - 0.12 - F2, 0), "tile_bath")
env.box((-7.35, F2, -25.95), (-6.85, F2 + 0.1, -25.35), "tile_bath")                     # squat toilet
env.quad((-7.25, F2 + 0.101, -25.5), (0.3, 0, 0), (0, 0, -0.3), "puddle", uv="fit")
env.cyl((-6.75, F2, -26.3), 0.17, 0.32, "plastic_blue", segs=6, r_top=0.2, caps=(True, False))
env.cyl((-6.75, F2 + 0.25, -26.3), 0.19, 0.0, "puddle", segs=6, caps=(False, True))
with env.obj("wc_mirror"):
    env.quad((RX1 + 0.02, F2 + 1.2, -25.55), (0, 0, -0.4), (0, 0.5, 0), "mirror", uv="fit")
env.marker("mirror", (RX1 + 0.03, F2 + 1.45, -25.75), yaw=-90)
lp = P.bulb(env, (-7.0, LOFT - 0.12, -25.8), "wc_bulb", wire=0.08, shade=False)
env.marker("light_wc", lp, pitch=-90)
# kitchen corner: low shelf + gas stove + pot, mini fridge
env.box((-7.6, F2, -28.05), (-7.05, F2 + 0.6, -26.85), "wood_dark", mats={"+y": "metal_alu"})
env.box((-7.5, F2 + 0.6, -27.9), (-7.15, F2 + 0.7, -27.25), "metal_dark")
env.cyl((-7.32, F2 + 0.7, -27.42), 0.13, 0.14, "metal_alu", segs=7)
env.cyl((-7.32, F2 + 0.6, -27.05), 0.1, 0.25, "plastic_red", segs=6)                     # gas bottle
env.col((-7.6, F2, -28.05), (-7.05, F2 + 0.7, -26.85), "props")
env.marker("stove", (-7.32, F2 + 0.71, -27.75), yaw=-90)
env.box((-5.95, F2, -28.05), (-5.4, F2 + 0.85, -27.5), "metal_alu", mats={"+x": "wall_white"})
env.col((-5.95, F2, -28.05), (-5.4, F2 + 0.85, -27.5), "props")
env.marker("mini_fridge", (-5.35, F2 + 0.5, -27.77), yaw=-90)
# desk under the window with laptop, stool, wardrobe, standing fan
env.box((-3.2, F2 + 0.72, w1 - 0.05), (-2.62, F2 + 0.76, w0 + 0.05), "desk_wood")
for zz in (w1 - 0.05, w0 + 0.02):
    env.box((-3.2, F2, zz), (-2.62, F2 + 0.72, zz + 0.03), "desk_wood", skip=("+y", "-y"))
env.box((-3.05, F2 + 0.76, -27.55), (-2.76, F2 + 0.78, -27.1), "metal_dark")
env.box((-2.78, F2 + 0.78, -27.55), (-2.75, F2 + 1.0, -27.1), "metal_dark", skip=("-x",))
with env.obj("laptop_screen_emit"):
    env.quad((-2.781, F2 + 0.79, -27.12), (0, 0, -0.41), (0, 0.2, 0), "screen@emit", uv="fit")
env.col((-3.2, F2 + 0.6, w1 - 0.05), (-2.62, F2 + 0.76, w0 + 0.05), "props")
env.marker("hide_desk", (-2.95, F2, -27.25), yaw=-90)
env.marker("laptop", (-2.9, F2 + 0.8, -27.3), yaw=-90)
P.stool(env, (-3.5, F2, -27.2), mat="plastic_red", h=0.45)
env.box((-4.95, F2, RZ0 - 0.55), (-4.0, F2 + 1.65, RZ0 - 0.02), "tarp", mats={"+z": "fabric", "-z": "fabric"},
        rects={"+z": (0, 0, 1, 1.5), "-z": (0, 0, 1, 1.5)})
env.col((-4.95, F2, RZ0 - 0.55), (-4.0, F2 + 1.65, RZ0 - 0.02), "props")
with env.at((-4.2, F2, -27.75)):
    env.cyl((0, 0, 0), 0.18, 0.04, "plastic_blue", segs=6)
    env.box((-0.015, 0.04, -0.015), (0.015, 1.15, 0.015), "metal_alu")
    with env.at((0, 1.2, 0), yaw=40, pitch=90):
        env.cyl((0, -0.06, 0), 0.2, 0.1, "railing@cut", segs=8)
env.card((-4.4, F2 + 1.6, RZ1 + 0.01), 0.5, 0.7, "poster_rent", tint=(0.9, 0.9, 0.9))
env.card((-3.4, F2 + 1.4, RZ0 - 0.01), 0.4, 0.4, "clock_face", yaw=180)
# light switch + ceiling bulb
env.box((XC - 0.12, F2 + 1.3, -26.5), (XC - 0.1, F2 + 1.4, -26.42), "wall_white")
env.marker("switch_room", (XC - 0.13, F2 + 1.35, -26.46), yaw=90)
lp = P.bulb(env, (-3.8, F3 - 0.2, -26.6), "room_bulb", wire=0.2, shade=False)
env.marker("light_room", lp, pitch=-90)
lp = P.bulb(env, (-6.4, F3 - 0.2, -27.6), "loft_bulb", wire=0.05, shade=False)
env.marker("light_loft", lp, pitch=-90)

# ================================================================== floor 3 (exterior only) + roof
env.box((XB, F3 - 0.2, ZS), (XF + 0.02, F3, ZN), "concrete", skip=("+y", "-y", "+z", "-z", "-x"), tint=(0.8, 0.8, 0.78))
env.quad((-2.6, F3, ZN), (XF + 2.6, 0, 0), (0, 0, ZS - ZN), "tile_red", seg=4)
env.quad((XC + 0.1, F3, ZN), (0, 0, ZS - ZN), (0, SH, 0), "wall_green", seg=3.2, tint=(0.85, 0.9, 0.85))
for k in range(5):
    za = ROOM_Z[k] - 0.1
    env.quad((XC + 0.11, F3, za - 0.3), (0, 0, -0.9), (0, 2.1, 0), "door_dorm", uv="fit")
    env.quad((XC + 0.11, F3 + 0.9, za - 1.6), (0, 0, -1.1), (0, 1.2, 0), "window_bars", uv="fit")
P.fence_railing(env, (XF, ZN), (XF, ZS), F3, 1.0, col=False, post=False)
env.box((XF - 0.06, F3 + 1.0, ZS), (XF + 0.04, F3 + 1.05, ZN), "metal_paint")
env.box((XF - 0.08, F3, ZS), (XF + 0.04, F3 + 0.12, ZN), "concrete_dark")
env.ceiling(-2.6, ZN, XF, ZS, ROOF, "wall_white", tint=(0.6, 0.6, 0.58))
env.box((XB, ROOF, ZS), (XF + 0.02, ROOF + 0.25, ZN), "concrete", skip=("-y",), tint=(0.75, 0.75, 0.72))
env.box((XF - 0.15, ROOF + 0.25, ZS), (XF + 0.02, ROOF + 0.8, ZN), "wall_blue", tint=(0.7, 0.72, 0.75))
P.water_tank(env, (-5.0, ROOF + 0.25, -20.0))
# laundry on the floor-3 railing
env.strip((XF - 0.05, -17.0), (XF - 0.05, -21.0), F3 + 0.3, F3 + 1.0, "fabric", uv="fit", rect=(0, 0, 4, 1))
env.strip((XF - 0.05, -21.0), (XF - 0.05, -17.0), F3 + 0.3, F3 + 1.0, "fabric", uv="fit", rect=(0, 0, 4, 1))

# ================================================================== cameras
env.marker_look("cam_corridor", (-1.5, F2 + 1.9, -30.9), (-1.8, F2 + 0.9, -15.0))
env.marker_look("cam_room", (-2.9, F2 + 2.6, -25.3), (-6.5, F2 + 0.6, -27.6))
env.marker_look("cam_dorm_gate", (0.6, 1.6, -11.5), (-2.5, 1.5, -15.8))
env.marker_look("cam_lane", (0.0, 1.7, 2.0), (0.0, 1.5, -20.0))
env.export()
