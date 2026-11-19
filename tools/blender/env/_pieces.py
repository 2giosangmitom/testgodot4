"""Shared builders for the standalone piece glbs (doors, gate)."""


def door_panel(env, tex, w=0.9, h=2.1, t=0.045, edge="wood_dark"):
    """Door leaf with hinge at origin: spans x 0..w, y 0..h, z -t/2..t/2. Front = +Z."""
    env.box((0, 0, -t / 2), (w, h, t / 2), edge, mats={"+z": tex, "-z": tex},
            rects={"+z": (0, 0, 1, 1), "-z": (1, 0, 0, 1)})
    for s in (1, -1):  # lever handles on both sides
        if s > 0:
            env.box((w - 0.12, 0.98, t / 2), (w - 0.07, 1.06, t / 2 + 0.04), "metal_alu", skip=("-z",))
            env.box((w - 0.24, 1.0, t / 2 + 0.04), (w - 0.07, 1.04, t / 2 + 0.06), "metal_alu")
        else:
            env.box((w - 0.12, 0.98, -t / 2 - 0.04), (w - 0.07, 1.06, -t / 2), "metal_alu", skip=("+z",))
            env.box((w - 0.24, 1.0, -t / 2 - 0.06), (w - 0.07, 1.04, -t / 2 - 0.04), "metal_alu")
    env.col((0, 0, -t / 2), (w, h, t / 2), "door")
