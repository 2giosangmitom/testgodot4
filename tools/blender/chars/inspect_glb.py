#!/usr/bin/env python3
"""Print a summary of .glb files: meshes/tris, morph targets, skins/joints, animations, extras.

Usage: python3 tools/blender/chars/inspect_glb.py assets/models/chars/*.glb
"""
import json
import struct
import sys


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, path
    clen, ctype = struct.unpack_from("<II", data, 12)
    return json.loads(data[20:20 + clen])


def tris(g, mesh):
    n = 0
    for p in mesh["primitives"]:
        if "indices" in p:
            n += g["accessors"][p["indices"]]["count"] // 3
        else:
            n += g["accessors"][p["attributes"]["POSITION"]]["count"] // 3
    return n


def main():
    for path in sys.argv[1:]:
        g = load(path)
        meshes = g.get("meshes", [])
        total = sum(tris(g, m) for m in meshes)
        morphs = sorted({t for m in meshes for t in m.get("extras", {}).get("targetNames", [])})
        joints = [g["nodes"][j]["name"] for s in g.get("skins", []) for j in s["joints"]]
        anims = [(a["name"], round(max(g["accessors"][s["input"]]["max"][0] for s in a["samplers"]), 2),
                  sorted({s.get("interpolation", "LINEAR") for s in a["samplers"]})) for a in g.get("animations", [])]
        extras = {n["name"]: n["extras"] for n in g["nodes"] if "extras" in n}
        imgs = [(i.get("name"), i.get("mimeType")) for i in g.get("images", [])]
        print(f"== {path}: tris={total} meshes={[m['name'] for m in meshes]}")
        if morphs:
            print("   morphs:", morphs)
        if joints:
            print("   joints:", joints)
        if anims:
            print("   anims:", anims)
        if extras:
            print("   extras:", extras)
        print("   images:", imgs, "samplers:", g.get("samplers"))


if __name__ == "__main__":
    main()
