#!/usr/bin/env python3
"""Builds every sfx / ambience / music file listed in docs/audio_manifest.md.

Sources: CC0 packs in tools/audio/_downloads (run fetch_cc0.py first; missing packs fall back
to synthesised stand-ins), TTS takes in tools/audio/src (tts_specials.py), dialogue voices in
assets/audio/voice (used, reversed and muffled, as crowd/TV murmur), and numpy synthesis.

    python3 -I tools/audio/synth.py            # build everything
    python3 -I tools/audio/synth.py --only shop_bell music_menu
    python3 -I tools/audio/synth.py --list

Loops (amb/music) are rendered circularly: noise is generated in the frequency domain, LFOs
have whole cycles per loop, and every event/reverb tail that runs past the end wraps into the
head — so the loop point is seamless without an audible crossfade.
"""
from __future__ import annotations

import argparse
import glob
import sys
import time
import zlib
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
import fx_chain as fxc  # noqa: E402
from fx_chain import filt, bandpass, peak_eq, reverb, bitcrush, softclip, fade, noise  # noqa: E402

SR = 22050
OUT = REPO / "assets" / "audio"
DL = HERE / "_downloads"
SRC = HERE / "src"
REG: dict[str, tuple[str, callable]] = {}
USED_SOURCES: set[str] = set()


def reg(cat, *names):
    def deco(fn):
        for n in names or (fn.__name__,):
            REG[n] = (cat, fn)
        return fn
    return deco


def rng_for(name):
    return np.random.default_rng(zlib.crc32(name.encode()))


# ═════════════════════════════ generic helpers ═════════════════════════════
def T(n):
    return np.arange(n) / SR


def N(sec):
    return int(round(sec * SR))


def place(buf, x, pos, gain=1.0, wrap=True):
    """Add x into buf at sample pos (wrapping around the end for loops)."""
    n = len(buf)
    pos = int(pos) % n if wrap else int(pos)
    x = np.asarray(x, np.float32) * gain
    if not wrap:
        e = min(n, pos + len(x))
        if pos < n:
            buf[pos:e] += x[:e - pos]
        return buf
    while len(x):
        e = min(n, pos + len(x))
        buf[pos:e] += x[:e - pos]
        x = x[e - pos:]
        pos = 0
    return buf


def mix(*xs):
    """Sum arrays of different lengths (zero-padded to the longest)."""
    n = max(len(x) for x in xs)
    out = np.zeros(n, np.float32)
    for x in xs:
        out[:len(x)] += x
    return out


def lfo(n, cycles, phase=0.0):
    return np.sin(2 * np.pi * cycles * np.arange(n) / n + phase).astype(np.float32)


def smooth_rand(n, rng, kmax=6, floor=0.0):
    """Periodic smooth random curve in [floor,1] (only the first kmax Fourier bins)."""
    X = np.zeros(n // 2 + 1, complex)
    k = np.arange(1, kmax + 1)
    X[1:kmax + 1] = (rng.standard_normal(kmax) + 1j * rng.standard_normal(kmax)) / k ** 0.7
    y = np.fft.irfft(X, n)
    y = (y - y.min()) / (y.max() - y.min() + 1e-12)
    return (floor + (1 - floor) * y).astype(np.float32)


def cnoise(n, rng, color="white"):
    return noise(n, rng, color)  # FFT-based → periodic


def mtof(m, cents=0.0):
    return 440.0 * 2 ** ((m - 69 + cents / 100) / 12)


def osc(freq, n, kind="sine", phase0=0.0):
    """freq: scalar or per-sample array. kind: sine|saw|square|tri."""
    f = np.broadcast_to(np.asarray(freq, np.float64), (n,))
    ph = phase0 + np.cumsum(f) / SR
    ph = ph - np.floor(ph)
    if kind == "sine":
        return np.sin(2 * np.pi * ph).astype(np.float32)
    if kind == "saw":
        return (2 * ph - 1).astype(np.float32)
    if kind == "square":
        return np.where(ph < 0.5, 1.0, -1.0).astype(np.float32)
    if kind == "tri":
        return (4 * np.abs(ph - 0.5) - 1).astype(np.float32)
    raise ValueError(kind)


def expenv(n, tau, attack=0.002):
    t = T(n)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return (a * np.exp(-t / tau)).astype(np.float32)


def adsr(n, a, d, s, r):
    t = T(n)
    dur = n / SR
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = np.clip((dur - t) / max(r, 1e-4), 0, 1)
    return (e * rel).astype(np.float32)


def stretch(x, tempo=1.0, pitch_semis=0.0):
    return fxc.ffilter(x, SR, f"rubberband=tempo={tempo:.4f}:pitch={2 ** (pitch_semis / 12):.5f}:pitchq=quality")


def resample_pitch(x, semis):
    """Tape-style pitch change (changes length)."""
    r = 2 ** (semis / 12)
    idx = np.arange(0, len(x) - 1, r)
    return np.interp(idx, np.arange(len(x)), x).astype(np.float32)


def wow_flutter(x, depth_ms=2.5, wow_cycles=None, flutter_cycles=None, flutter_ms=0.25):
    """Circular tape wow/flutter (whole cycles per loop → seamless)."""
    n = len(x)
    L = n / SR
    wc = wow_cycles or max(1, round(L * 0.45))
    fc = flutter_cycles or max(1, round(L * 5.5))
    d = (depth_ms / 1000 * SR) * (1 + lfo(n, wc)) / 2 + (flutter_ms / 1000 * SR) * (1 + lfo(n, fc, 1.0)) / 2
    idx = np.arange(n) - d
    i0 = np.floor(idx).astype(int)
    fr = idx - i0
    return (x[i0 % n] * (1 - fr) + x[(i0 + 1) % n] * fr).astype(np.float32)


def crackle(n, rng, density=6.0, level=0.05, hiss=0.004):
    """Vinyl crackle: sparse clicks (+ rare pops) and a soft hiss bed — circular."""
    c = np.zeros(n, np.float32)
    k = rng.integers(0, n, size=int(n / SR * density))
    c[k] = rng.standard_normal(len(k)) * rng.uniform(0.2, 1.0, len(k)) ** 2
    pops = rng.integers(0, n, size=max(1, int(n / SR * 0.15)))
    for p in pops:
        place(c, expenv(N(0.004), 0.0012) * rng.uniform(1.5, 3.0), p)
    c = filt(c, SR, hp=700, lp=5500, order=1, circular=True)
    c /= np.max(np.abs(c)) + 1e-9
    h = filt(cnoise(n, rng, "pink"), SR, hp=300, lp=4500, order=1, circular=True)
    return (level * c + hiss * h / (np.std(h) + 1e-9)).astype(np.float32)


def loopify(x, xf=0.0):
    """Ensure a clean loop seam (fallback crossfade if needed)."""
    return fxc.loop_crossfade(x, SR, xf) if xf else x


# ── output ──
def finish_sfx(x, peak_db=-3.0, lp=None, hp=None, bits=None, fin=0.0, fout=0.01, trim=True):
    x = np.asarray(x, np.float32)
    if hp or lp:
        x = filt(x, SR, hp=hp, lp=lp, order=2)
    if trim:
        x = fxc.trim_silence(x, SR, thresh_db=-60, keep=0.005)
    if bits:
        x = bitcrush(x, bits)
    x = fade(x, SR, fin, fout)
    return fxc.peak_normalize(x, peak_db)


def finish_loop(x, lufs=-24.0, lp=None, hp=None, peak_db=-2.0):
    x = np.asarray(x, np.float32)
    if hp or lp:
        x = filt(x, SR, hp=hp, lp=lp, order=2, circular=True)
    x = x - np.mean(x)
    return fxc.normalize(x, SR, lufs, peak_db)


# ── sources ──
def src_path(rel):
    p = DL / rel
    return p if p.exists() else None


def pk(rel, gain=1.0):
    """Load a downloaded pack file (mono, SR) or None. Records it for CREDITS."""
    p = src_path(rel)
    if p is None:
        print(f"    (missing pack file {rel} — using synth fallback)")
        return None
    USED_SOURCES.add(rel)
    return fxc.load(p, SR) * gain


def K(pack, name):
    return f"kenney/{pack}/files/Audio/{name}.ogg"


def tts_src(name):
    p = SRC / f"tts_{name}.ogg"
    return fxc.load(p, SR) if p.exists() else None


def voice_pool():
    files = sorted(glob.glob(str(OUT / "voice" / "*.ogg")))
    return [fxc.load(f, SR) for f in files if "test_" not in f]


# ═════════════════════════════ building blocks ═════════════════════════════
def thump(dur=0.15, f0=70, f1=45, tau=0.06):
    n = N(dur)
    f = f1 + (f0 - f1) * np.exp(-T(n) / 0.03)
    return osc(f, n) * expenv(n, tau, 0.001)


def click(dur=0.012, f=3000, tau=0.002, rng=None):
    n = N(dur)
    x = osc(f, n) * 0.6 + (rng.standard_normal(n) if rng is not None else 0) * 0.4
    return (x * expenv(n, tau, 0.0002)).astype(np.float32)


def stick_slip(dur, rate0, rate1, rng, modes=(380, 870, 1650, 2900), q=25, jitter=0.25):
    """Friction creak: impulse train with varying rate excites resonant modes."""
    n = N(dur)
    r = np.linspace(rate0, rate1, n) * (1 + 0.15 * np.sin(2 * np.pi * rng.uniform(1, 3) * T(n)))
    ph = np.cumsum(r) / SR
    imp = np.zeros(n, np.float32)
    k = np.where(np.diff(np.floor(ph)) > 0)[0]
    imp[k] = rng.uniform(1 - jitter, 1 + jitter, len(k))
    out = np.zeros(n, np.float32)
    for i, m in enumerate(modes):
        bw = m / q
        out += bandpass(imp, SR, m - bw, m + bw, order=2) * (1.0 / (1 + 0.5 * i))
    env = np.sin(np.pi * np.clip(T(n) / dur, 0, 1)) ** 0.6
    return out * env


def modal(freqs, amps, taus, dur, detune_hz=0.0, rng=None):
    n = N(dur)
    t = T(n)
    x = np.zeros(n, np.float32)
    for f, a, tau in zip(freqs, amps, taus):
        x += a * np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
        if detune_hz:
            x += a * 0.5 * np.sin(2 * np.pi * (f + detune_hz) * t + 1.0) * np.exp(-t / tau)
    x *= np.clip(t / 0.0015, 0, 1)
    return x.astype(np.float32)


def bell(f, dur=4.0, bright=1.0):
    ratios = [0.5, 1.0, 1.19, 1.5, 2.0, 2.52, 3.0, 4.07]
    amps = [0.35, 1.0, 0.55, 0.35, 0.45 * bright, 0.25 * bright, 0.15 * bright, 0.1 * bright]
    taus = [2.4, 1.6, 1.1, 0.9, 0.7, 0.45, 0.3, 0.2]
    return modal([f * r for r in ratios], amps, [t * dur / 4 for t in taus], dur, detune_hz=1.3)


def chime_tube(f, dur=3.0):
    return modal([f, f * 2.76, f * 5.40, f * 8.93], [1, 0.5, 0.25, 0.1], [1.6, 0.8, 0.4, 0.2], dur, detune_hz=0.7)


def fm_rhodes(f, dur, vel=0.8, rng=None):
    n = N(dur)
    t = T(n)
    idx = (1.2 + 2.5 * vel) * np.exp(-t / 0.25) + 0.25
    mod = np.sin(2 * np.pi * f * t) * idx
    tine = 0.08 * vel * np.sin(2 * np.pi * f * 7.0 * t) * np.exp(-t / 0.03)
    car = np.sin(2 * np.pi * f * t + mod) + tine
    amp = vel * np.exp(-t / (1.6 if f < 300 else 1.1)) * np.clip(t / 0.003, 0, 1)
    rel = np.clip((dur - t) / 0.08, 0, 1)
    trem = 1 + 0.08 * np.sin(2 * np.pi * 4.5 * t)
    return (car * amp * rel * trem).astype(np.float32)


def pad_saw(freqs, n, rng, voices=3, detune=0.12, lp=1200):
    x = np.zeros(n, np.float32)
    for f in freqs:
        for v in range(voices):
            ff = f * 2 ** ((v - (voices - 1) / 2) * detune / 12)
            x += osc(ff, n, "saw", rng.uniform(0, 1))
    return filt(x / (len(freqs) * voices), SR, lp=lp, order=2, circular=True)


def kick(vel=1.0):
    n = N(0.35)
    f = 48 + 90 * np.exp(-T(n) / 0.035)
    return osc(f, n) * expenv(n, 0.12, 0.001) * vel


def snare(vel=1.0, rng=None):
    n = N(0.25)
    body = osc(185, n) * expenv(n, 0.05) * 0.5
    nz = bandpass(rng.standard_normal(n).astype(np.float32), SR, 1200, 6000) * expenv(n, 0.07) * 1.2
    return (body + nz) * vel


def hat(vel=1.0, rng=None, open_=False):
    n = N(0.25 if open_ else 0.06)
    nz = filt(rng.standard_normal(n).astype(np.float32), SR, hp=6000, order=2)
    return nz * expenv(n, 0.08 if open_ else 0.015) * vel * 0.6


def motorbike(dur=6.0, speed=11.0, dist=4.0, rpm_base=34.0, rng=None, accel=0.25):
    """Single-cylinder scooter passing by with doppler + distance (mono)."""
    pad = 1.0
    n = N(dur + pad)
    t = T(n)
    tc = dur / 2
    # engine at emission time
    fe = rpm_base * (1 + accel * (t / dur)) * (1 + 0.03 * np.sin(2 * np.pi * 0.7 * t))
    ph = np.cumsum(fe) / SR
    frac = ph - np.floor(ph)
    pulse = np.exp(-frac / 0.12) - 0.15  # firing pulses
    pulse = pulse.astype(np.float32) + 0.25 * osc(fe * 2, n, "saw")
    eng = bandpass(pulse, SR, 90, 1400, order=2) + 0.6 * peak_eq(pulse, SR, 420, 9, q=2)
    eng += 0.15 * bandpass(rng.standard_normal(n).astype(np.float32), SR, 300, 2500) * (1 + frac)
    whine = 0.03 * osc(fe * 11, n)
    tyre = 0.12 * filt(rng.standard_normal(n).astype(np.float32), SR, lp=600, hp=80)
    src = (eng + whine + tyre).astype(np.float32)
    # geometry
    x = speed * (t - tc)
    r = np.sqrt(x ** 2 + dist ** 2)
    ta = t + r / 343.0
    out_t = T(N(dur))
    tau = np.interp(out_t, ta, t)  # emission time for each received sample
    y = np.interp(tau, t, src)
    rr = np.interp(tau, t, r)
    near = np.interp(tau, t, (dist / r))
    y_far = filt(y, SR, lp=900, order=2)
    y = (near * y + (1 - near) * y_far) * (dist / rr) ** 0.9
    return fade(y.astype(np.float32), SR, 0.3, 0.3)


def car_horn(dur=0.3, f=(415, 520)):
    n = N(dur)
    x = sum(osc(ff, n, "square") for ff in f) * adsr(n, 0.01, 0.1, 0.9, 0.04)
    return filt(x, SR, hp=200, lp=2200)


def bird_phrase(rng, base=None):
    base = base or rng.uniform(2200, 4200)
    out = []
    for _ in range(int(rng.integers(2, 6))):
        d = rng.uniform(0.04, 0.13)
        n = N(d)
        f = base * (1 + rng.uniform(-0.25, 0.3) * np.linspace(0, 1, n) ** rng.uniform(0.5, 2))
        f *= 1 + 0.04 * np.sin(2 * np.pi * rng.uniform(25, 60) * T(n))
        out.append(osc(f, n) * np.sin(np.pi * np.linspace(0, 1, n)) ** 2)
        out.append(np.zeros(N(rng.uniform(0.02, 0.09)), np.float32))
    return np.concatenate(out)


def babble(n, rng, pool, streams=4, lp=1500, reverse=True, gap=(0.2, 1.5)):
    """Unintelligible murmur from dialogue takes (reversed, overlapped, muffled)."""
    out = np.zeros(n, np.float32)
    if not pool:  # fallback: syllabic noise
        for s in range(streams):
            am = np.clip(lfo(n, int(n / SR * rng.uniform(3.5, 5)), rng.uniform(0, 6)), 0, 1) ** 2
            out += bandpass(cnoise(n, rng, "pink"), SR, 250, 1800, circular=True) * am * smooth_rand(n, rng, 20)
        return out
    for s in range(streams):
        pos = int(rng.integers(0, n))
        covered = 0
        semis = rng.uniform(-2, 2)
        while covered < n:
            v = pool[int(rng.integers(0, len(pool)))]
            v = v[::-1] if reverse and rng.random() < 0.7 else v
            v = resample_pitch(v, semis)
            place(out, v * rng.uniform(0.5, 1.0), pos + covered)
            covered += len(v) + N(rng.uniform(*gap))
    return filt(out, SR, hp=150, lp=lp, order=2, circular=True)


def traffic_bed(n, rng, level=1.0, lp=500):
    rumble = filt(cnoise(n, rng, "brown"), SR, hp=30, lp=lp, order=2, circular=True)
    sw = smooth_rand(n, rng, kmax=max(4, int(n / SR / 6)), floor=0.25)
    hiss = filt(cnoise(n, rng, "pink"), SR, hp=300, lp=1800, circular=True) * 0.25
    return ((rumble / np.std(rumble)) * sw + hiss * sw) * level


def crickets(n, rng, count=4, level=1.0, density=0.85):
    out = np.zeros(n, np.float32)
    L = n / SR
    for c in range(count):
        f0 = rng.uniform(3600, 5200)
        prate = rng.uniform(25, 45)
        npulse = int(rng.integers(2, 5))
        nchirp = int(round(L / rng.uniform(0.45, 0.9)))
        period = n / nchirp
        pl = N(0.6 / prate)
        pshape = np.sin(np.pi * np.linspace(0, 1, pl)) ** 2
        env = np.zeros(n, np.float32)
        gain = smooth_rand(n, rng, kmax=5, floor=0.0)
        for i in range(nchirp):
            if rng.random() > density:
                continue
            st = int(i * period + rng.uniform(-0.01, 0.01) * SR)
            for p in range(npulse):
                place(env, pshape * rng.uniform(0.7, 1.0), st + int(p * SR / prate))
        car = osc(f0 * (1 + 0.003 * lfo(n, 7)), n) + 0.05 * osc(f0 * 2, n)
        out += car * env * (0.35 + 0.65 * gain) * rng.uniform(0.4, 1.0)
    return out * level


def wind(n, rng, level=1.0, lowness=1.0):
    lo = filt(cnoise(n, rng, "pink"), SR, hp=60, lp=350 * lowness, circular=True)
    mid = bandpass(cnoise(n, rng, "pink"), SR, 300, 1200 * lowness, circular=True)
    g1 = smooth_rand(n, rng, kmax=max(3, int(n / SR / 8)), floor=0.2)
    g2 = smooth_rand(n, rng, kmax=max(4, int(n / SR / 4)), floor=0.0) ** 2
    y = lo / np.std(lo) * g1 + 0.5 * mid / np.std(mid) * g2 * g1
    return y * level


def leaves(n, rng, level=1.0):
    grains = np.zeros(n, np.float32)
    k = rng.integers(0, n, size=int(n / SR * 120))
    grains[k] = rng.uniform(0, 1, len(k))
    env = filt(grains, SR, lp=30, circular=True)
    env = np.clip(env / (env.max() + 1e-9), 0, 1)
    nz = bandpass(cnoise(n, rng), SR, 1500, 5000, order=1, circular=True)
    gust = smooth_rand(n, rng, kmax=max(3, int(n / SR / 6)), floor=0.0) ** 2
    return nz / np.std(nz) * env * gust * level


def mains_hum(n, f=100.0, harmonics=18, tilt=0.75, rng=None, buzz=0.3):
    t = T(n)
    x = np.zeros(n, np.float32)
    for h in range(1, harmonics + 1):
        x += (tilt ** (h - 1)) * np.sin(2 * np.pi * f * h * t + (rng.uniform(0, 6) if rng is not None else 0))
    b = softclip(np.sin(2 * np.pi * f * t) * 4, 3.0)
    b = bandpass(b, SR, 900, 4000, circular=True)
    return (x / harmonics * 2 + buzz * b).astype(np.float32)


def fridge(n, rng):
    t = T(n)
    hum = (0.3 * np.sin(2 * np.pi * 50 * t) + 0.4 * np.sin(2 * np.pi * 100 * t) + 0.25 * np.sin(2 * np.pi * 150 * t)
           + 0.18 * np.sin(2 * np.pi * 200 * t) + 0.1 * np.sin(2 * np.pi * 300 * t))
    whine = 0.03 * np.sin(2 * np.pi * 412 * t + 0.3 * lfo(n, 23))
    rattle = bandpass(cnoise(n, rng), SR, 600, 2500, circular=True) * (0.5 + 0.5 * np.sin(2 * np.pi * 100 * t)) ** 4
    rattle *= smooth_rand(n, rng, kmax=12) ** 3 * 0.25
    fan = filt(cnoise(n, rng, "pink"), SR, hp=150, lp=1200, circular=True) * 0.3
    wob = 1 + 0.06 * smooth_rand(n, rng, kmax=8)
    return ((hum + whine) * wob + rattle + fan).astype(np.float32)


whisperize = fxc.whisperize


# ═════════════════════════════ SFX ═════════════════════════════
def _fallback_step(rng, bright=1.0):
    n = N(0.18)
    x = rng.standard_normal(n).astype(np.float32) * expenv(n, 0.03)
    return filt(x, SR, hp=80, lp=1500 * bright) + thump(0.12, 90, 60, 0.03) * 0.6


@reg("sfx", *[f"footstep_concrete_{i}" for i in range(1, 5)])
def footstep_concrete(name):
    i = int(name[-1]) - 1
    x = pk(K("impact-sounds", f"footstep_concrete_00{i}"))
    x = _fallback_step(rng_for(name)) if x is None else x
    x = filt(x, SR, hp=60, lp=6000)
    return finish_sfx(reverb(x, SR, 0.5, 0.08, lp=3000, seed=i), -6, bits=11)


@reg("sfx", *[f"footstep_tile_{i}" for i in range(1, 5)])
def footstep_tile(name):
    i = int(name[-1])
    rng = rng_for(name)
    x = pk(K("impact-sounds", f"footstep_concrete_00{i}"))
    x = _fallback_step(rng, 2) if x is None else x
    x = filt(x, SR, hp=150)
    x = peak_eq(x, SR, 2600, 6, q=0.8)
    c = click(0.015, rng.uniform(2800, 3600), 0.0025, rng) * 0.25 * np.max(np.abs(x))
    x = place(np.concatenate([x, np.zeros(N(0.05))]), c, N(0.002), wrap=False)
    return finish_sfx(reverb(x, SR, 0.45, 0.16, lp=6000, predelay=0.006, seed=i), -6, bits=11)


@reg("sfx", *[f"footstep_wood_{i}" for i in range(1, 5)])
def footstep_wood(name):
    i = int(name[-1]) - 1
    rng = rng_for(name)
    x = pk(K("impact-sounds", f"footstep_wood_00{i}"))
    x = _fallback_step(rng, 0.8) if x is None else x
    x = filt(x, SR, hp=60, lp=5000)
    if i in (1, 3):  # old floor: a little board creak
        cr = stick_slip(0.22, 140, 90, rng, modes=(520, 1100, 2100), q=18) * 0.25
        x = place(np.concatenate([x, np.zeros(N(0.25))]), cr / (np.max(np.abs(cr)) + 1e-9) * np.max(np.abs(x)) * 0.3, N(0.03), wrap=False)
    return finish_sfx(reverb(x, SR, 0.5, 0.1, lp=3000, seed=i), -6, bits=11)


@reg("sfx", "footstep_stiff_1", "footstep_stiff_2")
def footstep_stiff(name):
    i = int(name[-1])
    rng = rng_for(name)
    x = pk(K("impact-sounds", "footstep_concrete_004" if i == 1 else "footstep_wood_004"))
    x = _fallback_step(rng) if x is None else x
    x = resample_pitch(x, -3)
    x = np.concatenate([x, np.zeros(N(0.2))])
    x = place(x, thump(0.12, 110, 70, 0.035) * np.max(np.abs(x)) * 0.45, 0, wrap=False)
    x = filt(x, SR, hp=70, lp=3500)
    return finish_sfx(reverb(x, SR, 0.9, 0.22, lp=2000, seed=i), -4, bits=10)


@reg("sfx", "breath_heavy")
def breath_heavy(name):
    x = pk("oga/breathing-tired/breathing tired.wav")
    if x is None:
        return _synth_breaths(rng_for(name), 2.8, 0.7)
    x = fxc.trim_silence(x, SR)[:N(3.0)]
    return finish_sfx(filt(x, SR, hp=90, lp=7000), -4, fout=0.3)


def _synth_breaths(rng, dur, period):
    n = N(dur)
    out = np.zeros(n, np.float32)
    t = 0.0
    while t < dur - 0.3:
        d = period * rng.uniform(0.4, 0.6)
        m = N(d)
        e = np.sin(np.pi * np.linspace(0, 1, m)) ** 1.5 * (1 + 0.3 * rng.standard_normal(m) * 0.1)
        b = bandpass(rng.standard_normal(m).astype(np.float32), SR, 500, 3500) * e
        place(out, b * rng.uniform(0.6, 1), N(t), wrap=False)
        t += period * rng.uniform(0.45, 0.6)
    return finish_sfx(out, -6)


@reg("sfx", "breath_scared")
def breath_scared(name):
    x = pk("oga/horror-breathing/files/horrorbreathing/horrorbreathing.wav")
    if x is None:
        return _synth_breaths(rng_for(name), 2.5, 0.45)
    x = fxc.trim_silence(x, SR)[:N(3.2)]
    trem = 1 + 0.25 * np.sin(2 * np.pi * 7 * T(len(x)))  # shaky
    return finish_sfx(filt(x * trem, SR, hp=220, lp=7000, order=4), -5, fout=0.4)


@reg("sfx", "heartbeat")
def heartbeat(name):
    n = N(1.0)  # 60 bpm, exact loop
    out = np.zeros(n, np.float32)
    lub = mix(thump(0.16, 62, 40, 0.05), 0.45 * thump(0.06, 160, 110, 0.015))
    dub = mix(thump(0.13, 75, 48, 0.04) * 0.7, 0.3 * thump(0.05, 180, 120, 0.012))
    place(out, lub, 0)
    place(out, dub, N(0.29))
    out = filt(out, SR, hp=30, lp=700, circular=True)
    return fxc.peak_normalize(out - np.mean(out), -3)


def _creak_long(rng, dur, r0, r1, modes=(330, 760, 1480, 2600)):
    x = stick_slip(dur, r0, r1, rng, modes=modes, q=22)
    return x / (np.max(np.abs(x)) + 1e-9)


@reg("sfx", "door_open_creak")
def door_open_creak(name):
    rng = rng_for(name)
    syn = _creak_long(rng, 2.0, 70, 160) * 0.8
    c = pk(K("rpg-audio", "creak2"))
    x = np.zeros(N(2.3), np.float32)
    place(x, syn, N(0.08), wrap=False)
    if c is not None:
        cs = stretch(c, 0.45, -3)
        place(x, cs / (np.max(np.abs(cs)) + 1e-9) * 0.7, N(0.05), wrap=False)
    lat = pk(K("rpg-audio", "metalLatch"))
    if lat is not None:
        place(x, lat / (np.max(np.abs(lat)) + 1e-9) * 0.5, 0, wrap=False)
    x = filt(x, SR, hp=80, lp=5000)
    return finish_sfx(reverb(x, SR, 0.8, 0.2, lp=3000, seed=3), -4, bits=11, fout=0.15)


@reg("sfx", "door_close")
def door_close(name):
    x = pk(K("rpg-audio", "doorClose_4"))
    x = thump(0.3, 80, 50, 0.08) if x is None else x
    x = np.concatenate([x, np.zeros(N(0.3))])
    place(x, thump(0.25, 70, 45, 0.07) * 0.6 * np.max(np.abs(x)), 0, wrap=False)
    return finish_sfx(reverb(filt(x, SR, hp=40, lp=4500), SR, 0.7, 0.2, lp=2500, seed=4), -3, bits=11)


@reg("sfx", "door_lock")
def door_lock(name):
    rng = rng_for(name)
    a = pk(K("rpg-audio", "metalLatch"))
    b = pk(K("rpg-audio", "metalClick"))
    x = np.zeros(N(0.6), np.float32)
    if a is None or b is None:
        place(x, click(0.03, 1800, 0.006, rng), 0, wrap=False)
        place(x, click(0.04, 1300, 0.01, rng), N(0.18), wrap=False)
    else:
        place(x, b * 0.7, 0, wrap=False)
        place(x, a, N(0.14), wrap=False)
    return finish_sfx(reverb(filt(x, SR, hp=150, lp=6000), SR, 0.4, 0.12, seed=5), -5, bits=11)


@reg("sfx", "door_unlock")
def door_unlock(name):
    rng = rng_for(name)
    x = pk("oga/100-cc0-metal-and-wood-sfx/files/lock_open_01.ogg")
    if x is None:
        x = np.zeros(N(0.6), np.float32)
        place(x, click(0.04, 1300, 0.01, rng), 0, wrap=False)
        place(x, click(0.03, 1900, 0.006, rng), N(0.25), wrap=False)
    return finish_sfx(reverb(filt(x, SR, hp=150, lp=6000), SR, 0.4, 0.12, seed=6), -5, bits=11)


def _knock(rng, heavy=False):
    srcs = ["wood_hit_07", "wood_hit_08", "wood_hit_09"] if not heavy else ["wood_slam_04", "wood_hit_09"]
    x = pk(f"oga/100-cc0-metal-and-wood-sfx/files/{srcs[int(rng.integers(0, len(srcs)))]}.ogg")
    if x is None:
        x = thump(0.2, 180, 120, 0.03)
    if heavy:
        x = resample_pitch(x, -3)
        x = np.concatenate([x, np.zeros(N(0.1))])
        place(x, thump(0.18, 90, 55, 0.05) * np.max(np.abs(x)) * 0.8, 0, wrap=False)
    return x / (np.max(np.abs(x)) + 1e-9)


@reg("sfx", "door_knock_3")
def door_knock_3(name):
    rng = rng_for(name)
    x = np.zeros(N(1.2), np.float32)
    t = 0.0
    for i in range(3):
        place(x, _knock(rng) * rng.uniform(0.75, 1.0), N(t), wrap=False)
        t += rng.uniform(0.2, 0.27)
    x = filt(x, SR, hp=60, lp=4000)
    return finish_sfx(reverb(x, SR, 0.5, 0.18, lp=2500, seed=7), -3, bits=11)


@reg("sfx", "door_knock_slow")
def door_knock_slow(name):
    rng = rng_for(name)
    k = _knock(rng, heavy=True)  # the SAME knock, evenly spaced: wrong
    x = np.zeros(N(4.6), np.float32)
    for i in range(4):
        place(x, k, N(i * 1.1), wrap=False)
    x = filt(x, SR, hp=40, lp=2500)
    return finish_sfx(reverb(x, SR, 1.2, 0.25, lp=1800, seed=8), -2, bits=10, fout=0.3)


@reg("sfx", "door_handle_rattle")
def door_handle_rattle(name):
    rng = rng_for(name)
    a = pk(K("rpg-audio", "metalLatch"))
    b = pk(K("rpg-audio", "metalClick"))
    grains = [g for g in (a, b) if g is not None] or [click(0.03, 1500, 0.006, rng)]
    x = np.zeros(N(1.6), np.float32)
    t = 0.0
    while t < 1.35:
        g = grains[int(rng.integers(0, len(grains)))]
        g = resample_pitch(g, rng.uniform(-3, 2))
        place(x, g * rng.uniform(0.4, 1.0), N(t), wrap=False)
        t += rng.uniform(0.06, 0.16) if (t % 0.6) < 0.4 else rng.uniform(0.18, 0.3)
    x = filt(x, SR, hp=200, lp=5000)
    return finish_sfx(reverb(x, SR, 0.4, 0.15, seed=9), -4, bits=11)


@reg("sfx", "shop_bell")
def shop_bell(name):
    # cheap electronic "ding-dong" — two square-ish tones through a tiny speaker
    x = np.zeros(N(2.0), np.float32)
    for i, (f, st) in enumerate([(mtof(76, -12), 0.0), (mtof(72, -12), 0.42)]):
        n = N(1.5)
        tone = osc(f, n) + 0.3 * osc(f * 2, n) + 0.12 * osc(f, n, "square")
        place(x, tone * expenv(n, 0.55, 0.004), N(st), wrap=False)
    x = bandpass(x, SR, 450, 5000, order=2)
    x = softclip(x * 1.2, 1.5)
    return finish_sfx(reverb(x, SR, 0.6, 0.12, lp=5000, seed=10), -5, bits=8, fout=0.2)


@reg("sfx", "scanner_beep")
def scanner_beep(name):
    n = N(0.11)
    x = (osc(2350, n, "square") * 0.6 + osc(2350, n) * 0.4) * adsr(n, 0.003, 0.05, 0.85, 0.01)
    x = bandpass(x, SR, 600, 6000)
    return finish_sfx(np.concatenate([x, np.zeros(N(0.02))]), -9, bits=8, trim=False)


@reg("sfx", "register_open")
def register_open(name):
    rng = rng_for(name)
    x = np.zeros(N(1.3), np.float32)
    m = pk("oga/100-cc0-metal-and-wood-sfx/files/metal_open_01.ogg")
    if m is not None:
        place(x, m / (np.max(np.abs(m)) + 1e-9), N(0.05), wrap=False)
    else:
        slide = filt(rng.standard_normal(N(0.35)).astype(np.float32), SR, hp=800, lp=4000) * adsr(N(0.35), 0.02, 0.1, 0.6, 0.1)
        place(x, slide * 0.5, N(0.05), wrap=False)
        place(x, thump(0.12, 160, 110, 0.03), N(0.38), wrap=False)
    ding = bell(1750, 1.1, 0.6) * 0.35
    place(x, ding, 0, wrap=False)
    return finish_sfx(reverb(filt(x, SR, hp=100, lp=6500), SR, 0.4, 0.1, seed=11), -4, bits=11)


@reg("sfx", "item_pickup")
def item_pickup(name):
    x = pk(K("rpg-audio", "handleSmallLeather"))
    x = filt(np.random.default_rng(1).standard_normal(N(0.15)).astype(np.float32), SR, hp=500, lp=3000) * expenv(N(0.15), 0.04) if x is None else x
    return finish_sfx(filt(x, SR, hp=120, lp=6000), -8, bits=11)


@reg("sfx", "item_drop")
def item_drop(name):
    x = pk(K("impact-sounds", "impactGeneric_light_002"))
    x = thump(0.15, 220, 130, 0.03) if x is None else x
    return finish_sfx(reverb(filt(x, SR, hp=80, lp=5500), SR, 0.4, 0.1, seed=12), -5, bits=11)


@reg("sfx", "can_place")
def can_place(name):
    x = pk(K("impact-sounds", "impactTin_medium_001"))
    x = modal([1200, 2650, 4100], [1, .5, .3], [0.05, 0.03, 0.02], 0.3) if x is None else x
    return finish_sfx(reverb(filt(x, SR, hp=150, lp=7000), SR, 0.35, 0.1, seed=13), -6, bits=11)


@reg("sfx", "box_open")
def box_open(name):
    rng = rng_for(name)
    x = np.zeros(N(1.0), np.float32)
    for i in range(2):  # two flaps: cardboard = papery noise + low flap thump
        m = N(0.28)
        flap = bandpass(rng.standard_normal(m).astype(np.float32), SR, 400, 3500, order=1) * adsr(m, 0.03, 0.08, 0.4, 0.12)
        flap *= 1 + 0.5 * rng.standard_normal(m) * 0.2
        th = np.zeros(m, np.float32)
        place(th, thump(0.1, 120, 80, 0.02), 0, wrap=False)
        place(x, flap * 0.5 + th * 0.3, N(0.05 + i * 0.33), wrap=False)
    b = pk(K("rpg-audio", "bookOpen"))
    if b is not None:
        place(x, resample_pitch(b, -2) * 0.4, N(0.02), wrap=False)
    return finish_sfx(filt(x, SR, hp=90, lp=5000), -6, bits=11)


@reg("sfx", "mop_squeak")
def mop_squeak(name):
    rng = rng_for(name)
    n = N(0.9)
    swish = bandpass(rng.standard_normal(n).astype(np.float32), SR, 300, 2500, order=1) * np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
    wet = filt(rng.standard_normal(n).astype(np.float32), SR, hp=1500, lp=6000) * (rng.random(n) > 0.995) * 3
    f = 950 + 500 * np.sin(np.pi * np.linspace(0.1, 0.9, N(0.25)))
    sq = osc(f, N(0.25), "tri") * np.sin(np.pi * np.linspace(0, 1, N(0.25)))
    sq = bandpass(sq, SR, 600, 3500)
    x = swish * 0.6 + filt(wet, SR, lp=5000) * 0.1
    place(x, sq * 0.35, N(0.45), wrap=False)
    s = pk("oga/100-cc0-metal-and-wood-sfx/files/wood_squeak_01.ogg")
    if s is not None:
        place(x, resample_pitch(s, 5) * 0.4 / (np.max(np.abs(s)) + 1e-9), N(0.2), wrap=False)
    return finish_sfx(x, -7, bits=11, fin=0.02, fout=0.1)


@reg("sfx", "water_boil")
def water_boil(name):
    x = pk("oga/boiling-water-loops/cooking_without_cover_01.ogg")
    if x is None:
        rng = rng_for(name)
        n = N(3.0)
        x = np.zeros(n, np.float32)
        for _ in range(140):
            m = N(rng.uniform(0.01, 0.04))
            f = rng.uniform(300, 1400) * np.linspace(1, 1.6, m)
            place(x, osc(f, m) * expenv(m, 0.01) * rng.uniform(0.2, 1), int(rng.integers(0, n)))
        x += 0.2 * filt(cnoise(n, rng, "pink"), SR, hp=200, lp=2500, circular=True)
        return fxc.peak_normalize(x, -6)
    seg = x[N(2.0):N(2.0) + N(3.6)]
    seg = fxc.loop_crossfade(seg, SR, 0.6)  # → 3.0 s seamless loop
    seg = filt(seg, SR, hp=80, lp=7000, circular=True)
    return fxc.normalize(seg, SR, -26, -6)


@reg("sfx", "stove_click")
def stove_click(name):
    rng = rng_for(name)
    x = np.zeros(N(1.6), np.float32)
    c = pk(K("rpg-audio", "metalClick"))
    for i in range(3):
        g = click(0.02, 3200, 0.003, rng) if c is None else resample_pitch(c[:N(0.12)], 4)
        place(x, g * 0.6, N(i * 0.11), wrap=False)
    m = N(1.3)
    whoosh = bandpass(rng.standard_normal(m).astype(np.float32), SR, 150, 1400, order=1) * adsr(m, 0.06, 0.25, 0.35, 0.5)
    whoosh += 0.4 * filt(rng.standard_normal(m).astype(np.float32), SR, lp=250) * adsr(m, 0.02, 0.15, 0.3, 0.5)
    place(x, whoosh * 0.7, N(0.26), wrap=False)
    return finish_sfx(filt(x, SR, hp=60, lp=6000), -5, bits=11, fout=0.3)


@reg("sfx", "phone_vibrate")
def phone_vibrate(name):
    rng = rng_for(name)
    x = np.zeros(N(1.25), np.float32)
    for st in (0.0, 0.62):
        n = N(0.42)
        m = osc(165 + 5 * np.sin(2 * np.pi * 9 * T(n)), n, "square")
        rattle = softclip(m * 3, 3) * (rng.random(n) > 0.6)
        b = filt(m, SR, lp=900) + 0.25 * bandpass(rattle.astype(np.float32), SR, 1500, 5000)
        place(x, b * adsr(n, 0.02, 0.1, 0.9, 0.04), N(st), wrap=False)
    return finish_sfx(x, -6, bits=11, trim=False)


def _kenney_ui(pack, nm, semis=0.0, lp=6000, bits=10, peak=-10):
    x = pk(K(pack, nm))
    if x is None:
        x = click(0.03, 1500, 0.006, np.random.default_rng(2))
    if semis:
        x = resample_pitch(x, semis)
    return finish_sfx(filt(x, SR, hp=150, lp=lp), peak, bits=bits)


@reg("sfx", "phone_tap")
def phone_tap(name):
    return _kenney_ui("interface-sounds", "tick_002", -2, 5000, 10, -12)


@reg("sfx", "phone_open")
def phone_open(name):
    return _kenney_ui("interface-sounds", "toggle_001", -1, 6000, 10, -10)


@reg("sfx", "flashlight_click")
def flashlight_click(name):
    return _kenney_ui("ui-audio", "switch3", -3, 6000, 11, -8)


@reg("sfx", "light_switch")
def light_switch(name):
    x = pk(K("ui-audio", "switch20"))
    x = click(0.03, 1200, 0.006, rng_for(name)) if x is None else resample_pitch(x, -5)
    x = np.concatenate([x, np.zeros(N(0.1))])
    place(x, thump(0.06, 160, 110, 0.012) * 0.4 * np.max(np.abs(x)), 0, wrap=False)
    return finish_sfx(reverb(filt(x, SR, hp=80, lp=5000), SR, 0.3, 0.12, seed=14), -7, bits=11)


@reg("sfx", "fan_click")
def fan_click(name):
    return _kenney_ui("ui-audio", "switch10", -4, 5000, 11, -8)


@reg("sfx", "page_turn")
def page_turn(name):
    x = pk("oga/10-book-page-flips/files/book_flip.3.ogg")
    if x is None:
        x = pk(K("rpg-audio", "bookFlip1"))
    if x is None:
        n = N(0.4)
        x = bandpass(rng_for(name).standard_normal(n).astype(np.float32), SR, 800, 5000) * adsr(n, 0.05, 0.1, 0.5, 0.15)
    return finish_sfx(filt(x, SR, hp=150, lp=7000), -8, bits=11)


@reg("sfx", "ui_move")
def ui_move(name):
    return _kenney_ui("interface-sounds", "tick_001", -3, 4500, 8, -14)


@reg("sfx", "ui_select")
def ui_select(name):
    return _kenney_ui("interface-sounds", "select_002", -4, 4500, 8, -11)


@reg("sfx", "ui_back")
def ui_back(name):
    return _kenney_ui("interface-sounds", "back_002", -4, 4500, 8, -12)


@reg("sfx", "fluorescent_flicker")
def fluorescent_flicker(name):
    rng = rng_for(name)
    n = N(1.5)
    hum = mains_hum(n, 100, 14, 0.8, rng, buzz=0.8)
    gate = np.zeros(n, np.float32)
    t = 0.0
    on = True
    while t < 1.5:
        d = rng.uniform(0.02, 0.12) if on else rng.uniform(0.03, 0.18)
        if on:
            gate[N(t):N(t + d)] = rng.uniform(0.5, 1.0)
        t += d
        on = not on
    gate = filt(gate, SR, lp=180)
    x = hum * gate
    ticks = np.zeros(n, np.float32)
    for k in np.where(np.abs(np.diff(gate)) > 0.004)[0][::40]:
        place(ticks, click(0.01, rng.uniform(2000, 4000), 0.0015, rng) * rng.uniform(0.3, 0.9), k, wrap=False)
    x = x + 0.6 * ticks
    return finish_sfx(x, -8, lp=7000, bits=10, trim=False)


@reg("sfx", "static_burst")
def static_burst(name):
    rng = rng_for(name)
    n = N(1.0)
    w = rng.standard_normal(n).astype(np.float32)
    s = bandpass(w, SR, 500, 7500, order=1)
    am = (rng.random(n // 200 + 1) > 0.25).repeat(200)[:n].astype(np.float32)
    am = 0.5 + 0.5 * filt(am, SR, lp=400)
    buzz = 0.3 * softclip(osc(59.94 * 2, n, "square") * 0.5, 2) * (rng.random() + 0.5)
    x = softclip((s * am + bandpass(buzz, SR, 200, 3000)) * 2.2, 2.5)
    x *= adsr(n, 0.004, 0.2, 0.8, 0.12)
    return finish_sfx(x, -3, bits=7, trim=False)


@reg("sfx", "jumpscare_sting")
def jumpscare_sting(name):
    rng = rng_for(name)
    dur = 2.6
    n = N(dur)
    pre = N(0.22)
    x = np.zeros(n, np.float32)
    # reversed swell into the hit
    sw = reverb(rng.standard_normal(N(0.5)).astype(np.float32) * expenv(N(0.5), 0.05), SR, 0.8, 0.9, lp=3000, seed=1)
    sw = sw[::-1][-pre:] if len(sw) >= pre else sw[::-1]
    place(x, sw / (np.max(np.abs(sw)) + 1e-9) * 0.5, 0, wrap=False)
    m = n - pre
    t = T(m)
    env = np.exp(-t / 0.55) * np.clip(t / 0.003, 0, 1)
    cl = sum(osc(f * (1 - 0.06 * t / dur), m, "saw") for f in (55.0, 58.3, 82.4, 87.3, 116.5))
    cl = softclip(filt(cl, SR, lp=1800) * 2.5, 3)
    nz = softclip(bandpass(rng.standard_normal(m).astype(np.float32), SR, 300, 6000) * 3, 3)
    scrape = bandpass(rng.standard_normal(m).astype(np.float32), SR, 1800, 4200, order=3)
    scrape = fxc.flanger(scrape, SR, depth_ms=4, rate=3.0, mix=0.7, fb=0.6) * np.exp(-t / 0.3)
    sub = osc(45 * np.exp(-t / 1.5) + 28, m) * np.exp(-t / 0.9)
    cl = filt(cl, SR, hp=90)
    hit = (0.8 * cl * env + 0.6 * nz * np.exp(-t / 0.18) + 0.7 * scrape + 0.3 * sub)
    place(x, hit, pre, wrap=False)
    x = reverb(x, SR, 1.4, 0.25, lp=3500, seed=15)
    return finish_sfx(x, -0.5, bits=9, fout=0.4, trim=False)


@reg("sfx", "stinger_low")
def stinger_low(name):
    rng = rng_for(name)
    n = N(4.0)
    t = T(n)
    sub = osc(48 - 12 * (1 - np.exp(-t / 1.0)), n) * np.exp(-t / 1.4) * np.clip(t / 0.01, 0, 1)
    low = sum(fm_rhodes(mtof(m, c), 4.0, 0.9) for m, c in ((33, 0), (34, -20), (40, 0), (46, -35)))
    sw = reverb(rng.standard_normal(N(0.6)).astype(np.float32) * expenv(N(0.6), 0.1), SR, 1.0, 0.95, lp=1500, seed=2)[::-1]
    x = np.zeros(n + N(0.5), np.float32)
    place(x, filt(sw, SR, lp=1500) / (np.max(np.abs(sw)) + 1e-9) * 0.25, 0, wrap=False)
    place(x, sub * 1.0 + filt(low, SR, lp=1200) * 0.5, N(0.5) - N(0.02), wrap=False)
    x = reverb(x, SR, 2.5, 0.35, lp=1500, seed=16)[:N(6.0)]
    return finish_sfx(x, -2, bits=11, fout=1.2, trim=False)


@reg("sfx", "entity_whisper")
def entity_whisper(name):
    rng = rng_for(name)
    takes = [tts_src(k) for k in ("wh_1", "wh_2", "wh_3")]
    takes = [t for t in takes if t is not None]
    dur = 5.0
    x = np.zeros(N(dur), np.float32)
    if takes:
        for i, tk in enumerate(takes):
            w = whisperize(tk)
            if i != 1:
                w = w[::-1]
            w = fxc.pitch_shift(w, SR, [-5, -3, -7][i % 3], formant="shifted")
            w = filt(w, SR, hp=250, lp=5000)
            w = w / (np.max(np.abs(w)) + 1e-9)
            place(x, w * [1.0, 0.7, 0.8][i % 3], N(i * 0.9), wrap=False)
    else:  # filtered-noise formants
        n = N(dur)
        for f1, f2 in ((700, 1200), (400, 2200), (550, 1700)):
            nz = rng.standard_normal(n).astype(np.float32)
            x += (bandpass(nz, SR, f1 * 0.85, f1 * 1.15) + 0.6 * bandpass(nz, SR, f2 * 0.9, f2 * 1.1)) * smooth_rand(n, rng, 30) ** 2
    x = fxc.flanger(x, SR, 3.0, 0.15, 0.4, 0.4)
    x = reverb(x, SR, 2.0, 0.45, lp=3500, seed=17)[:N(dur + 1.0)]
    return finish_sfx(x, -6, bits=10, fin=0.3, fout=0.8, trim=False)


@reg("sfx", "glass_tap")
def glass_tap(name):
    rng = rng_for(name)
    x = np.zeros(N(1.3), np.float32)
    for i in range(3):
        g = pk(K("impact-sounds", f"impactGlass_light_00{i}"))
        if g is None:
            g = modal([2100, 3900, 5600], [1, .5, .3], [0.03, 0.02, 0.015], 0.25)
        g = filt(g, SR, hp=200, lp=6000)
        place(x, g / (np.max(np.abs(g)) + 1e-9) * rng.uniform(0.7, 1), N(i * rng.uniform(0.28, 0.33)), wrap=False)
    return finish_sfx(reverb(x, SR, 0.5, 0.12, seed=18), -4, bits=11)


@reg("sfx", "motorbike_pass")
def motorbike_pass(name):
    x = motorbike(5.0, 12, 3.5, 36, rng_for(name))
    return finish_sfx(filt(x, SR, hp=50, lp=6000), -3, bits=11, fin=0.4, fout=0.6, trim=False)


@reg("sfx", "dog_bark_far")
def dog_bark_far(name):
    x = pk("oga/dog-barking-mono/dog_barking_mono.wav")
    if x is None:
        rng = rng_for(name)
        x = np.zeros(N(1.5), np.float32)
        for i in range(2):
            m = N(0.16)
            f = 520 * np.exp(-T(m) / 0.2)
            b = osc(f, m, "saw") * expenv(m, 0.06, 0.01)
            place(x, bandpass(b, SR, 400, 2200), N(i * 0.4), wrap=False)
    y = fxc.apply_fx(x, SR, "far", seed=3, out_sr=SR)[0]
    return finish_sfx(filt(y, SR, lp=1800), -10, bits=11, fout=0.5)


@reg("sfx", "match_strike")
def match_strike(name):
    rng = rng_for(name)
    x = np.zeros(N(1.6), np.float32)
    m = N(0.1)
    scr = filt(rng.standard_normal(m).astype(np.float32), SR, hp=1500, lp=7000) * (0.4 + 0.6 * (rng.random(m) > 0.5)) * adsr(m, 0.005, 0.03, 0.7, 0.03)
    place(x, scr, 0, wrap=False)
    m2 = N(1.4)
    flare = bandpass(rng.standard_normal(m2).astype(np.float32), SR, 250, 2500, order=1) * (np.exp(-T(m2) / 0.18) * 0.9 + 0.1) * np.clip(T(m2) / 0.01, 0, 1)
    pops = np.zeros(m2, np.float32)
    for k in rng.integers(N(0.1), m2, size=10):
        place(pops, click(0.006, rng.uniform(1500, 3500), 0.001, rng) * rng.uniform(0.1, 0.4), int(k), wrap=False)
    place(x, flare * 0.6 + pops, N(0.06), wrap=False)
    return finish_sfx(x, -6, bits=11, fout=0.3)


@reg("sfx", "shrine_bell")
def shrine_bell(name):
    x = bell(1180, 4.5, 0.8) + 0.3 * bell(1180 * 1.003, 4.5, 0.5)
    x = np.concatenate([np.zeros(N(0.005)), x])
    return finish_sfx(reverb(filt(x, SR, hp=150, lp=8000), SR, 2.2, 0.25, lp=4000, seed=19), -4, bits=12, fout=0.6)


@reg("sfx", "wind_chime")
def wind_chime(name):
    rng = rng_for(name)
    notes = [mtof(m, c) for m, c in ((81, 0), (84, -30), (86, 0), (88, -20), (91, -40))]  # detuned
    x = np.zeros(N(5.5), np.float32)
    t = 0.0
    while t < 3.6:
        f = notes[int(rng.integers(0, len(notes)))]
        place(x, chime_tube(f, 2.0) * rng.uniform(0.3, 1.0), N(t), wrap=False)
        t += rng.uniform(0.08, 0.5)
    return finish_sfx(reverb(filt(x, SR, hp=300, lp=8000), SR, 2.0, 0.3, lp=5000, seed=20), -6, bits=11, fout=1.0)


@reg("sfx", "water_drip")
def water_drip(name):
    n = N(0.12)
    f = 900 + 900 * (1 - np.exp(-T(n) / 0.03))
    x = osc(f, n) * expenv(n, 0.025, 0.0008)
    x = np.concatenate([x, np.zeros(N(0.6))])
    return finish_sfx(reverb(x, SR, 0.9, 0.3, lp=4000, seed=21), -8, bits=11)


@reg("sfx", "water_pour")
def water_pour(name):
    """Pouring into a pot: gurgling stream + bubbles, cavity resonance rising as it fills."""
    rng = rng_for(name)
    dur = 1.6
    n = N(dur)
    t = T(n)
    stream = bandpass(rng.standard_normal(n).astype(np.float32), SR, 250, 4000, order=1)
    gurg = filt(rng.standard_normal(n).astype(np.float32), SR, lp=25)
    gurg = 0.6 + 0.4 * np.tanh(gurg / (np.std(gurg) + 1e-9))
    x = stream * gurg
    # rising cavity resonance: crossfade 4 fixed peak-EQ segments
    segs = [peak_eq(x, SR, fc, 10, q=3) for fc in (480, 600, 760, 950)]
    w = np.clip(t / dur * 3, 0, 3)
    y = np.zeros(n, np.float32)
    for i, sg in enumerate(segs):
        y += sg * np.clip(1 - np.abs(w - i), 0, 1)
    for _ in range(60):  # bubbles
        m = N(rng.uniform(0.008, 0.03))
        f0 = rng.uniform(500, 1400)
        b = osc(f0 * np.linspace(1, 1.5, m), m) * expenv(m, 0.008)
        place(y, b * rng.uniform(0.2, 0.8) * np.std(y) * 4, int(rng.uniform(0.05, dur - 0.1) * SR), wrap=False)
    y *= adsr(n, 0.08, 0.3, 0.85, 0.25)
    y = reverb(filt(y, SR, hp=150, lp=6500), SR, 0.4, 0.12, lp=4000, seed=22)
    return finish_sfx(y, -6, bits=11, fout=0.15, trim=False)


@reg("sfx", "buzz_wrong")
def buzz_wrong(name):
    n = N(0.38)
    f = 98 * (1 - 0.04 * T(n) / 0.38)
    x = osc(f, n, "square") + 0.8 * osc(f * 1.06, n, "square")  # beating, slightly sour
    x = bandpass(x, SR, 120, 2400, order=2) * adsr(n, 0.004, 0.1, 0.9, 0.03)
    x = softclip(x * 1.5, 2.0)
    return finish_sfx(np.concatenate([x, np.zeros(N(0.02))]), -6, bits=8, trim=False)


# ═════════════════════════════ AMBIENCE (loops) ═════════════════════════════
def _events(n, rng, count, gen, gain=(0.5, 1.0), spread=True):
    out = np.zeros(n, np.float32)
    for i in range(count):
        pos = (i + rng.uniform(0.1, 0.9)) * n / count if spread else rng.uniform(0, n)
        place(out, gen() * rng.uniform(*gain), int(pos))
    return out


def _norm(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-9)


@reg("amb", "amb_school_day")
def amb_school_day(name):
    rng = rng_for(name)
    n = N(60)
    pool = voice_pool()
    mur = babble(n, rng, pool, streams=6, lp=1600)
    mur = reverb(mur, SR, 1.6, 0.5, lp=1500, circular=True)
    birds = _events(n, rng, 26, lambda: bird_phrase(rng), (0.3, 1.0), spread=False)
    birds = reverb(filt(birds, SR, hp=1500, lp=6000, circular=True), SR, 1.0, 0.3, circular=True)
    bikes = _events(n, rng, 5, lambda: filt(motorbike(7, 9, 25, rng.uniform(30, 40), rng), SR, lp=1200))
    traf = traffic_bed(n, rng, 1.0, 400)
    x = 0.6 * _norm(mur) * smooth_rand(n, rng, 8, 0.5) + 0.25 * _norm(birds) + 0.35 * _norm(bikes) + 0.35 * traf + 0.15 * wind(n, rng)
    return finish_loop(x, -26, lp=7000, hp=40)


@reg("amb", "amb_classroom")
def amb_classroom(name):
    rng = rng_for(name)
    n = N(48)
    pool = voice_pool()
    mur = reverb(babble(n, rng, pool, streams=4, lp=2200, gap=(0.6, 3.0)), SR, 0.9, 0.35, lp=2500, circular=True)
    blade = bandpass(cnoise(n, rng, "pink"), SR, 120, 900, circular=True)
    fanx = blade * (0.75 + 0.25 * lfo(n, int(48 * 4.2)))  # ceiling fan swish ~4.2 Hz
    motor = 0.15 * mains_hum(n, 50, 6, 0.5, rng, 0.05)
    outside = 0.3 * traffic_bed(n, rng, 1.0, 350)
    x = 0.5 * _norm(mur) + 0.35 * _norm(fanx) + motor + outside
    return finish_loop(x, -27, lp=6500, hp=40)


@reg("amb", "amb_street_day")
def amb_street_day(name):
    rng = rng_for(name)
    n = N(60)
    traf = traffic_bed(n, rng, 1.0, 700)
    bikes = _events(n, rng, 12, lambda: motorbike(rng.uniform(5, 8), rng.uniform(7, 13), rng.uniform(6, 18), rng.uniform(28, 45), rng))
    horns = _events(n, rng, 7, lambda: car_horn(rng.uniform(0.15, 0.45), (rng.uniform(380, 450), rng.uniform(480, 560))), (0.1, 0.35), spread=False)
    horns = reverb(filt(horns, SR, lp=1500, circular=True), SR, 1.2, 0.4, circular=True)
    pool = voice_pool()
    mur = babble(n, rng, pool, streams=2, lp=1200, gap=(2, 6))
    x = 0.6 * traf + 0.7 * _norm(bikes) + 0.25 * _norm(horns) + 0.12 * _norm(mur) + 0.12 * wind(n, rng)
    return finish_loop(x, -25, lp=6000, hp=35)


@reg("amb", "amb_store_night")
def amb_store_night(name):
    rng = rng_for(name)
    n = N(48)
    fr = fridge(n, rng)
    outside = filt(traffic_bed(n, rng, 1.0, 300), SR, lp=400, circular=True)
    bike = _events(n, rng, 2, lambda: filt(motorbike(7, 10, 15, 33, rng), SR, lp=700), (0.3, 0.5))
    x = _norm(fr) * 0.8 + 0.25 * outside + 0.3 * _norm(bike)
    return finish_loop(x, -27, lp=5000, hp=35)


@reg("amb", "hum_fluorescent")
def hum_fluorescent(name):
    rng = rng_for(name)
    n = N(20)
    # Vietnamese mains are 50 Hz → tubes buzz at 100 Hz (+ a little 50 Hz)
    x = mains_hum(n, 100, 20, 0.85, rng, buzz=1.2) + 0.1 * np.sin(2 * np.pi * 50 * T(n))
    x *= 1 + 0.08 * smooth_rand(n, rng, 30) * lfo(n, 37)
    ticks = np.zeros(n, np.float32)
    for k in rng.integers(0, n, size=9):
        place(ticks, click(0.01, rng.uniform(2500, 4500), 0.0015, rng) * rng.uniform(0.2, 0.6), int(k))
    x = _norm(x) + 0.8 * ticks
    return finish_loop(x, -30, lp=6000)


@reg("amb", "amb_alley_night")
def amb_alley_night(name):
    rng = rng_for(name)
    n = N(60)
    cr = crickets(n, rng, count=5, level=1.0)
    far = traffic_bed(n, rng, 1.0, 300)
    dog = pk("oga/dog-barking-mono/dog_barking_mono.wav")
    dogs = np.zeros(n, np.float32)
    if dog is not None:
        d = fxc.apply_fx(dog, SR, "far", seed=5, out_sr=SR)[0]
        d = filt(d, SR, lp=1500)
        place(dogs, d, N(17))
        place(dogs, resample_pitch(d, -1)[:N(2.5)], N(46), 0.6)
    wires = mains_hum(n, 100, 10, 0.8, rng, 0.8) * (0.6 + 0.4 * smooth_rand(n, rng, 6))
    wires = bandpass(wires, SR, 150, 3000, circular=True)
    x = 0.24 * _norm(cr) + 0.5 * far + 0.25 * _norm(dogs) + 0.05 * _norm(wires) + 0.2 * wind(n, rng, lowness=0.8)
    return finish_loop(x, -27, lp=6500, hp=35)


def _fan_loop(n, rng, cycles=4):
    """Oscillating desk fan: blade whoosh + motor + creak at each turn-around."""
    blade = filt(cnoise(n, rng, "pink"), SR, hp=80, lp=1000, circular=True)
    sweep = (0.6 + 0.4 * lfo(n, cycles))  # facing / away
    whoosh = _norm(blade) * sweep * (0.85 + 0.15 * lfo(n, int(n / SR * 18)))
    motor = 0.12 * mains_hum(n, 50, 5, 0.5, rng, 0.0)
    cr = np.zeros(n, np.float32)
    for i in range(cycles * 2):
        pos = (i + 0.5) * n / (cycles * 2) - N(0.3)
        c = _creak_long(rng, rng.uniform(0.35, 0.6), rng.uniform(55, 80), rng.uniform(90, 140), modes=(610, 1250, 2300))
        place(cr, c * rng.uniform(0.5, 1.0), int(pos))
    tick = np.zeros(n, np.float32)
    for i in range(cycles * 6):
        place(tick, click(0.008, 1800, 0.0015, rng) * 0.3, int((i + rng.uniform(0, .3)) * n / (cycles * 6)))
    return whoosh * 0.6 + motor + 0.35 * cr + 0.2 * tick


@reg("amb", "fan_creak")
def fan_creak(name):
    rng = rng_for(name)
    n = N(32)
    return finish_loop(_fan_loop(n, rng, 4), -28, lp=6000, hp=40)


@reg("amb", "amb_dorm_night")
def amb_dorm_night(name):
    rng = rng_for(name)
    n = N(64)
    fan = _fan_loop(n, rng, 8)
    pool = voice_pool()
    tv = babble(n, rng, pool, streams=2, lp=600, reverse=False, gap=(0.3, 1.2))
    tune = np.zeros(n, np.float32)
    for i in range(6):
        place(tune, fm_rhodes(mtof(int(rng.choice([60, 64, 67, 72]))), 1.0, 0.5), int(rng.uniform(0, n)))
    tv = reverb(filt(tv + 0.3 * _norm(tune) * np.std(tv), SR, hp=150, lp=550, circular=True), SR, 0.5, 0.4, lp=600, circular=True)
    pipes = np.zeros(n, np.float32)
    for st in (12, 41):
        m = N(rng.uniform(3, 5))
        flow = filt(rng.standard_normal(m).astype(np.float32), SR, hp=100, lp=700) * np.sin(np.pi * np.linspace(0, 1, m)) ** 2
        for _ in range(25):
            k = N(rng.uniform(0.02, 0.06))
            f = rng.uniform(180, 520) * np.linspace(1, 1.5, k)
            place(flow, osc(f, k) * expenv(k, 0.02) * rng.uniform(0.3, 1.5), int(rng.integers(0, m - k)), wrap=False)
        place(pipes, flow, N(st))
        place(pipes, modal([1350, 3100], [1, .4], [0.2, 0.1], 0.6) * 0.3, N(st + 4.8))
    x = 0.6 * fan + 0.35 * _norm(tv) * smooth_rand(n, rng, 10, 0.4) + 0.3 * _norm(pipes) + 0.2 * traffic_bed(n, rng, 1.0, 250)
    return finish_loop(x, -28, lp=6000, hp=35)


@reg("amb", "amb_room_day")
def amb_room_day(name):
    rng = rng_for(name)
    n = N(60)
    traf = traffic_bed(n, rng, 1.0, 500)
    bikes = _events(n, rng, 8, lambda: motorbike(rng.uniform(5, 8), 9, rng.uniform(10, 25), rng.uniform(28, 42), rng))
    horns = _events(n, rng, 4, lambda: car_horn(rng.uniform(0.15, 0.4)), (0.1, 0.3), spread=False)
    birds = _events(n, rng, 8, lambda: bird_phrase(rng), (0.2, 0.6), spread=False)
    x = 0.6 * traf + 0.6 * _norm(bikes) + 0.15 * _norm(horns) + 0.12 * _norm(birds)
    x = filt(x, SR, lp=2200, circular=True)  # through the window
    x = reverb(x, SR, 0.5, 0.25, lp=2000, circular=True)
    return finish_loop(x, -28, hp=35)


@reg("amb", "amb_shrine")
def amb_shrine(name):
    rng = rng_for(name)
    n = N(60)
    w = wind(n, rng, 1.0, 1.0)
    lv = leaves(n, rng)
    cr = crickets(n, rng, count=2, density=0.5)
    ch = np.zeros(n, np.float32)
    notes = [mtof(m, c) for m, c in ((81, 0), (84, -30), (86, 0), (88, -20))]
    for i in range(7):
        st = rng.uniform(0, n)
        for j in range(int(rng.integers(1, 4))):
            place(ch, chime_tube(notes[int(rng.integers(0, 4))], 2.0) * rng.uniform(0.2, 0.6), int(st + j * rng.uniform(0.1, 0.4) * SR))
    ch = reverb(ch, SR, 2.0, 0.4, lp=5000, circular=True)
    x = 0.8 * w + 0.25 * lv + 0.15 * _norm(cr) + 0.08 * _norm(ch)
    return finish_loop(x, -27, lp=6000, hp=30)


@reg("amb", "amb_street_dead")
def amb_street_dead(name):
    rng = rng_for(name)
    n = N(60)
    w = wind(n, rng, 1.0, 0.7)
    lamp = mains_hum(n, 100, 16, 0.82, rng, 0.9) * (0.8 + 0.2 * smooth_rand(n, rng, 20))
    lamp = bandpass(lamp, SR, 90, 3500, circular=True)
    creak = np.zeros(n, np.float32)
    place(creak, _creak_long(rng, 1.4, 30, 55, modes=(240, 610, 1300)), N(23))
    creak = reverb(filt(creak, SR, lp=1500, circular=True), SR, 2.5, 0.6, lp=1200, circular=True)
    x = 0.9 * w + 0.08 * _norm(lamp) + 0.12 * _norm(creak)
    return finish_loop(x, -29, lp=5000, hp=30)


@reg("amb", "drone_dread")
def drone_dread(name):
    rng = rng_for(name)
    n = N(60)
    d = pad_saw([mtof(28), mtof(28, 14), mtof(35, -8), mtof(29, -30)], n, rng, voices=2, detune=0.1, lp=220)
    d *= 0.7 + 0.3 * smooth_rand(n, rng, 5)
    sub = 0.5 * osc(mtof(16) * (1 + 0.004 * lfo(n, 3)), n)
    metal = bandpass(cnoise(n, rng, "pink"), SR, 600, 1400, circular=True)
    metal = fxc.flanger(metal, SR, 6, 60 / n * SR * 0 + 3 / (n / SR), 0.6, 0.7) * smooth_rand(n, rng, 4) ** 3
    hi = sum(osc(mtof(m, c), n) for m, c in ((76, 0), (77, -30))) * 0.04 * smooth_rand(n, rng, 3) ** 2
    x = _norm(d) + 0.5 * sub + 0.4 * _norm(metal) + hi
    x = reverb(x, SR, 3.0, 0.3, lp=1500, circular=True)
    return finish_loop(x, -24, lp=3000, hp=22)


@reg("amb", "rao_dem")
def rao_dem(name):
    rng = rng_for(name)
    n = N(60)
    bed = 0.5 * traffic_bed(n, rng, 1.0, 250) + 0.25 * wind(n, rng, 1.0, 0.6) + 0.06 * _norm(crickets(n, rng, 2, density=0.4))
    calls = [tts_src(k) for k in ("rao_tuyen_1", "rao_vinh_2", "rao_tuyen_2", "rao_vinh_1")]
    calls = [c for c in calls if c is not None]
    voice = np.zeros(n, np.float32)
    if calls:
        for i, (st, c) in enumerate(zip((6.0, 21.0, 37.0, 50.0), calls * 2)):
            if i == 3 and len(calls) < 4:
                break
            c = stretch(c, 0.72, 1.0)  # drawn-out vendor cadence
            y = fxc.apply_fx(c, SR, "far", seed=i, out_sr=SR)[0]
            y = filt(y, SR, lp=1800)
            ramp = np.linspace(*( (0.6, 1.0) if i % 2 == 0 else (1.0, 0.55)), len(y))  # moving cart
            place(voice, _norm(y) * ramp * [1.0, 0.75, 0.6, 0.85][i], N(st))
    x = 0.55 * _norm(voice) + bed
    return finish_loop(x, -28, lp=5000, hp=35)


# ═════════════════════════════ MUSIC (loops) ═════════════════════════════
def chord_hits(buf, bar_len, bars, chords, rng, vel=0.6, restrike=0.5, strum=0.012, octave_shift=0, swing_t=None):
    for b in range(bars):
        ch = chords[b % len(chords)]
        st = b * bar_len
        for hit_t, v in ((0.0, vel), (bar_len * 0.625, vel * 0.55)):
            if hit_t > 0 and rng.random() > restrike:
                continue
            dur = bar_len - hit_t + 0.4
            for i, (m, c) in enumerate(ch):
                f = mtof(m + 12 * octave_shift, c + rng.uniform(-6, 6))
                note = fm_rhodes(f, dur, v * rng.uniform(0.8, 1.0)) + 0.5 * fm_rhodes(f * 1.003, dur, v * 0.5)
                place(buf, note, N(st + hit_t + i * strum * rng.uniform(0.5, 1.5)))


def bass_line(buf, bar_len, bars, roots, rng, vel=0.5, pattern=((0.0, 0.55), (0.625, 0.3))):
    for b in range(bars):
        m, c = roots[b % len(roots)]
        for pos, d in pattern:
            n = N(bar_len * d)
            f = mtof(m, c)
            x = (osc(f, n) + 0.25 * osc(2 * f, n)) * adsr(n, 0.01, 0.3, 0.6, 0.08) * vel
            place(buf, x, N(b * bar_len + pos * bar_len))


def drums(buf, beat, bars, rng, swing=0.6, kick_v=0.9, snare_v=0.5, hat_v=0.25, ghost=True, snare_on=True):
    for b in range(bars):
        base = b * 4 * beat
        for k in (0.0, 2.5 if rng.random() < 0.6 else 2.0):
            place(buf, kick(kick_v * rng.uniform(0.85, 1.0)), N(base + k * beat))
        if rng.random() < 0.3:
            place(buf, kick(kick_v * 0.6), N(base + 3.5 * beat))
        if snare_on:
            for s in (1, 3):
                place(buf, snare(snare_v * rng.uniform(0.85, 1.0), rng), N(base + s * beat + rng.uniform(0, 0.01)))
        for e in range(8):
            off = (e // 2) * beat + (swing * beat if e % 2 else 0)
            v = hat_v * (1.0 if e % 2 == 0 else 0.6) * rng.uniform(0.7, 1.0)
            place(buf, hat(v, rng, open_=(e == 7 and rng.random() < 0.2)), N(base + off))
        if ghost and rng.random() < 0.4:
            place(buf, snare(snare_v * 0.2, rng), N(base + 3.75 * beat))


def melody(buf, bar_len, bars, scale, rng, vel=0.35, density=0.35, start_bar=4, octave=72):
    for b in range(start_bar, bars):
        for s in range(8):
            if rng.random() > density:
                continue
            m, c = scale[int(rng.integers(0, len(scale)))]
            d = bar_len / 8 * rng.choice([1, 2, 3])
            n = N(d + 0.6)
            f = mtof(octave + m, c)
            x = (osc(f, n) + 0.2 * osc(2 * f, n, "tri")) * adsr(n, 0.03, 0.3, 0.5, 0.3) * vel
            x *= 1 + 0.03 * np.sin(2 * np.pi * 5 * T(n))
            place(buf, x, N(b * bar_len + s * bar_len / 8))


def lofi_master(x, lp=3800, wow=2.5, crackle_lv=0.05, rng=None, lufs=-18.0, bits=11):
    x = wow_flutter(x, depth_ms=wow)
    x = filt(x, SR, hp=35, lp=lp, order=2, circular=True)
    x = softclip(x / (np.max(np.abs(x)) + 1e-9) * 0.9, 1.4)
    x = x + crackle(len(x), rng, density=7, level=crackle_lv, hiss=crackle_lv * 0.08)
    x = bitcrush(x, bits)
    return finish_loop(x, lufs, peak_db=-1.5)


# chord voicings as (midi, cents); some tones detuned flat → "subtly wrong"
DAY = [[(53, 0), (57, 0), (60, 0), (64, -30)],          # Fmaj7 (flat 7th)
       [(52, 0), (55, 0), (59, -25), (62, 0)],          # Em7
       [(50, 0), (53, 0), (57, 0), (60, 0), (64, -15)],  # Dm9
       [(49, -20), (53, 0), (56, 0), (60, -35)]]        # Dbmaj7 (borrowed, sour)
MENU = [[(45, 0), (52, 0), (59, -30), (60, 0)],          # Am(add9)
        [(41, 0), (48, 0), (52, -35), (57, 0)],          # Fmaj7
        [(38, 0), (50, 0), (53, -20), (59, 0)],          # Dm6
        [(40, 0), (50, 0), (53, -40), (56, 0)]]          # E7b9-ish
CREDITS = [[(50, 0), (57, 0), (61, -20), (64, 0)],       # Dmaj9
           [(47, 0), (54, 0), (57, 0), (62, -15)],       # Bm7
           [(43, 0), (54, 0), (59, 0), (62, 0)],         # Gmaj7
           [(45, 0), (52, 0), (55, -25), (62, 0)]]       # A7sus4
END_A = [[(43, 0), (50, 0), (54, 0), (59, 0)],           # Gmaj7
         [(42, 0), (50, 0), (54, 0), (57, -10)],         # D/F#
         [(40, 0), (50, 0), (55, 0), (59, 0)],           # Em7
         [(36, 0), (52, 0), (55, 0), (62, -15)]]         # Cmaj9


def _render_lofi(name, bpm, bars, chords, mel_scale, drum_cfg, lp, wow, crk, lufs=-18, chord_vel=0.6, mel=0.3, oct_shift=0):
    rng = rng_for(name)
    beat = 60 / bpm
    bar = 4 * beat
    n = N(bar * bars)
    keys = np.zeros(n, np.float32)
    chord_hits(keys, bar, bars, chords, rng, vel=chord_vel, octave_shift=oct_shift)
    bass = np.zeros(n, np.float32)
    bass_line(bass, bar, bars, [(c[0][0] - 12 if c[0][0] >= 40 else c[0][0], c[0][1]) for c in chords], rng)
    dr = np.zeros(n, np.float32)
    if drum_cfg:
        drums(dr, beat, bars, rng, **drum_cfg)
    ml = np.zeros(n, np.float32)
    if mel_scale:
        melody(ml, bar, bars, mel_scale, rng, vel=0.3, density=mel)
    dr = filt(dr, SR, hp=55, circular=True) if drum_cfg else dr
    x = 0.6 * _norm(keys) + 0.22 * _norm(bass) + (0.4 * _norm(dr) if drum_cfg else 0) + (0.22 * _norm(ml) if mel_scale else 0)
    x = reverb(x, SR, 1.6, 0.18, lp=3000, circular=True)
    return lofi_master(x, lp=lp, wow=wow, crackle_lv=crk, rng=rng, lufs=lufs)


PENTA_F = [(0, 0), (2, 0), (4, -20), (7, 0), (9, 0), (12, 0)]
PENTA_D = [(2, 0), (4, 0), (6, 0), (9, 0), (11, -10), (14, 0)]
PENTA_A = [(-3, 0), (0, 0), (2, -30), (4, 0), (7, 0)]


@reg("music", "music_day_lofi")
def music_day_lofi(name):
    return _render_lofi(name, 80, 24, DAY, PENTA_F, dict(swing=0.62, kick_v=0.8, snare_v=0.45, hat_v=0.22),
                        lp=3800, wow=2.5, crk=0.05, chord_vel=0.6, mel=0.25)


@reg("music", "music_menu")
def music_menu(name):
    return _render_lofi(name, 60, 16, MENU, PENTA_A,
                        dict(swing=0.6, kick_v=0.6, snare_v=0.2, hat_v=0.12, snare_on=False, ghost=False),
                        lp=2800, wow=4.5, crk=0.08, lufs=-20, chord_vel=0.5, mel=0.12)


@reg("music", "music_credits")
def music_credits(name):
    return _render_lofi(name, 76, 30, CREDITS, PENTA_D, dict(swing=0.6, kick_v=0.8, snare_v=0.4, hat_v=0.2),
                        lp=4200, wow=2.0, crk=0.045, chord_vel=0.6, mel=0.3)


@reg("music", "music_tension")
def music_tension(name):
    rng = rng_for(name)
    bpm = 100
    beat = 60 / bpm
    bars = 25
    n = N(4 * beat * bars)
    pulse = np.zeros(n, np.float32)
    e = N(beat / 2)
    for i in range(int(n / e)):
        acc = 1.0 if i % 8 in (0, 3, 6) else 0.55
        m = N(beat * 0.45)
        x = (osc(mtof(28), m, "saw") * 0.6 + osc(mtof(40, -10), m, "saw") * 0.7 + osc(mtof(52, -10), m, "saw") * 0.25) \
            * adsr(m, 0.005, 0.08, 0.3, 0.05) * acc
        place(pulse, x, i * e)
    pulse = filt(pulse, SR, hp=45, lp=900, order=2, circular=True)
    drone = pad_saw([mtof(28), mtof(29, -20)], n, rng, voices=3, detune=0.15, lp=300) * (0.7 + 0.3 * lfo(n, bars // 2))
    strings = pad_saw([mtof(64), mtof(65, -25), mtof(71, -10)], n, rng, voices=3, detune=0.2, lp=2200)
    strings *= smooth_rand(n, rng, 6) ** 2
    hb = np.zeros(n, np.float32)
    for b in range(bars):
        place(hb, kick(0.9), N(b * 4 * beat))
        place(hb, kick(0.6), N(b * 4 * beat + 0.28))
    tick = np.zeros(n, np.float32)
    for i in range(bars * 16):
        place(tick, hat(0.15 if i % 4 else 0.3, rng), N(i * beat / 4))
    x = 0.6 * _norm(pulse) + 0.35 * _norm(drone) + 0.3 * _norm(strings) + 0.35 * _norm(hb) + 0.12 * _norm(tick)
    x = reverb(x, SR, 2.0, 0.2, lp=2500, circular=True)
    return lofi_master(x, lp=3500, wow=1.5, crackle_lv=0.02, rng=rng, lufs=-19)


@reg("music", "music_ending_a")
def music_ending_a(name):
    rng = rng_for(name)
    bpm = 66
    beat = 60 / bpm
    bar = 4 * beat
    bars = 24
    n = N(bar * bars)
    pad = np.zeros(n, np.float32)
    for b in range(bars):
        ch = END_A[(b // 2) % 4]
        m = N(bar * 2 + 1.5) if b % 2 == 0 else 0
        if m:
            p = pad_saw([mtof(mm, c) for mm, c in ch], m, rng, voices=3, detune=0.08, lp=1400)
            place(pad, p * adsr(m, 1.2, 1.0, 0.8, 1.4), N(b * bar))
    arp = np.zeros(n, np.float32)
    for b in range(bars):
        ch = END_A[(b // 2) % 4]
        for s in range(8):
            mm, c = ch[(s * 3 + b) % len(ch)]
            place(arp, fm_rhodes(mtof(mm + 12, c), beat * 1.5, 0.35 * rng.uniform(0.7, 1.0)), N(b * bar + s * beat / 2))
    bass = np.zeros(n, np.float32)
    bass_line(bass, bar, bars, [(c[0][0] - 12 if c[0][0] > 40 else c[0][0], 0) for c in END_A for _ in (0, 1)], rng, 0.5, ((0.0, 1.0),))
    birds = _events(n, rng, 6, lambda: bird_phrase(rng), (0.2, 0.5), spread=True)
    x = 0.55 * _norm(pad) + 0.5 * _norm(arp) + 0.3 * _norm(bass) + 0.05 * _norm(filt(birds, SR, hp=1500, circular=True))
    x = reverb(x, SR, 2.5, 0.3, lp=4000, circular=True)
    return lofi_master(x, lp=5000, wow=1.5, crackle_lv=0.025, rng=rng, lufs=-19, bits=12)


@reg("music", "music_ending_b")
def music_ending_b(name):
    rng = rng_for(name)
    n = N(88)
    fifth = pad_saw([mtof(33), mtof(40), mtof(45)], n, rng, voices=3, detune=0.06, lp=500)
    fifth *= 0.75 + 0.25 * lfo(n, 4)
    cluster = pad_saw([mtof(69), mtof(70, -20), mtof(76, -35)], n, rng, voices=2, detune=0.1, lp=1600)
    cluster *= smooth_rand(n, rng, 4) ** 3
    tolls = np.zeros(n, np.float32)
    for i in range(8):
        place(tolls, bell(196, 9.0, 0.5), N(i * 11.0 + 2.0))
    tolls = filt(tolls, SR, lp=1500, circular=True)
    st = fxc.static_bed(n, SR, rng, 1.0) * smooth_rand(n, rng, 6) ** 4
    x = _norm(fifth) + 0.25 * _norm(cluster) + 0.35 * _norm(tolls) + 0.05 * _norm(st)
    x = reverb(x, SR, 4.0, 0.4, lp=2000, circular=True)
    return lofi_master(x, lp=3000, wow=3.0, crackle_lv=0.03, rng=rng, lufs=-21)


# ═════════════════════════════ main ═════════════════════════════
DIRS = {"sfx": "sfx", "amb": "amb", "music": "music"}
# Integrated loudness targets for one-shots (LUFS, short clips measured by tiling). Peaks capped at -1.5 dBFS.
SFX_LUFS = {
    "footstep_concrete": -27, "footstep_tile": -27, "footstep_wood": -27, "footstep_stiff": -24,
    "breath_heavy": -24, "breath_scared": -26, "heartbeat": -22,
    "door_open_creak": -22, "door_close": -20, "door_lock": -24, "door_unlock": -24, "door_knock_3": -20,
    "door_knock_slow": -18, "door_handle_rattle": -22, "shop_bell": -18, "scanner_beep": -19,
    "register_open": -22, "item_pickup": -26, "item_drop": -24, "can_place": -24, "box_open": -24,
    "mop_squeak": -22, "water_boil": -28, "stove_click": -23, "phone_vibrate": -20, "phone_tap": -26,
    "phone_open": -25, "flashlight_click": -24, "light_switch": -24, "fluorescent_flicker": -24,
    "static_burst": -19, "jumpscare_sting": -13, "stinger_low": -17, "entity_whisper": -21, "glass_tap": -21,
    "motorbike_pass": -20, "dog_bark_far": -28, "match_strike": -24, "shrine_bell": -21, "wind_chime": -22,
    "water_drip": -27, "fan_click": -25, "page_turn": -26, "ui_move": -26, "ui_select": -24, "ui_back": -25,
    "water_pour": -24, "buzz_wrong": -22,
}


def sfx_lufs(name):
    base = name.rstrip("0123456789").rstrip("_")
    return SFX_LUFS.get(name, SFX_LUFS.get(base, -22))


def build(name):
    cat, fn = REG[name]
    t0 = time.time()
    y = fn(name)
    if cat == "sfx":
        y = fxc.normalize(y, SR, sfx_lufs(name), peak_db=-1.5)
    q = 3.0 if cat != "music" else 4.0
    path = OUT / DIRS[cat] / f"{name}.ogg"
    for _ in range(4):  # vorbis can overshoot on dense/distorted material: back off until decoded peak <= -0.5 dBFS
        fxc.save_ogg(y, SR, path, q=q)
        pk_db = 20 * np.log10(np.max(np.abs(fxc.load(path, SR))) + 1e-9)
        if pk_db <= -0.5:
            break
        y = y * 10 ** ((-0.8 - pk_db) / 20)
    print(f"  {cat:5s} {name:24s} {len(y) / SR:6.2f}s  ({time.time() - t0:.1f}s)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--cat", choices=["sfx", "amb", "music"], help="build one category")
    a = ap.parse_args()
    if a.list:
        for k, (c, _) in sorted(REG.items(), key=lambda kv: (kv[1][0], kv[0])):
            print(c, k)
        return
    names = a.only or [k for k, (c, _) in REG.items() if not a.cat or c == a.cat]
    bad = [n for n in names if n not in REG]
    if bad:
        sys.exit(f"unknown: {bad}")
    for n in names:
        build(n)
    used = HERE / "_cache" / "used_sources.txt"
    used.parent.mkdir(exist_ok=True, parents=True)
    prev = set(used.read_text().split("\n")) if used.exists() else set()
    used.write_text("\n".join(sorted((prev | USED_SOURCES) - {""})))


if __name__ == "__main__":
    main()
