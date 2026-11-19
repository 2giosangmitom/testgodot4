#!/usr/bin/env bash
# Rebuild all Track C2 character assets: textures -> glbs -> Godot .import files -> verify.
# Usage: tools/blender/chars/build_all.sh [--no-godot] [names...]
set -euo pipefail
cd "$(dirname "$0")/../../.."
GODOT=1
if [[ "${1:-}" == "--no-godot" ]]; then GODOT=0; shift; fi

python3 tools/textures/chars/make_faces.py "$@"
python3 tools/textures/chars/make_clothes.py "$@"
blender -b --factory-startup -P tools/blender/chars/build_character.py -- "$@" 2>&1 | grep -E "^\[char\]|Error|Traceback" || true
python3 tools/textures/chars/write_imports.py
python3 tools/blender/chars/inspect_glb.py assets/models/chars/*.glb | grep -E "^==" || true

if [[ $GODOT == 1 ]]; then
  godot --headless --path . --import 2>&1 | grep -iE "error" || true
  godot --headless --path . -s res://tools/blender/chars/verify_chars.gd 2>&1 | grep -E "FAIL|VERIFY"
fi
