#!/usr/bin/env python3
"""Verify assets/audio against docs/audio_manifest.md and data/dialogue/lines_*.json.

Checks every manifest name (sfx/amb/music, expanding `name_1..4` and `a / b`) and every dialogue
key (voice) exists as .ogg with the expected sample rate and mono. Prints a table; exit 1 on failure.

    python3 tools/audio/check_manifest.py [--quiet]
"""
import argparse
import glob
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
AUDIO = REPO / "assets" / "audio"
RATES = {"sfx": {22050, 11025}, "amb": {22050, 32000, 11025}, "music": {22050, 32000}, "voice": {22050}}
SECTION = re.compile(r"^##\s+(sfx|amb|music|voice)\b")


def manifest_names():
    out = {"sfx": [], "amb": [], "music": []}
    cur = None
    for line in (REPO / "docs" / "audio_manifest.md").read_text(encoding="utf8").splitlines():
        m = SECTION.match(line)
        if m:
            cur = m.group(1) if m.group(1) in out else None
            continue
        if cur is None or not line.startswith("|"):
            continue
        cell = line.split("|")[1].strip()
        if cell in ("name", "") or set(cell) <= set("-: "):
            continue
        for part in cell.split("/"):
            part = part.strip().strip("`")
            r = re.fullmatch(r"(.+?)(\d+)\.\.(\d+)", part)
            if r:
                out[cur] += [f"{r.group(1)}{i}" for i in range(int(r.group(2)), int(r.group(3)) + 1)]
            elif part:
                out[cur].append(part)
    return out


def dialogue_keys():
    keys = []
    for f in sorted(glob.glob(str(REPO / "data" / "dialogue" / "lines_*.json"))):
        keys += list(json.load(open(f, encoding="utf8")).keys())
    return keys


def probe(p):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels:format=duration",
                        "-of", "json", str(p)], capture_output=True, text=True)
    j = json.loads(r.stdout or "{}")
    s = (j.get("streams") or [{}])[0]
    return s.get("codec_name"), int(s.get("sample_rate", 0)), int(s.get("channels", 0)), float(j.get("format", {}).get("duration", 0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="only print failures + summary")
    a = ap.parse_args()
    expected = manifest_names()
    expected["voice"] = dialogue_keys()
    fails, rows, total_bytes = [], [], 0
    for kind, names in expected.items():
        for name in names:
            p = AUDIO / kind / f"{name}.ogg"
            if not p.exists():
                fails.append(f"{kind}/{name}: MISSING")
                rows.append((kind, name, "-", "-", "-", "-", "MISSING"))
                continue
            codec, sr, ch, dur = probe(p)
            total_bytes += p.stat().st_size
            ok = codec == "vorbis" and sr in RATES[kind] and ch == 1 and dur > 0.01
            status = "ok" if ok else "BAD"
            if not ok:
                fails.append(f"{kind}/{name}: codec={codec} sr={sr} ch={ch} dur={dur:.2f}")
            rows.append((kind, name, codec, sr, ch, f"{dur:.2f}", status))
    extra = []
    for kind in expected:
        have = {Path(f).stem for f in glob.glob(str(AUDIO / kind / "*.ogg"))}
        extra += [f"{kind}/{n}" for n in sorted(have - set(expected[kind]))]
    if not a.quiet:
        print(f"{'kind':6s} {'name':26s} {'codec':7s} {'rate':>6s} ch {'dur':>7s}  status")
        for r in rows:
            print(f"{r[0]:6s} {r[1]:26s} {str(r[2]):7s} {str(r[3]):>6s} {str(r[4]):>2s} {r[5]:>7s}  {r[6]}")
    print(f"\n{len(rows)} expected files ({', '.join(f'{k}: {len(v)}' for k, v in expected.items())}), "
          f"{len(fails)} problems, {total_bytes / 1e6:.1f} MB")
    if extra:
        print("not in manifest (unused by contract):", ", ".join(extra))
    for f in fails:
        print("FAIL", f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
