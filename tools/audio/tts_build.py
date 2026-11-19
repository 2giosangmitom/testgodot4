#!/usr/bin/env python3
"""Generate voice lines: data/dialogue/lines_*.json -> assets/audio/voice/<key>.ogg (22050 Hz mono).

MUST run with the VieNeu venv python:
    ~/Workspace/tools/VieNeu-TTS/.venv/bin/python -I tools/audio/tts_build.py [--only ch2_] [--force]
        [--lines path.json ...] [--out dir] [--manifest path] [--dry-run]

Per line: speaker -> VieNeu preset voice (speakers.json, overridable in VOICE_OVERRIDE below),
TTS at 48 kHz -> fx_chain.apply_fx(fx) -> loudness normalise -> ogg.
Entity / mimic lines: speaker "mimic_<id>" (or "<id>" with fx entity/door) uses the imitated
person's voice; "???" (Tuấn) uses Nam's voice. Then the line's fx.
Cache: tools/audio/voice_manifest.json {key: sha1(text|voice|fx|PIPELINE_VERSION)}; unchanged lines are skipped.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import sys
import time
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
import numpy as np  # noqa: E402
import fx_chain as fxc  # noqa: E402

PIPELINE_VERSION = "4"  # bump to force a full rebuild after fx changes
# Track-D voice overrides (speaker id -> preset voice). Empty = use speakers.json as-is.
VOICE_OVERRIDE: dict[str, str] = {}
# Per-speaker tweaks applied before fx: (semitones pitch shift, tempo factor)
SPEAKER_TWEAK: dict[str, tuple[float, float]] = {
    "ba_cu": (0.0, 0.92),       # old woman: slower
    "bac_bao_ve": (-1.0, 0.94),  # old guard: slower, a bit lower/rougher
}
# Per-speaker breathiness (0..1 blend with a whispered copy) — acting notes: "Bà cụ: thì thầm"
SPEAKER_BREATHY: dict[str, float] = {"ba_cu": 0.55}
MIMIC_PREFIXES = ("mimic_",)
TTS_SR = 48000
OUT_SR = 22050


# ───────────────────────── VieNeu loading (ONNX path workaround) ─────────────────────────
def load_vieneu():
    """onnxruntime >= 1.2x refuses external-data files that are symlinks into the HF blob store.
    We wrap the engine's artifact fetch so it returns a directory of hard links (same fs) instead."""
    cache = HERE / "_cache" / "onnx_links"
    try:
        from vieneu._v3_turbo_engine import onnx_runtime_lite as orl
        orig = orl.OnnxV3LiteEngine._fetch

        def _fetch(repo, files, subfolder):
            src = orig(repo, files, subfolder)
            dst = cache / (repo.replace("/", "--") + ("--" + subfolder if subfolder else ""))
            dst.mkdir(parents=True, exist_ok=True)
            for f in src.iterdir():
                d = dst / f.name
                if not d.exists():
                    try:
                        os.link(f.resolve(), d)
                    except OSError:
                        shutil.copy2(f.resolve(), d)
            return dst

        orl.OnnxV3LiteEngine._fetch = staticmethod(_fetch)
    except Exception as e:  # engine layout changed — try plain load
        print("note: ONNX fetch patch not applied:", e)
    from vieneu import Vieneu
    return Vieneu()


# ───────────────────────── data ─────────────────────────
def load_lines(paths):
    lines = {}
    for p in paths:
        with open(p, encoding="utf8") as f:
            d = json.load(f)
        for k, v in d.items():
            if k in lines:
                print(f"warning: duplicate key {k} in {p}")
            lines[k] = v
    return lines


def resolve_voice(speaker: str, fx: str, speakers: dict) -> tuple[str, str]:
    """Return (voice, effective_fx)."""
    sp = speaker
    for pre in MIMIC_PREFIXES:
        if sp.startswith(pre):
            sp = sp[len(pre):]
            if fx in ("none", ""):
                fx = "entity"
    if sp == "???":
        sp = "nam" if "nam" in speakers else sp
    voice = VOICE_OVERRIDE.get(sp) or speakers.get(sp, {}).get("voice")
    if not voice:
        voice = speakers.get("nam", {}).get("voice", "Hải Đăng")
        print(f"warning: unknown speaker '{speaker}', using {voice}")
    return voice, fx or "none"


def clean_text(t: str) -> str:
    t = t.strip()
    t = re.sub(r"^\((.*)\)$", r"\1", t)  # inner monologue "( … )" — still read
    t = t.replace("…", "...")
    t = re.sub(r"\s+", " ", t)
    return t


def line_hash(text, voice, fx, speaker):
    return hashlib.sha1(f"{text}|{voice}|{fx}|{speaker}|{PIPELINE_VERSION}".encode()).hexdigest()


# ───────────────────────── processing ─────────────────────────
def take_problem(audio, text) -> str | None:
    """Heuristic QA of a raw 48 kHz take: cut-off ending or implausible speaking rate."""
    x = np.asarray(audio, np.float32)
    if len(x) < TTS_SR * 0.3:
        return "too short"
    pk = np.max(np.abs(x)) + 1e-9
    tail = np.sqrt(np.mean(x[-int(0.08 * TTS_SR):] ** 2)) / pk
    if tail > 0.08:
        return f"speech still running at the end (tail {20 * np.log10(tail):.0f} dB)"
    rate = len(re.findall(r"\w+", text)) / (len(x) / TTS_SR)
    if rate < 1.6 or rate > 8.0:
        return f"implausible rate {rate:.1f} syl/s"
    return None

def post(audio: np.ndarray, speaker: str, fx: str, seed: int) -> tuple[np.ndarray, int]:
    x = np.asarray(audio, np.float32)
    semis, tempo = SPEAKER_TWEAK.get(speaker, (0.0, 1.0))
    if semis or tempo != 1.0:
        x = fxc.ffilter(x, TTS_SR, f"rubberband=tempo={tempo}:pitch={2 ** (semis / 12):.5f}:pitchq=quality")
    br = SPEAKER_BREATHY.get(speaker, 0.0)
    if br > 0:
        w = fxc.whisperize(x, nfft=1024, seed=seed)
        w *= np.sqrt(np.mean(x ** 2)) / (np.sqrt(np.mean(w ** 2)) + 1e-9)
        x = (1 - br) * x + br * fxc.filt(w, TTS_SR, hp=300, lp=7000)
    y, sr = fxc.apply_fx(x, TTS_SR, fx, seed=seed, out_sr=OUT_SR)
    y = fxc.normalize(y, sr, fxc.FX_LUFS.get(fx, -18.0), peak_db=-1.0)
    return y, sr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None, help="key prefix filter")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--lines", nargs="*", default=None, help="lines json files (default data/dialogue/lines_*.json)")
    ap.add_argument("--speakers", default=str(REPO / "data/dialogue/speakers.json"))
    ap.add_argument("--out", default=str(REPO / "assets/audio/voice"))
    ap.add_argument("--manifest", default=str(HERE / "voice_manifest.json"))
    ap.add_argument("--keep-raw", default=None, help="dir to also store the raw 48 kHz TTS wavs")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-batch", action="store_true", help="never use infer_batch")
    a = ap.parse_args()

    speakers = json.load(open(a.speakers, encoding="utf8"))
    paths = a.lines or sorted(glob.glob(str(REPO / "data/dialogue/lines_*.json")))
    lines = load_lines(paths)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    man_path = Path(a.manifest)
    manifest = json.loads(man_path.read_text()) if man_path.exists() else {}

    todo = []  # (key, text, voice, fx, speaker, hash)
    for k, v in sorted(lines.items()):
        if a.only and not k.startswith(a.only):
            continue
        voice, fx = resolve_voice(v["speaker"], v.get("fx", "none"), speakers)
        text = clean_text(v["text"])
        h = line_hash(text, voice, fx, v["speaker"])
        if not a.force and manifest.get(k) == h and (out / f"{k}.ogg").exists():
            continue
        todo.append((k, text, voice, fx, v["speaker"], h))
    print(f"{len(lines)} lines, {len(todo)} to build")
    if a.dry_run or not todo:
        for t in todo:
            print("  ", t[0], t[2], t[3], t[1])
        return 0

    tts = load_vieneu()
    by_voice: dict[str, list] = {}
    for t in todo:
        by_voice.setdefault(t[2], []).append(t)
    t0 = time.time()
    # infer_batch only pays off on the GPU/PyTorch engine; on CPU/ONNX it is sequential anyway and a
    # batched run once produced equal-length (capped) takes, so use plain infer() there.
    use_batch = getattr(tts, "backend", "onnx") != "onnx" and not a.no_batch
    for voice, items in by_voice.items():
        texts = [i[1] for i in items]
        audios = None
        if use_batch:
            try:
                audios = tts.infer_batch(texts, voice=voice)
            except Exception as e:
                print(f"infer_batch failed for {voice} ({e}); falling back to infer()")
        if audios is None:
            audios = [tts.infer(tx, voice=voice) for tx in texts]
        for idx, ((k, text, _v, fx, spk, h), audio) in enumerate(zip(items, audios)):
            for attempt in range(3):  # re-roll truncated / runaway takes
                problem = take_problem(audio, text)
                if not problem:
                    break
                print(f"  {k}: {problem} — re-rolling ({attempt + 1})")
                audio = tts.infer(text, voice=voice)
            if a.keep_raw:
                Path(a.keep_raw).mkdir(parents=True, exist_ok=True)
                tts.save(audio, str(Path(a.keep_raw) / f"{k}.wav"))
            seed = zlib.crc32(k.encode()) & 0xFFFF
            y, sr = post(audio, spk, fx, seed)
            fxc.save_ogg(y, sr, out / f"{k}.ogg", q=3)
            manifest[k] = h
            raw_dur = len(audio) / TTS_SR
            syl = len(re.findall(r"\w+", text))
            rate = syl / max(raw_dur, 1e-3)
            flag = "  <-- check (babble/too fast?)" if rate < 1.8 or rate > 7.5 else ""
            print(f"  {k:24s} {voice:12s} fx={fx:7s} {len(y) / sr:5.2f}s  {rate:4.1f} syl/s{flag}")
            man_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1, sort_keys=True))
    print(f"done in {time.time() - t0:.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
