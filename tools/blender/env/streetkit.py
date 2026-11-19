"""Street / alley building blocks shared by the level builders (Godot coords)."""
import math
import random

import props_env as P


def street(env, x0, x1, z_walk0, z_road0, z_road1, z_walk1, road_y=-0.15, line=True, tag="street"):
    """Sidewalk (y 0) from z_walk0..z_road0, road (y road_y) z_road0..z_road1 (centre dashed line),
    far sidewalk z_road1..z_walk1. Curbs get collision ramps so the capsule walks up them."""
    env.floor(x0, z_walk0, x1, z_road0, 0.0, "sidewalk", cat="floor")
    env.floor(x0, z_road1, x1, z_walk1, 0.0, "sidewalk", cat="floor")
    zc = (z_road0 + z_road1) / 2
    if line:
        env.floor(x0, z_road0, x1, zc - 1, road_y, "asphalt", cat="floor")
        L = x1 - x0
        env.quad((x0, road_y, zc + 1), (L, 0, 0), (0, 0, -2), "asphalt_line", uv="fit", rect=(0, 0, L / 2, 1), seg=2.5)
        env.col((x0, road_y - 0.3, zc - 1), (x1, road_y, zc + 1), "floor")
        env.floor(x0, zc + 1, x1, z_road1, road_y, "asphalt", cat="floor")
    else:
        env.floor(x0, z_road0, x1, z_road1, road_y, "asphalt", cat="floor")
    # curb faces
    lo, hi = sorted((z_road0, z_road1))
    env.quad((x0, road_y, lo), (x1 - x0, 0, 0), (0, -road_y, 0), "concrete")                 # faces +z at lo
    env.quad((x1, road_y, hi), (-(x1 - x0), 0, 0), (0, -road_y, 0), "concrete")              # faces -z at hi
    xm = (x0 + x1) / 2
    env.col_ramp((xm, road_y, lo + 0.45), (xm, 0.0, lo - 0.02), x1 - x0, cat="curb")
    env.col_ramp((xm, road_y, hi - 0.45), (xm, 0.0, hi + 0.02), x1 - x0, cat="curb")


def puddles(env, rng, area, n, y=0.006):
    x0, z0, x1, z1 = area
    for _ in range(n):
        w, d = rng.uniform(0.4, 1.4), rng.uniform(0.3, 0.9)
        x, z = rng.uniform(x0 + w / 2, x1 - w / 2), rng.uniform(min(z0, z1) + d / 2, max(z0, z1) - d / 2)
        env.quad((x - w / 2, y, z + d / 2), (w, 0, 0), (0, 0, -d), "puddle", uv="fit")


# ------------------------------------------------------------------ alley walls
FACING = {
    # facing: (yaw, axis of the run, sign mapping local +x to world run axis)
    "+x": (90.0, "z", -1),
    "-x": (-90.0, "z", +1),
    "+z": (0.0, "x", +1),
    "-z": (180.0, "x", -1),
}


def alley_side(env, facing, line, a0, a1, rng, storeys=(3, 4), jitter=0.35, widths=(2.8, 4.6),
               grounds=("door", "door", "window", "shutter", "gate", "wall"), depth=4.0, lamps=None,
               details=True, door_texs=("door_dorm", "door_wood")):
    """Row of tube-house facades lining an alley. `line` = facade coordinate closest to the alley
    centre (x for +x/-x facing, z for +z/-z); houses are pushed back 0..jitter (widening the lane).
    Run covers world coords a0..a1 along the other axis. Returns list of (start, end, setback, H)."""
    yaw, axis, sgn = FACING[facing]
    lo, hi = min(a0, a1), max(a0, a1)
    a = lo
    out = []
    back = {"+x": -1, "-x": 1, "+z": -1, "-z": 1}[facing]  # direction away from alley
    while a < hi - 0.3:
        w = min(rng.uniform(*widths), hi - a)
        if hi - (a + w) < 1.5:
            w = hi - a
        j = rng.uniform(0, jitter)
        c = line + back * j
        # origin such that local x 0..w covers [a, a+w]
        start = a if sgn > 0 else a + w
        pos = (c, 0, start) if axis == "z" else (start, 0, c)
        g = rng.choice(grounds)
        H = P.tube_house(env, pos, w, yaw=yaw, storeys=rng.randint(*storeys), ground=g, rng=rng,
                         depth=depth, balcony=rng.random() < 0.35, ac=rng.random() < 0.7,
                         door_tex=rng.choice(door_texs), storey_h=3.1)
        out.append((a, a + w, j, H))
        a += w
    return out


def facade_point(facing, line, along, setback, y, out=0.0):
    """World point on a facade at run coordinate `along`, height y, pushed `out` into the alley."""
    back = {"+x": -1, "-x": 1, "+z": -1, "-z": 1}[facing]
    c = line + back * setback - back * out
    _, axis, _ = FACING[facing]
    return (c, y, along) if axis == "z" else (along, y, c)


def setback_at(rows, along):
    for s, e, j, H in rows:
        if s - 1e-6 <= along <= e + 1e-6:
            return j
    return 0.0


def overhead_cables(env, rng, pts_a, pts_b, y_range=(4.0, 7.5), n_each=3):
    for pa, pb in zip(pts_a, pts_b):
        P.cables_between(env, pa, pb, rng.uniform(*y_range), n=n_each, sag=rng.uniform(0.3, 0.8), rng=rng)
