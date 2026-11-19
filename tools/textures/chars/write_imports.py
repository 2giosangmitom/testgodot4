#!/usr/bin/env python3
"""Write Godot .import files for PSX textures (lossless, no mipmaps, no 3D VRAM auto-compress)
and for character/prop glbs (looping animations). Existing uid lines are preserved.

Run after generating textures/models, before `godot --headless --import`:
  python3 tools/textures/chars/write_imports.py
"""
import glob
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
TEX_DIRS = ["assets/textures/chars", "assets/textures/props"]
GLB_DIRS = ["assets/models/chars", "assets/models/props"]
LOOP_ANIMS = ["idle", "walk", "run", "stiff_run", "sit", "sweep", "wait", "stand_stare"]

TEX_PARAMS = """[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def existing_uid(path):
    if os.path.exists(path):
        m = re.search(r'^uid="([^"]+)"', open(path).read(), re.M)
        if m:
            return m.group(1)
    return None


def write_tex(png):
    imp = png + ".import"
    uid = existing_uid(imp)
    head = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
    if uid:
        head += f'uid="{uid}"\n'
    open(imp, "w").write(head + "\n" + TEX_PARAMS)


def write_glb(glb, loops):
    imp = glb + ".import"
    uid = existing_uid(imp)
    head = '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n'
    if uid:
        head += f'uid="{uid}"\n'
    anims = ",\n".join(f'"{a}": {{\n"settings/loop_mode": 1\n}}' for a in loops)
    params = f"""[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=1
meshes/force_disable_compression=true
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=false
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
_subresources={{
"animations": {{
{anims}
}}
}}
gltf/naming_version=2
gltf/embedded_image_handling=1
"""
    if not loops:
        params = params.replace('_subresources={\n"animations": {\n\n}\n}', "_subresources={}")
    open(imp, "w").write(head + "\n" + params)


def main():
    n = 0
    for d in TEX_DIRS:
        for png in sorted(glob.glob(os.path.join(ROOT, d, "*.png"))):
            write_tex(png)
            n += 1
    for d in GLB_DIRS:
        for glb in sorted(glob.glob(os.path.join(ROOT, d, "*.glb"))):
            write_glb(glb, LOOP_ANIMS if "/chars/" in glb else [])
            n += 1
    print(f"wrote {n} .import files")


if __name__ == "__main__":
    main()
