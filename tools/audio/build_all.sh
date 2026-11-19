#!/usr/bin/env bash
# Regenerate every audio asset in assets/audio/ and verify it against docs/audio_manifest.md.
#
#   tools/audio/build_all.sh            # fetch packs (cached), TTS (cached), synth, check
#   tools/audio/build_all.sh --no-tts   # skip the VieNeu steps (use committed voices / src takes)
#   tools/audio/build_all.sh --force    # re-roll all TTS takes (voices + tools/audio/src)
#
# Needs: ffmpeg (with libvorbis + rubberband), python3 + numpy, and the VieNeu-TTS venv for the TTS steps.
set -euo pipefail
cd "$(dirname "$0")/../.."

VENV_PY="${VIENEU_PY:-$HOME/Workspace/tools/VieNeu-TTS/.venv/bin/python}"
TTS=1
FORCE=""
for a in "$@"; do
  case "$a" in
    --no-tts) TTS=0 ;;
    --force) FORCE="--force" ;;
    *) echo "unknown arg $a"; exit 2 ;;
  esac
done

echo "== 1/5 CC0 packs"
python3 -I tools/audio/fetch_cc0.py || echo "(fetch failed: synth fallbacks will be used)"

if [[ $TTS == 1 ]]; then
  if [[ -x "$VENV_PY" ]]; then
    echo "== 2/5 TTS source takes (rao dem, whispers)"
    "$VENV_PY" -I tools/audio/tts_specials.py $FORCE
    echo "== 3/5 voice lines"
    "$VENV_PY" -I tools/audio/tts_build.py $FORCE
  else
    echo "VieNeu venv python not found at $VENV_PY (set VIENEU_PY) — skipping TTS"
  fi
fi

echo "== 4/5 sfx / ambience / music"
python3 -I tools/audio/synth.py

echo "== 5/5 manifest check"
python3 -I tools/audio/check_manifest.py --quiet
