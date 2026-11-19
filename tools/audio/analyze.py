#!/usr/bin/env python3
"""Quick objective listen-check: duration, rate, peak, LUFS, spectral centroid, band energy,
f0 estimate (voice), loop seam jump. Usage: python3 tools/audio/analyze.py files... [--loop]"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fx_chain as fxc  # noqa: E402

BANDS = [(0, 150), (150, 500), (500, 2000), (2000, 5000), (5000, 20000)]


def info(p):
    o = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=sample_rate,channels:format=duration",
                        "-of", "json", str(p)], capture_output=True, text=True).stdout
    j = json.loads(o)
    s = j["streams"][0]
    return int(s["sample_rate"]), int(s["channels"]), float(j["format"]["duration"])


def f0(x, sr):
    """Median autocorrelation pitch over voiced frames (60–400 Hz)."""
    n = int(0.04 * sr)
    vals = []
    thr = 0.3 * np.max(np.abs(x))
    for i in range(0, len(x) - n, n // 2):
        fr = x[i:i + n] - np.mean(x[i:i + n])
        if np.max(np.abs(fr)) < thr:
            continue
        ac = np.correlate(fr, fr, "full")[n - 1:]
        lo, hi = int(sr / 400), int(sr / 60)
        k = lo + np.argmax(ac[lo:hi])
        if ac[k] > 0.4 * ac[0]:
            vals.append(sr / k)
    return float(np.median(vals)) if vals else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--f0", action="store_true")
    a = ap.parse_args()
    print(f"{'file':34s} {'sr':>5s} ch {'dur':>6s} {'peak':>6s} {'LUFS':>6s} {'cent':>5s}  bands% <150/150-500/.5-2k/2-5k/>5k"
          + ("  seam" if a.loop else "") + ("   f0" if a.f0 else ""))
    for p in a.files:
        sr, ch, dur = info(p)
        x = fxc.load(p, sr)
        pk = 20 * np.log10(np.max(np.abs(x)) + 1e-9)
        lu = fxc.measure_lufs(x, sr)
        X = np.abs(np.fft.rfft(x)) ** 2
        f = np.fft.rfftfreq(len(x), 1 / sr)
        cent = float(np.sum(f * X) / (np.sum(X) + 1e-12))
        tot = np.sum(X) + 1e-12
        bands = "/".join(f"{100 * np.sum(X[(f >= lo) & (f < hi)]) / tot:3.0f}" for lo, hi in BANDS)
        line = f"{Path(p).name[:34]:34s} {sr:5d} {ch:2d} {dur:6.2f} {pk:6.1f} {lu:6.1f} {cent:5.0f}  {bands}"
        if a.loop:
            w = int(0.01 * sr)
            seam = np.sqrt(np.mean((x[-w:] - x[:w]) ** 2)) / (np.sqrt(np.mean(x ** 2)) + 1e-9)
            jump = abs(x[-1] - x[0]) / (np.max(np.abs(x)) + 1e-9)
            line += f"  {seam:4.2f}/{jump:4.2f}"
        if a.f0:
            line += f"  {f0(x, sr):5.0f}"
        print(line)


if __name__ == "__main__":
    main()
