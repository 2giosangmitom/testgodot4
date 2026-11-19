"""Render low-res previews of an exported env glb (verifies the export round-trip too).

blender -b --factory-startup -P preview_glb.py -- <in.glb> <out_prefix> [mode] [cam specs...]
  mode: 'night' (dark ambient, point lights at MARKER_*light*/lamp/bulb/tube markers) or 'day'
  cam spec: "x,y,z:tx,ty,tz" in Godot coords (extra viewpoints). Every MARKER_cam_* in the file
  is rendered as well.  Output: <out_prefix>_<cam>.png (640x480).
"""
import bpy
import math
import os
import sys
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
glb, prefix = args[0], args[1]
mode = args[2] if len(args) > 2 else "day"
specs = args[3:]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
scene = bpy.context.scene

# make sure vertex colours multiply the texture and textures stay Closest
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    nt = mat.node_tree
    for n in nt.nodes:
        if n.type == "TEX_IMAGE":
            n.interpolation = "Closest"
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        continue
    if mat.name.endswith("_emit"):
        bsdf.inputs["Emission Strength"].default_value = 3.0 if mode == "night" else 1.0
        continue
    if mat.name.endswith("_glass"):
        continue
    bc = bsdf.inputs["Base Color"]
    if bc.links and bc.links[0].from_node.type == "TEX_IMAGE":
        img = bc.links[0].from_node
        vc = nt.nodes.new("ShaderNodeVertexColor")
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        nt.links.new(img.outputs["Color"], mix.inputs[6])
        nt.links.new(vc.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], bc)

# hide collision meshes
for ob in list(scene.objects):
    if "-colonly" in ob.name or ob.name.endswith("-col"):
        ob.hide_render = True

world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
if mode == "night":
    bg.inputs[0].default_value = (0.03, 0.035, 0.05, 1)
    bg.inputs[1].default_value = 1.0
else:
    bg.inputs[0].default_value = (0.55, 0.6, 0.65, 1)
    bg.inputs[1].default_value = 1.0
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 2.5
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    scene.collection.objects.link(so)

# point lights at light markers
for ob in list(scene.objects):
    if ob.type != "EMPTY":
        continue
    n = ob.name.lower()
    if not n.startswith("marker_"):
        continue
    if any(k in n for k in ("light", "lamp", "bulb", "tube", "streetlight")) and "cam" not in n:
        sodium = "street" in n or "far_light" in n
        ld = bpy.data.lights.new(ob.name + "_L", "POINT")
        ld.energy = (900 if sodium else 120) if mode == "night" else (300 if sodium else 60)
        ld.color = (1.0, 0.62, 0.25) if sodium else (0.9, 1.0, 0.92)
        ld.shadow_soft_size = 0.1
        lo = bpy.data.objects.new(ob.name + "_L", ld)
        lo.location = ob.matrix_world.translation
        scene.collection.objects.link(lo)

scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 640
scene.render.resolution_y = 480
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
try:
    scene.view_settings.view_transform = "Standard"
except Exception:
    pass

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 18
cam_data.clip_start = 0.05
cam_data.clip_end = 300
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam


def g2b(p):
    return Vector((p[0], -p[2], p[1]))


views = []
for ob in scene.objects:
    if ob.type == "EMPTY" and ob.name.startswith("MARKER_cam"):
        views.append((ob.name[7:], ob.matrix_world @ Matrix.Rotation(math.radians(90), 4, "X")))
for i, s in enumerate(specs):
    a, b = s.split(":")
    p = g2b([float(v) for v in a.split(",")])
    t = g2b([float(v) for v in b.split(",")])
    d = (t - p).normalized()
    rot = d.to_track_quat("-Z", "Y").to_matrix().to_4x4()
    views.append((f"v{i}", Matrix.Translation(p) @ rot))

os.makedirs(os.path.dirname(prefix) or ".", exist_ok=True)
for name, mw in views:
    cam.matrix_world = mw
    scene.render.filepath = f"{prefix}_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("[preview]", scene.render.filepath)
