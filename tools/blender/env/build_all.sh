#!/usr/bin/env bash
# Rebuild all environment textures + glbs (Track C1).
#   tools/blender/env/build_all.sh            # textures + all glbs
#   tools/blender/env/build_all.sh --no-tex   # glbs only
#   BLENDER=/path/to/blender tools/blender/env/build_all.sh
# Optional previews: PREVIEW_DIR=/tmp/pv tools/blender/env/build_all.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BLENDER="${BLENDER:-blender}"
cd "$ROOT"

if [[ "${1:-}" != "--no-tex" ]]; then
  python3 tools/textures/env/make_textures.py | tail -n 1
fi

LEVELS=(school store alley dorm shrine)
PIECES=(door_wood door_dorm door_glass_shop gate_iron streetlight motorbike_parked cables_cluster potted_plant plastic_stool banyan_tree)

fail=0
summary=""
for n in "${LEVELS[@]}" "${PIECES[@]}"; do
  out="$("$BLENDER" -b --factory-startup -P "$HERE/build_$n.py" 2>&1)" || { echo "$out" | tail -n 30; echo "FAILED: $n"; fail=1; continue; }
  line="$(echo "$out" | grep -E '^\[env\] [a-z_]+\.glb' || true)"
  if [[ -z "$line" ]] || echo "$out" | grep -q "Traceback"; then
    echo "$out" | grep -A 20 Traceback || true
    echo "FAILED: $n"; fail=1; continue
  fi
  summary+="$line"$'\n'
  if [[ -n "${PREVIEW_DIR:-}" ]]; then
    "$BLENDER" -b --factory-startup -P "$HERE/preview_glb.py" -- "assets/models/env/$n.glb" "$PREVIEW_DIR/$n" night >/dev/null 2>&1 || true
  fi
done

echo "---------------------------------------------------------------"
echo -n "$summary"
for n in "${LEVELS[@]}" "${PIECES[@]}"; do
  [[ -f "assets/models/env/$n.glb" ]] || { echo "MISSING assets/models/env/$n.glb"; fail=1; }
done
exit $fail
