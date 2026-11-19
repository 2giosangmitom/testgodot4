"""Post-process Blender-exported .glb files (pure python, usable inside or outside Blender).

- Materials get their base-color texture as an EXTERNAL image uri (relative to the glb), sampled
  NEAREST/NEAREST. The textures live once in assets/textures/{chars,props}/ with our own .import
  settings (lossless, no mipmaps) instead of being embedded + re-extracted by Godot per glb.
- Optional STEP interpolation for named animations (stiff / held poses).
- Morph target default weights forced to 0.
"""
import json
import os
import struct

NEAREST = 9728


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _, _ = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, path
    clen, _ = struct.unpack_from("<II", data, 12)
    g = json.loads(data[20:20 + clen])
    rest = data[20 + clen:]
    return g, rest


def write_glb(path, g, rest):
    js = json.dumps(g, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + len(rest)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(rest)


def postprocess(path, textures=None, step_anims=(), alpha_materials=()):
    """textures: {material_name: absolute png path}."""
    g, rest = read_glb(path)
    textures = textures or {}
    if textures:
        g["samplers"] = [{"magFilter": NEAREST, "minFilter": NEAREST, "wrapS": 10497, "wrapT": 10497}]
        g["images"] = []
        g["textures"] = []
        uri_index = {}
        for m in g.get("materials", []):
            tex = textures.get(m.get("name"))
            if not tex:
                continue
            uri = os.path.relpath(tex, os.path.dirname(path)).replace(os.sep, "/")
            if uri not in uri_index:
                g["images"].append({"uri": uri, "name": os.path.splitext(os.path.basename(tex))[0]})
                g["textures"].append({"sampler": 0, "source": len(g["images"]) - 1})
                uri_index[uri] = len(g["textures"]) - 1
            pbr = m.setdefault("pbrMetallicRoughness", {})
            pbr["baseColorTexture"] = {"index": uri_index[uri]}
            pbr["metallicFactor"] = 0.0
            pbr["roughnessFactor"] = 1.0
            pbr.pop("baseColorFactor", None)
            m.pop("doubleSided", None)  # PS1: back-face culling
            m.pop("extensions", None)
            if m.get("name") in alpha_materials:
                m["alphaMode"] = "MASK"
                m["alphaCutoff"] = 0.5
                m["doubleSided"] = True
        if not g["images"]:
            for k in ("samplers", "images", "textures"):
                g.pop(k)
    if "extensionsUsed" in g:
        g["extensionsUsed"] = [e for e in g["extensionsUsed"] if e != "KHR_materials_specular"]
        if not g["extensionsUsed"]:
            g.pop("extensionsUsed")
    for a in g.get("animations", []):
        if a["name"] in step_anims:
            for smp in a["samplers"]:
                smp["interpolation"] = "STEP"
    for m in g.get("meshes", []):
        names = m.get("extras", {}).get("targetNames")
        if names:
            m["weights"] = [0.0] * len(names)
    write_glb(path, g, rest)
