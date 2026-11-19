"""Build one standalone piece glb:  blender -b --factory-startup -P build_pieces.py -- <piece>
(the per-piece scripts build_<piece>.py are thin wrappers around this).

Pieces (all origin-centred, Godot axes, front/forward = -Z unless noted):
  door_wood        classroom/dorm panel door 0.9x2.1, hinge at origin, leaf spans x 0..0.9, front = +Z
  door_dorm        old blue-painted dorm door + `number_plate` placeholder (+Z side) + hasp
  door_glass_shop  aluminium frame + `door_glass` pane, hinge at origin
  gate_iron        swing iron gate leaf 1.0x2.0, hinge at origin, x 0..1.0
  streetlight      sodium streetlight, pole base at origin, arm toward -Z, `streetlight_lamp_emit`
  motorbike_parked step-through scooter on side stand, front -Z
  cables_cluster   sagging cable tangle spanning x -4..+4 at y 0 (alpha cutout)
  potted_plant     terracotta pot + leaves
  plastic_stool    low red plastic stool
  banyan_tree      giant banyan with aerial roots, trunk at origin
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lowpoly_env as L  # noqa: E402
import props_env as P  # noqa: E402
import _pieces  # noqa: E402


def door_wood():
    env = L.Env("door_wood")
    _pieces.door_panel(env, "door_wood")
    env.marker("handle", (0.82, 1.0, 0.0))
    return env


def door_dorm():
    env = L.Env("door_dorm")
    _pieces.door_panel(env, "door_dorm", t=0.04)
    with env.obj("number_plate"):
        env.box((0.37, 1.72, 0.02), (0.53, 1.80, 0.028), "metal_alu", mats={"+z": "plate_blank"},
                rects={"+z": (0, 0, 1, 1)})
    env.box((0.80, 1.18, 0.02), (0.86, 1.24, 0.045), "metal_dark")   # padlock hasp
    env.marker("number_plate", (0.45, 1.76, 0.03))
    env.marker("padlock", (0.83, 1.21, 0.05))
    return env


def door_glass_shop():
    env = L.Env("door_glass_shop")
    w, h, t, fr = 0.9, 2.1, 0.05, 0.07
    env.box((0, 0, -t / 2), (fr, h, t / 2), "metal_alu")                 # hinge stile
    env.box((w - fr, 0, -t / 2), (w, h, t / 2), "metal_alu")             # lock stile
    env.box((fr, h - fr, -t / 2), (w - fr, h, t / 2), "metal_alu")       # top rail
    env.box((fr, 0, -t / 2), (w - fr, 0.22, t / 2), "metal_alu")         # kick plate
    with env.obj("door_glass"):
        env.quad((fr, 0.22, 0), (w - 2 * fr, 0, 0), (0, h - fr - 0.22, 0), "glass@glass", uv="fit")
    for s in (1, -1):  # vertical pull bars
        z = s * (t / 2 + 0.05)
        env.box((w - 0.17, 0.8, z - 0.015), (w - 0.14, 1.4, z + 0.015), "metal_alu")
        za, zb = sorted((z, s * t / 2))
        env.box((w - 0.17, 0.85, za), (w - 0.14, 0.88, zb), "metal_alu", skip=("+z", "-z"))
        env.box((w - 0.17, 1.32, za), (w - 0.14, 1.35, zb), "metal_alu", skip=("+z", "-z"))
    env.card((w / 2, 1.15, 0.008), 0.22, 0.11, "sticker_push")
    env.card((w / 2, 1.15, -0.008), 0.22, 0.11, "sticker_push", yaw=180)
    env.col((0, 0, -t / 2), (w, h, t / 2), "door")
    return env


def gate_iron():
    env = L.Env("gate_iron")
    w, h, m = 1.0, 2.0, "metal_paint"
    env.box((0, 0, -0.03), (0.05, h + 0.1, 0.03), m)              # hinge post
    env.box((w - 0.05, 0, -0.03), (w, h, 0.03), m)
    for y in (0.08, 1.0, h - 0.06):
        env.box((0.05, y, -0.02), (w - 0.05, y + 0.05, 0.02), m)
    n = 8
    for i in range(n):
        x = 0.05 + (i + 0.5) * (w - 0.1) / n
        env.box((x - 0.012, 0.13, -0.012), (x + 0.012, h + 0.12, 0.012), m, skip=("-y",))
        env.face([(x - 0.03, h + 0.12, 0), (x + 0.03, h + 0.12, 0), (x, h + 0.24, 0)], m)
        env.face([(x + 0.03, h + 0.12, 0), (x - 0.03, h + 0.12, 0), (x, h + 0.24, 0)], m)
    env.quad((0.05, 0.13, 0.0), (w - 0.1, 0, 0), (0, 0.87, 0), "iron_gate@cut", uv="fit")
    env.box((w - 0.2, 0.95, 0.02), (w - 0.06, 1.12, 0.07), "metal_dark")    # lock box
    env.col((0, 0, -0.04), (w, h + 0.2, 0.04), "door")
    return env


def streetlight():
    env = L.Env("streetlight")
    lamp = P.streetlight(env, (0, 0, 0), name="streetlight")
    env.marker("lamp", lamp, pitch=-90)
    env.col((-0.2, 0, -0.2), (0.2, 6.6, 0.2), "pole")
    return env


def motorbike_parked():
    env = L.Env("motorbike_parked")
    P.motorbike(env, (0, 0, 0))
    env.col((-0.35, 0, -0.95), (0.35, 1.0, 1.0), "props")
    return env


def cables_cluster():
    env = L.Env("cables_cluster")
    rng = random.Random(3)
    P.cables_between(env, (-4, 0), (4, 0), 0.0, n=7, sag=0.7, rng=rng, spread=0.3)
    P.cables_between(env, (-4, -0.4), (4, 0.5), 0.1, n=3, sag=0.5, rng=rng, spread=0.2)
    env.cyl((0.3, -0.9, 0), 0.25, 0.4, "cables@cut", segs=6, caps=(False, False), uv_v=(0.1, 0.9))
    return env


def potted_plant():
    env = L.Env("potted_plant")
    P.potted_plant(env, (0, 0, 0))
    env.col((-0.2, 0, -0.2), (0.2, 0.35, 0.2), "props")
    return env


def plastic_stool():
    env = L.Env("plastic_stool")
    P.stool(env, (0, 0, 0))
    return env


def banyan_tree():
    env = L.Env("banyan_tree")
    P.banyan(env, (0, 0, 0))
    return env


PIECES = {f.__name__: f for f in (door_wood, door_dorm, door_glass_shop, gate_iron, streetlight,
                                   motorbike_parked, cables_cluster, potted_plant, plastic_stool, banyan_tree)}

if __name__ == "__main__":
    args = L.run_args()
    names = args or list(PIECES)
    for n in names:
        PIECES[n]().export()
