#!/usr/bin/env bash
# Rebuild Track C2 props: textures -> glbs -> Godot .import files -> verify.
# Usage: tools/blender/props/build_all.sh [--no-godot] [prop names...]
set -euo pipefail
cd "$(dirname "$0")/../../.."
GODOT=1
if [[ "${1:-}" == "--no-godot" ]]; then GODOT=0; shift; fi

python3 tools/textures/props/make_prop_textures.py
blender -b --factory-startup -P tools/blender/props/build_props.py -- "$@" 2>&1 | grep -E "^\[prop\]|Error|Traceback" || true
python3 tools/textures/chars/write_imports.py

if [[ $GODOT == 1 ]]; then
  godot --headless --path . --import 2>&1 | grep -iE "error" || true
  godot --headless --path . -s res://tools/blender/props/verify_props.gd 2>&1 | grep -E "FAIL|VERIFY"
fi
