"""Render a lineup of exported character/prop glbs (Workbench, textured, Closest filtering).

Usage:
  blender -b --factory-startup -P tools/blender/chars/render_preview.py -- OUT.png [--anim NAME --frame F]
      [--cols N] [--spacing M] [--res WxH] [--angle DEG] [--key KEY=VALUE shape key] glb1 glb2 ...
"""
import bpy
import math
import os
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv.pop(0)
opts = {"anim": None, "frame": 0, "cols": 99, "spacing": 0.8, "res": "640x480", "angle": 20.0, "key": None,
        "height": None, "ortho": None}
files = []
i = 0
while i < len(argv):
    a = argv[i]
    if a.startswith("--"):
        opts[a[2:]] = argv[i + 1]
        i += 2
    else:
        files.append(a)
        i += 1

bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.engine = "BLENDER_WORKBENCH"
scn.display.shading.light = "STUDIO"
scn.display.shading.color_type = "TEXTURE"
scn.display.shading.show_backface_culling = True
scn.display.shading.show_specular_highlight = False
if os.environ.get("PREVIEW_FLAT"):
    scn.display.shading.light = "FLAT"
scn.render.film_transparent = False
w, h = map(int, opts["res"].split("x"))
scn.render.resolution_x, scn.render.resolution_y = w, h
scn.render.resolution_percentage = 100
scn.world = bpy.data.worlds.new("w")
scn.display.shading.background_type = "VIEWPORT"
scn.display.shading.background_color = (0.18, 0.2, 0.22)

cols = int(opts["cols"])
sp = float(opts["spacing"])
maxh = 0.0
minx, maxx, maxy_row = 1e9, -1e9, 0
for idx, f in enumerate(files):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    col, row = idx % cols, idx // cols
    off = Vector((col * sp, row * sp * 1.6, 0))
    for r in roots:
        r.location += off
    for o in new:
        if o.type == "ARMATURE" and opts["anim"]:
            act = None
            for a in bpy.data.actions:
                if a.name == opts["anim"] or a.name.startswith(opts["anim"] + "_") or a.name.startswith(opts["anim"] + "."):
                    if act is None or len(a.name) < len(act.name):
                        act = a
            # prefer the action imported with this file
            cand = [a for a in bpy.data.actions if a.name.split("_")[0] == opts["anim"].split("_")[0]]
            if o.animation_data is None:
                o.animation_data_create()
            if o.animation_data.nla_tracks:
                for t in o.animation_data.nla_tracks:
                    t.mute = t.name != opts["anim"]
                    for s in t.strips:
                        if t.name == opts["anim"]:
                            o.animation_data.action = s.action
            if o.animation_data.action is None and act is not None:
                o.animation_data.action = act
            if o.animation_data.action is not None:
                try:
                    o.animation_data.action_slot = o.animation_data.action.slots[0]
                except Exception:
                    pass
        if o.type == "MESH" and opts["key"] and o.data.shape_keys:
            for kv in opts["key"].split(","):
                k, v = kv.split("=")
                if k in o.data.shape_keys.key_blocks:
                    o.data.shape_keys.key_blocks[k].value = float(v)
        if o.type == "MESH":
            for m in o.data.materials:
                if m and m.node_tree:
                    for n in m.node_tree.nodes:
                        if n.type == "TEX_IMAGE":
                            n.interpolation = "Closest"
    bpy.context.view_layer.update()
    bb = [o.matrix_world @ Vector(c) for o in new if o.type == "MESH" for c in o.bound_box]
    if bb:
        maxh = max(maxh, max(v.z for v in bb))
        minx = min(minx, min(v.x for v in bb))
        maxx = max(maxx, max(v.x for v in bb))
    maxy_row = max(maxy_row, row)

scn.frame_set(int(opts["frame"]))
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scn.collection.objects.link(cam)
scn.camera = cam
cx = (minx + maxx) / 2
width = maxx - minx
rows = maxy_row + 1
cam_data.type = "ORTHO"
ang = math.radians(float(opts["angle"]))
H = float(opts["height"]) if opts["height"] else maxh * 0.55
cam_data.ortho_scale = max(width * 1.1, maxh * 1.2 * w / h * (1 + 0.6 * (rows - 1)))
if opts.get("ortho"):
    cam_data.ortho_scale = float(opts["ortho"])
cam.location = Vector((cx + math.sin(ang) * 20, -math.cos(ang) * 20 + (rows - 1) * sp * 0.8, H + 4.0))
direction = Vector((cx, (rows - 1) * sp * 0.8, H)) - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
print("[preview] wrote", out)
