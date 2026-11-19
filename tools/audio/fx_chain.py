#!/usr/bin/env python3
"""Lo-fi audio FX chain + shared DSP helpers (numpy only; ffmpeg for I/O, pitch and loudness).

Importable (synth.py, tts_build.py) and usable as a CLI:

    python3 tools/audio/fx_chain.py in.wav out.ogg --fx entity [--sr 22050] [--lufs -18] [--bits 10] [--seed 1]

FX presets (dialogue `fx` field): none | phone | radio | door | far | entity | whisper
All outputs are mono .ogg (libvorbis). FFT filters are zero-phase; on loops they are circular,
which keeps loop points seamless.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import zlib
from pathlib import Path

import numpy as np

FX_NAMES = ("none", "phone", "radio", "door", "far", "entity", "whisper")
# target loudness (LUFS) per preset — door/far are meant to sound distant
FX_LUFS = {"none": -18.0, "phone": -19.0, "radio": -20.0, "door": -21.0, "far": -23.0,
           "entity": -19.0, "whisper": -22.0}


# ───────────────────────────── I/O ─────────────────────────────
def load(path, sr: int) -> np.ndarray:
    """Decode any audio file to mono float32 at `sr` via ffmpeg."""
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(sr),
                          "-f", "f32le", "-"], check=True, capture_output=True).stdout
    return np.frombuffer(out, dtype=np.float32).copy()


def ffilter(x: np.ndarray, sr: int, af: str, out_sr: int | None = None) -> np.ndarray:
    """Run raw mono float32 through an ffmpeg audio filtergraph."""
    out_sr = out_sr or sr
    p = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "-",
                        "-af", af, "-ac", "1", "-ar", str(out_sr), "-f", "f32le", "-"],
                       input=np.asarray(x, np.float32).tobytes(), check=True, capture_output=True)
    return np.frombuffer(p.stdout, dtype=np.float32).copy()


def resample(x, sr, out_sr):
    if sr == out_sr:
        return x
    return ffilter(x, sr, "aresample=resampler=soxr" if _has_soxr() else "aresample", out_sr)


_SOXR = None


def _has_soxr():
    global _SOXR
    if _SOXR is None:
        try:
            ffilter(np.zeros(100, np.float32), 22050, "aresample=resampler=soxr", 11025)
            _SOXR = True
        except subprocess.CalledProcessError:
            _SOXR = False
    return _SOXR


def measure_lufs(x: np.ndarray, sr: int) -> float:
    """Integrated loudness (EBU R128) via ffmpeg loudnorm analysis. Short clips are padded by repetition."""
    y = x
    if len(y) < sr * 3 and len(y) > 0:  # loudnorm gating needs a few seconds
        y = np.tile(y, int(np.ceil(sr * 3 / len(y))))
    p = subprocess.run(["ffmpeg", "-hide_banner", "-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "-",
                        "-af", "loudnorm=print_format=json", "-f", "null", "-"],
                       input=np.asarray(y, np.float32).tobytes(), capture_output=True)
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", p.stderr.decode("utf8", "replace"), re.S)
    if not m:
        return -70.0
    v = float(json.loads(m.group(0))["input_i"])
    return v if np.isfinite(v) else -70.0


def normalize(x, sr, lufs=None, peak_db=-1.0):
    """Gain to target LUFS (if given), then soft-limit peaks below peak_db."""
    x = np.asarray(x, np.float32)
    if not np.any(x):
        return x
    if lufs is not None:
        cur = measure_lufs(x, sr)
        if cur > -69:
            x = x * (10 ** ((lufs - cur) / 20))
    lim = 10 ** (peak_db / 20)
    pk = np.max(np.abs(x))
    if pk > lim:
        # soft knee: tanh above 70% of the limit, then hard scale
        k = 0.7 * lim
        a = np.abs(x)
        over = a > k
        y = x.copy()
        y[over] = np.sign(x[over]) * (k + (lim - k) * np.tanh((a[over] - k) / (lim - k)))
        x = y
    return x.astype(np.float32)


def peak_normalize(x, peak_db=-1.0):
    pk = np.max(np.abs(x)) if len(x) else 0
    return (x * (10 ** (peak_db / 20) / pk)).astype(np.float32) if pk > 0 else x


def save_ogg(x: np.ndarray, sr: int, path, q: float = 3.0):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.clip(np.asarray(x, np.float32), -1, 1)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(q), "-map_metadata", "-1", str(path)],
                   input=x.tobytes(), check=True)


def save_wav(x, sr, path):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "-",
                    "-c:a", "pcm_s16le", str(path)], input=np.asarray(x, np.float32).tobytes(), check=True)


# ───────────────────────────── DSP ─────────────────────────────
def _bw(f, fc, order, high):
    with np.errstate(divide="ignore"):
        r = (fc / np.maximum(f, 1e-6)) if high else (f / fc)
    return 1.0 / np.sqrt(1.0 + r ** (2 * order))


def filt(x, sr, hp=None, lp=None, order=2, circular=False, pad=None):
    """Zero-phase Butterworth-magnitude HP/LP in the frequency domain.
    circular=True for loops (no padding → wraps seamlessly)."""
    x = np.asarray(x, np.float64)
    n = len(x)
    if not circular:
        pad = pad if pad is not None else min(n, sr)
        x = np.concatenate([x, np.zeros(pad)])
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sr)
    H = np.ones_like(f)
    if hp:
        H *= _bw(f, hp, order, True)
    if lp:
        H *= _bw(f, lp, order, False)
    y = np.fft.irfft(X * H, len(x))
    return y[:n].astype(np.float32)


def bandpass(x, sr, lo, hi, order=2, circular=False):
    return filt(x, sr, hp=lo, lp=hi, order=order, circular=circular)


def peak_eq(x, sr, fc, gain_db, q=1.0, circular=False):
    """Gaussian-shaped (log-frequency) bell EQ."""
    x = np.asarray(x, np.float64)
    n = len(x)
    if not circular:
        x = np.concatenate([x, np.zeros(min(n, sr))])
    X = np.fft.rfft(x)
    f = np.maximum(np.fft.rfftfreq(len(x), 1 / sr), 1.0)
    bw = 1.0 / q
    H = 10 ** (gain_db / 20 * np.exp(-0.5 * (np.log2(f / fc) / (bw / 2)) ** 2))
    return np.fft.irfft(X * H, len(x))[:n].astype(np.float32)


def fftconv(a, b):
    n = len(a) + len(b) - 1
    N = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(a, N) * np.fft.rfft(b, N), N)[:n].astype(np.float32)


def reverb_ir(sr, seconds=1.2, lp=4000, predelay=0.01, seed=0, early=6):
    """Synthetic room IR: sparse early reflections + exponentially decaying filtered noise."""
    rng = np.random.default_rng(seed)
    n = int(sr * seconds)
    t = np.arange(n) / sr
    tail = rng.standard_normal(n) * np.exp(-6.9 * t / seconds)  # -60 dB at `seconds`
    tail = filt(tail, sr, lp=lp, hp=120, order=1)
    ir = np.zeros(n + int(predelay * sr) + 1, np.float32)
    ir[int(predelay * sr):int(predelay * sr) + n] += tail * 0.5
    for i in range(early):
        d = int(sr * (predelay + rng.uniform(0.003, 0.05)))
        ir[d] += rng.uniform(0.2, 0.6) * rng.choice([-1, 1])
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(x, sr, seconds=1.2, wet=0.3, lp=4000, predelay=0.01, seed=0, circular=False):
    ir = reverb_ir(sr, seconds, lp, predelay, seed)
    if circular:  # wrap tail around for loops
        y = fftconv(x, ir)
        w = y[:len(x)].copy()
        tail = y[len(x):]
        w[:len(tail)] += tail[:len(x)]
        y = w
    else:
        y = fftconv(np.concatenate([x, np.zeros(len(ir))]), ir)[:len(x) + len(ir)]
        x = np.concatenate([x, np.zeros(len(ir))])
    return ((1 - wet) * x + wet * y).astype(np.float32)


def bitcrush(x, bits=10, downsample=1):
    q = 2 ** (bits - 1)
    y = np.round(np.asarray(x) * q) / q
    if downsample > 1:
        y = np.repeat(y[::downsample], downsample)[:len(x)]
    return y.astype(np.float32)


def softclip(x, drive=2.0):
    return (np.tanh(np.asarray(x) * drive) / np.tanh(drive)).astype(np.float32)


def fade(x, sr, fin=0.005, fout=0.02):
    x = np.array(x, np.float32)
    a, b = int(fin * sr), int(fout * sr)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def trim_silence(x, sr, thresh_db=-45, keep=0.06):
    a = np.abs(x)
    th = 10 ** (thresh_db / 20) * (a.max() if len(a) else 1)
    idx = np.where(a > th)[0]
    if len(idx) == 0:
        return x
    s = max(0, idx[0] - int(keep * sr))
    e = min(len(x), idx[-1] + int(keep * sr * 2))
    return x[s:e]


def loop_crossfade(x, sr, xf=2.0):
    """Make a seamless loop: fold the last `xf` seconds into the head (equal-power)."""
    n = int(xf * sr)
    if n <= 0 or len(x) <= 2 * n:
        return x
    body = np.array(x[:-n], np.float32)
    tail = x[-n:]
    t = np.linspace(0, np.pi / 2, n)
    body[:n] = body[:n] * np.sin(t) + tail * np.cos(t)
    return body


def noise(n, rng, color="white"):
    w = rng.standard_normal(n)
    if color == "white":
        return w.astype(np.float32)
    X = np.fft.rfft(w)
    f = np.arange(len(X), dtype=np.float64)
    f[0] = 1
    if color == "pink":
        X /= np.sqrt(f)
    elif color == "brown":
        X /= f
    y = np.fft.irfft(X, n)
    return (y / (np.std(y) + 1e-12)).astype(np.float32)


def static_bed(n, sr, rng, level=0.03):
    """Radio/TV static: band-limited noise with crackle pops and slow amplitude wobble."""
    s = bandpass(noise(n, rng), sr, 800, 6000, order=1)
    s /= np.std(s) + 1e-9
    t = np.arange(n) / sr
    wob = 0.6 + 0.4 * np.sin(2 * np.pi * rng.uniform(0.2, 0.7) * t + rng.uniform(0, 6))
    pops = np.zeros(n, np.float32)
    k = rng.integers(0, n, size=max(1, int(n / sr * 25)))
    pops[k] = rng.uniform(-4, 4, size=len(k))
    pops = filt(pops, sr, hp=1000, lp=7000, order=1)
    return (level * (s * wob + pops)).astype(np.float32)


def pitch_shift(x, sr, semitones, formant="shifted"):
    """Pitch shift without changing duration (ffmpeg rubberband, falls back to asetrate+atempo)."""
    ratio = 2 ** (semitones / 12)
    try:
        return ffilter(x, sr, f"rubberband=pitch={ratio:.5f}:formant={formant}:pitchq=quality")
    except subprocess.CalledProcessError:
        tempo = 1 / ratio
        chain = []
        while tempo < 0.5:
            chain.append("atempo=0.5")
            tempo /= 0.5
        chain.append(f"atempo={tempo:.5f}")
        return ffilter(x, sr, f"asetrate={int(sr * ratio)},aresample={sr}," + ",".join(chain))


def flanger(x, sr, depth_ms=3.0, rate=0.25, mix=0.5, fb=0.4):
    """Simple modulated comb (vectorised, feedback approximated with two taps)."""
    n = len(x)
    t = np.arange(n) / sr
    d = (depth_ms / 1000) * sr * (0.5 + 0.5 * np.sin(2 * np.pi * rate * t)) + 1
    idx = np.arange(n) - d
    i0 = np.clip(np.floor(idx).astype(int), 0, n - 1)
    fr = idx - np.floor(idx)
    i1 = np.clip(i0 + 1, 0, n - 1)
    tap = x[i0] * (1 - fr) + x[i1] * fr
    idx2 = np.arange(n) - 2 * d
    j0 = np.clip(np.floor(idx2).astype(int), 0, n - 1)
    tap2 = x[j0]
    return ((1 - mix) * x + mix * (tap + fb * tap2) / (1 + fb)).astype(np.float32)


def stutter_dropout(x, sr, rng, n_stutter=2, n_drop=3):
    """Random stutters (repeat a 50–110 ms grain 2–3×) and dropouts (short gaps)."""
    x = list(np.asarray(x, np.float32))
    y = np.asarray(x, np.float32)
    segs = []
    pos = 0
    L = len(y)
    if L < sr // 2:
        return y
    cuts = sorted(rng.integers(int(0.15 * L), int(0.9 * L), size=n_stutter))
    for c in cuts:
        g = int(rng.uniform(0.05, 0.11) * sr)
        segs.append(y[pos:c])
        grain = fade(y[c:c + g], sr, 0.003, 0.003)
        segs.extend([grain] * int(rng.integers(1, 3)))
        pos = c
    segs.append(y[pos:])
    y = np.concatenate(segs)
    for _ in range(n_drop):
        c = int(rng.integers(int(0.1 * len(y)), int(0.95 * len(y))))
        g = int(rng.uniform(0.03, 0.09) * sr)
        env = np.ones(g, np.float32)
        r = min(g // 3, int(0.004 * sr))
        env[r:g - r] = rng.uniform(0.0, 0.15)
        y[c:c + g] *= env[:len(y[c:c + g])]
    return y


# ───────────────────────────── presets ─────────────────────────────
def apply_fx(x: np.ndarray, sr: int, fx: str, seed: int = 0, out_sr: int = 22050) -> tuple[np.ndarray, int]:
    """x: mono float32 at `sr` (any). Returns (processed, out_sr), NOT loudness-normalised."""
    rng = np.random.default_rng(seed)
    if fx not in FX_NAMES:
        raise ValueError(f"unknown fx '{fx}' (valid: {', '.join(FX_NAMES)})")
    if fx == "entity":  # pitch first at full rate for quality
        x = pitch_shift(x, sr, -5.0)
    x = resample(x, sr, 22050)
    sr = 22050
    x = trim_silence(x, sr)
    x = np.concatenate([np.zeros(int(0.03 * sr), np.float32), x])

    if fx == "none":
        y = filt(x, sr, hp=80, lp=8500, order=2)
        y = bitcrush(y, 12)
    elif fx == "phone":
        y = bandpass(x, sr, 320, 3300, order=4)
        y = peak_eq(y, sr, 1500, 4, q=1.0)
        y = softclip(y / (np.max(np.abs(y)) + 1e-9) * 0.9, drive=2.5)
        y = bitcrush(y, 9)
        y = y + static_bed(len(y), sr, rng, 0.004)
    elif fx == "radio":
        y = resample(x, sr, 11025)
        r = 11025
        y = bandpass(y, r, 400, 2800, order=3)
        y = softclip(y / (np.max(np.abs(y)) + 1e-9) * 0.9, drive=3.0)
        y = bitcrush(y, 8)
        y = y + static_bed(len(y), r, rng, 0.025)
        y = resample(y, r, sr)
    elif fx == "door":
        y = filt(x, sr, hp=90, lp=700, order=3)
        y = peak_eq(y, sr, 220, 4, q=0.8)
        y = reverb(y, sr, seconds=0.45, wet=0.35, lp=1500, predelay=0.004, seed=seed)
    elif fx == "far":
        y = filt(x, sr, hp=220, lp=2600, order=2)
        y = reverb(y, sr, seconds=2.8, wet=0.55, lp=2200, predelay=0.05, seed=seed)
        y = filt(y, sr, lp=3000, order=1)
    elif fx == "whisper":
        y = filt(x, sr, hp=300, lp=5000, order=2)
        y = reverb(y, sr, seconds=1.5, wet=0.4, lp=3000, seed=seed)
    elif fx == "entity":
        dry = filt(x, sr, hp=70, lp=5500, order=2)
        rev = dry[::-1].copy()
        rev = reverb(rev, sr, seconds=1.2, wet=0.6, lp=2500, seed=seed + 1)[:len(dry)]
        y = dry + 0.18 * rev
        y = flanger(y, sr, depth_ms=2.5, rate=0.18, mix=0.45, fb=0.5)
        y = stutter_dropout(y, sr, rng, n_stutter=2, n_drop=2)
        y = softclip(y / (np.max(np.abs(y)) + 1e-9) * 0.8, drive=1.8)
        y = bitcrush(y, 10)
        y = reverb(y, sr, seconds=1.0, wet=0.22, lp=3000, seed=seed + 2)
        y = y + static_bed(len(y), sr, rng, 0.02)
    y = fade(y, sr, 0.004, 0.05)
    if out_sr != sr:
        y = resample(y, sr, out_sr)
    return y.astype(np.float32), out_sr


def process_file(src, dst, fx="none", sr=22050, lufs=None, bits=None, seed=None, q=3.0):
    seed = seed if seed is not None else zlib.crc32(str(src).encode()) & 0xFFFF
    x = load(src, 44100)
    y, osr = apply_fx(x, 44100, fx, seed=seed, out_sr=sr)
    if bits:
        y = bitcrush(y, bits)
    y = normalize(y, osr, FX_LUFS.get(fx, -18.0) if lufs is None else lufs, peak_db=-1.0)
    save_ogg(y, osr, dst, q)
    return len(y) / osr


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--fx", default="none", choices=FX_NAMES)
    ap.add_argument("--sr", type=int, default=22050, help="output rate (22050 or 11025)")
    ap.add_argument("--lufs", type=float, default=None)
    ap.add_argument("--bits", type=int, default=None, help="extra bitcrush (8-12)")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("-q", type=float, default=3.0, help="vorbis quality")
    a = ap.parse_args()
    d = process_file(a.src, a.dst, a.fx, a.sr, a.lufs, a.bits, a.seed, a.q)
    print(f"{a.dst}: {d:.2f}s fx={a.fx}")


if __name__ == "__main__":
    sys.exit(main())
