#!/usr/bin/env python3
"""Procedural PS1-style Vietnamese face textures.

Output per character (assets/textures/chars/):
  head_<name>.png   128x64 head atlas: left 64x64 = flat front face (planar projection of the
                    head's 3 front faces), right 64x64 = cylindrical wrap of sides/back (hair, ears, nape).
                    Hair meshes sample the always-hair patch at x 80..112, y 0..14.
  face_<name>.png   64x64 crop of the front face (UI / phone avatars).
  head_<name>_distort.png  exaggerated version (entities only: gazer, mimic_hung, mimic_linh).

Front face coordinates: u 0..1 = full head width (ears at the edges), v 0 = top of the
front faces (z=0.225 m above chin), v 1 = chin. Eyes v~0.47, nose tip v~0.66, mouth v~0.79.

Run: python3 tools/textures/chars/make_faces.py
"""
import os
import sys
import copy
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from psxpaint import Canvas, finalize  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "chars")

FW, FH = 180, 256      # front canvas (physical aspect 0.165 x 0.235 m)
WW, WH = 256, 256      # wrap canvas

BLACK_HAIR = (22, 19, 19)
DARK_BROWN_HAIR = (38, 28, 24)
GRAY_HAIR = (128, 124, 118)

# --------------------------------------------------------------------------------------------
# Character face specs
# --------------------------------------------------------------------------------------------
BASE = dict(
    sex="m", skin=(214, 168, 132), age=0.0, face_w=1.0, round=0.0, gaunt=0.0,
    hair="messy", hair_color=BLACK_HAIR, brow=1.0, brow_color=(30, 24, 22),
    eye_size=1.0, iris=1.0, lids=True, double_lid=False, eye_dy=(0.0, 0.0), eye_dx=(0.0, 0.0),
    eye_spacing=0.19, wide=1.0, mouth_w=1.0, lips=(160, 92, 82), mouth_long=0.0, smile=0.0,
    mustache=False, glasses=False, mask=None, wrinkles=0.0, blush=0.0, stubble=0.0, seed=1,
    sclera=(226, 222, 212), mouth_open=0.0,
)

def spec(**kw):
    d = copy.deepcopy(BASE)
    d.update(kw)
    return d

CHARS = {
    "nam": spec(skin=(212, 166, 128), hair="messy", brow=1.1, seed=11, stubble=0.15),
    "hung": spec(skin=(200, 150, 112), hair="buzz", round=0.8, face_w=1.12, eye_size=0.9, brow=1.3,
                 mouth_w=1.05, smile=0.25, seed=12),
    "linh": spec(sex="f", skin=(228, 186, 154), hair="long_bangs", brow=0.7, double_lid=True, eye_size=1.08,
                 lips=(178, 92, 92), blush=0.25, face_w=0.92, mouth_w=0.88, seed=13),
    "bac_tu": spec(skin=(184, 136, 100), age=0.85, gaunt=0.6, hair="gray_thin", hair_color=GRAY_HAIR,
                   brow_color=(90, 84, 78), mustache=True, wrinkles=0.9, eye_size=0.85, lips=(140, 92, 82),
                   face_w=0.95, seed=14),
    "chi_hanh": spec(sex="f", skin=(222, 176, 142), age=0.3, hair="bun", brow=0.75, double_lid=True,
                     lips=(170, 80, 82), blush=0.15, wrinkles=0.15, seed=15),
    "thay_khai": spec(skin=(204, 158, 122), age=0.6, hair="side_part", hair_color=(48, 44, 42), glasses=True,
                      wrinkles=0.45, brow=1.0, face_w=1.02, round=0.3, seed=16),
    "ba_cu": spec(sex="f", skin=(190, 142, 108), age=1.0, gaunt=0.4, hair="scarf", hair_color=(150, 146, 140),
                  brow=0.5, brow_color=(110, 100, 92), wrinkles=1.0, eye_size=0.75, lips=(132, 86, 80),
                  mouth_w=0.9, seed=17),
    "student_m1": spec(skin=(210, 162, 124), hair="short_neat", seed=21, face_w=0.97),
    "student_m2": spec(skin=(196, 148, 108), hair="side_part", glasses=True, seed=22, round=0.4, face_w=1.05),
    "student_f1": spec(sex="f", skin=(226, 182, 150), hair="ponytail", brow=0.7, lips=(176, 94, 92),
                       blush=0.2, double_lid=True, seed=23, face_w=0.93),
    "student_f2": spec(sex="f", skin=(218, 174, 140), hair="bob", brow=0.75, lips=(168, 96, 90), blush=0.1,
                       glasses=True, seed=24, face_w=0.95, round=0.3),
    "passerby_m1": spec(skin=(176, 128, 92), age=0.45, hair="short_neat", wrinkles=0.35, stubble=0.4,
                        seed=31, face_w=1.03),
    "passerby_m2": spec(skin=(190, 140, 104), age=0.3, hair="messy", mask=(120, 150, 170), seed=32),
    "passerby_f1": spec(sex="f", skin=(200, 152, 116), age=0.5, hair="bun", wrinkles=0.4, lips=(150, 90, 86),
                        brow=0.6, seed=33, mask=None),
    # Gazer: a calm guard/student face that is subtly wrong -- eyes too wide, irises tiny, no lids.
    "gazer": spec(skin=(204, 170, 146), hair="short_neat", gaunt=0.7, face_w=0.88, lids=False, wide=1.9,
                  iris=0.45, eye_size=1.05, brow=0.6, mouth_w=0.8, lips=(150, 112, 104), seed=41,
                  sclera=(236, 234, 226)),
}
CHARS["mimic_hung"] = dict(CHARS["hung"], eye_dy=(0.0, 0.028), eye_dx=(-0.012, 0.0), mouth_long=0.55, smile=0.0,
                          seed=12)
CHARS["mimic_linh"] = dict(CHARS["linh"], eye_dy=(0.024, 0.0), eye_dx=(0.0, 0.014), mouth_long=0.6, seed=13)

DISTORT = {
    "gazer": dict(wide=3.6, iris=0.25, mouth_long=0.9, mouth_open=0.4, eye_size=1.5, gaunt=1.0),
    "mimic_hung": dict(eye_dy=(-0.01, 0.07), eye_dx=(-0.03, 0.02), mouth_long=1.6, mouth_open=0.9, wide=2.2,
                       iris=0.4, lids=False),
    "mimic_linh": dict(eye_dy=(0.06, -0.01), eye_dx=(0.0, 0.03), mouth_long=1.8, mouth_open=1.0, wide=2.4,
                       iris=0.35, lids=False),
}


def mix(a, b, t):
    return tuple(float(a[i]) * (1 - t) + float(b[i]) * t for i in range(3))


def scale(c, f):
    return tuple(min(255, c[i] * f) for i in range(3))


# --------------------------------------------------------------------------------------------
# Front face
# --------------------------------------------------------------------------------------------
def paint_front(s):
    c = Canvas(FW, FH, s["skin"], seed=s["seed"])
    skin = s["skin"]
    shadow = mix(skin, (90, 50, 40), 0.45)
    deep = mix(skin, (50, 25, 20), 0.6)
    light = mix(skin, (255, 236, 220), 0.35)
    u, v = c.u, c.v
    fw = s["face_w"]

    # --- head volume shading (cylinder + top light) ---
    side = np.abs(u - 0.5) * 2
    c.shade(side ** 2.2, 0.62)
    c.shade(np.clip(u - 0.45, 0, 1) * 1.6, 0.8)   # key light from the left
    c.shade(np.clip(0.4 - u, 0, 1) * 2.0, 1.1)
    c.shade(np.clip((v - 0.85) / 0.15, 0, 1) * (side ** 1.5), 0.6)
    # jaw outline: everything outside the jaw is under-chin / neck shadow
    jaw_hw = 0.36 * fw
    jaw = c.poly([(0.5 - 0.46 * fw, 0.5), (0.5 - 0.44 * fw, 0.70), (0.5 - jaw_hw, 0.86), (0.5 - 0.17 * fw, 0.985),
                  (0.5 + 0.17 * fw, 0.985), (0.5 + jaw_hw, 0.86), (0.5 + 0.44 * fw, 0.70), (0.5 + 0.46 * fw, 0.5),
                  (1.2, 0.5), (1.2, -0.2), (-0.2, -0.2), (-0.2, 0.5)], blur=0.03)
    c.shade(1 - jaw, 0.55)
    if s["round"] > 0:  # full cheeks
        for sx in (-1, 1):
            c.shade(c.ellipse(0.5 + sx * 0.27, 0.66, 0.13, 0.12, blur=0.06), 1 + 0.08 * s["round"])
    # cheekbone highlight & forehead highlight
    for sx in (-1, 1):
        c.shade(c.ellipse(0.5 + sx * 0.24, 0.58, 0.1, 0.06, blur=0.05), 1.08)
    c.shade(c.ellipse(0.5, 0.22, 0.25, 0.1, blur=0.06), 1.08)
    if s["gaunt"] > 0:  # hollow cheeks + temples
        for sx in (-1, 1):
            c.shade(c.ellipse(0.5 + sx * 0.3, 0.7, 0.07, 0.09, blur=0.04), 1 - 0.25 * s["gaunt"])
            c.shade(c.ellipse(0.5 + sx * 0.4, 0.38, 0.06, 0.08, blur=0.04), 1 - 0.18 * s["gaunt"])

    # --- ears at the far sides ---
    for sx in (0, 1):
        ex = 0.035 if sx == 0 else 0.965
        c.blend(c.ellipse(ex, 0.54, 0.045, 0.09, blur=0.01), mix(skin, (170, 90, 80), 0.15), 0.9)
        c.shade(c.ellipse(ex + (0.01 if sx == 0 else -0.01), 0.55, 0.018, 0.05, blur=0.01), 0.7)

    # --- eye sockets ---
    ey = 0.47
    eyes = []
    for i, sx in enumerate((-1, 1)):
        ex = 0.5 + sx * s["eye_spacing"] + s["eye_dx"][i]
        eyy = ey + s["eye_dy"][i]
        eyes.append((ex, eyy))
        c.shade(c.ellipse(ex, eyy - 0.01, 0.1, 0.045, blur=0.03), 0.86 - 0.08 * s["age"])

    # --- nose ---
    c.shade(c.rect(0.475, 0.47, 0.525, 0.63, blur=0.02), 1.08)                       # bridge highlight
    c.shade(c.poly([(0.52, 0.48), (0.57, 0.62), (0.6, 0.67), (0.52, 0.67)], blur=0.02), 0.7)  # side shadow
    c.shade(c.ellipse(0.51, 0.69, 0.1, 0.025, blur=0.02), 0.62)                      # under-nose shadow
    c.blend(c.ellipse(0.5, 0.655, 0.06, 0.03, blur=0.02), light, 0.35)                # tip highlight
    for sx in (-1, 1):
        c.blend(c.ellipse(0.5 + sx * 0.04, 0.675, 0.018, 0.009, blur=0.004), deep, 0.85)  # nostrils
        c.shade(c.ellipse(0.5 + sx * 0.075, 0.66, 0.02, 0.022, blur=0.01), 0.85)      # alae
    c.shade(c.rect(0.49, 0.70, 0.51, 0.75, blur=0.01), 0.92)                          # philtrum

    # --- age lines ---
    w = s["wrinkles"]
    if w > 0:
        for sx in (-1, 1):  # nasolabial folds
            c.blend(c.line([(0.5 + sx * 0.09, 0.66), (0.5 + sx * 0.15, 0.75), (0.5 + sx * 0.16, 0.82)], 0.012, 0.004),
                    shadow, 0.6 * w)
            c.blend(c.line([(eyes[0 if sx < 0 else 1][0] - 0.02, 0.515), (eyes[0 if sx < 0 else 1][0] + 0.06, 0.52)],
                           0.008, 0.004), shadow, 0.55 * w)                           # eye bags
            c.blend(c.line([(0.5 + sx * 0.33, 0.45), (0.5 + sx * 0.39, 0.43)], 0.006, 0.003), shadow, 0.4 * w)
            c.blend(c.line([(0.5 + sx * 0.16, 0.84), (0.5 + sx * 0.2, 0.92)], 0.008, 0.004), shadow, 0.4 * w)  # jowl
        for k in range(3):  # forehead lines
            yy = 0.27 + k * 0.035
            c.blend(c.line([(0.32, yy + 0.005), (0.5, yy), (0.68, yy + 0.005)], 0.006, 0.003), shadow, 0.45 * w)
        rng = np.random.default_rng(s["seed"])
        for _ in range(int(6 * w)):  # age spots
            c.blend(c.ellipse(rng.uniform(0.25, 0.75), rng.uniform(0.25, 0.75), 0.012, 0.008, blur=0.004),
                    shadow, 0.35)

    if s["blush"] > 0:
        for sx in (-1, 1):
            c.blend(c.ellipse(0.5 + sx * 0.25, 0.62, 0.1, 0.05, blur=0.05), (220, 120, 120), s["blush"])

    # --- mouth ---
    my = 0.79
    mw = 0.13 * s["mouth_w"]
    ml = s["mouth_long"]
    up = s["smile"] * 0.015
    if s["stubble"] > 0:
        c.blend(c.poly([(0.5 - 0.3 * fw, 0.72), (0.5 + 0.3 * fw, 0.72), (0.5 + 0.2, 0.97), (0.5 - 0.2, 0.97)],
                       blur=0.04), (90, 70, 60), 0.25 * s["stubble"])
    c.shade(c.ellipse(0.5, my + 0.045, 0.08, 0.02, blur=0.02), 0.85)                  # under-lip shadow
    c.shade(c.ellipse(0.5, 0.92, 0.1, 0.04, blur=0.03), 1.08)                         # chin highlight
    upper = [(0.5 - mw, my), (0.5 - mw * 0.4, my - 0.022), (0.5, my - 0.016), (0.5 + mw * 0.4, my - 0.022),
             (0.5 + mw, my), (0.5, my + 0.004)]
    lower = [(0.5 - mw * 0.9, my), (0.5 + mw * 0.9, my), (0.5 + mw * 0.45, my + 0.028), (0.5 - mw * 0.45, my + 0.028)]
    c.blend(c.poly(upper, blur=0.008), mix(s["lips"], (60, 30, 30), 0.25), 0.9)
    c.blend(c.poly(lower, blur=0.008), s["lips"], 0.85)
    c.blend(c.ellipse(0.5, my + 0.013, mw * 0.4, 0.007, blur=0.005), mix(s["lips"], (255, 230, 220), 0.3), 0.5)
    if s["mouth_open"] > 0:
        c.blend(c.ellipse(0.5, my + 0.006, mw * (0.8 + ml * 0.6), 0.012 + 0.03 * s["mouth_open"], blur=0.004),
                (20, 8, 8), 1.0)
    line_pts = [(0.5 - mw - ml * 0.14, my - up + ml * 0.02), (0.5 - mw, my - up), (0.5, my + 0.002),
                (0.5 + mw, my - up), (0.5 + mw + ml * 0.14, my - up + ml * 0.02)]
    c.blend(c.line(line_pts, 0.012 + 0.004 * ml, 0.003), (58, 28, 26), 0.95)
    if ml > 0:  # corners that keep going - thin dark creases toward the ears
        for sx in (-1, 1):
            c.blend(c.line([(0.5 + sx * (mw + ml * 0.14), my + ml * 0.02),
                            (0.5 + sx * (mw + ml * 0.2), my - 0.01 + ml * 0.01)], 0.007, 0.002), (70, 34, 30), 0.8)

    if s["mustache"]:
        mc = (70, 64, 60)
        c.blend(c.poly([(0.5 - mw * 1.1, 0.77), (0.5 - 0.05, 0.715), (0.5, 0.725), (0.5 + 0.05, 0.715),
                        (0.5 + mw * 1.1, 0.77), (0.5, 0.75)], blur=0.006), mc, 0.95)
        c.streaks(c.poly([(0.5 - mw * 1.1, 0.77), (0.5, 0.715), (0.5 + mw * 1.1, 0.77), (0.5, 0.755)]),
                  mix(mc, (230, 230, 230), 0.4), 40, 0.02, 0.006, 0.4, 0.6)

    # --- eyes ---
    esz = s["eye_size"]
    wide = s["wide"]
    for i, (ex, eyy) in enumerate(eyes):
        rx = 0.082 * esz
        ry = 0.017 * esz * wide
        sx = -1 if i == 0 else 1
        # almond: inner corner lower, outer corner slightly up
        eye_poly = [(ex - sx * rx, eyy + 0.004), (ex - sx * rx * 0.3, eyy - ry), (ex + sx * rx * 0.5, eyy - ry * 0.95),
                    (ex + sx * rx, eyy - 0.004 * wide), (ex + sx * rx * 0.4, eyy + ry * 0.85),
                    (ex - sx * rx * 0.4, eyy + ry * 0.9)]
        if not s["lids"]:
            eye_poly = [(ex - sx * rx, eyy), (ex - sx * rx * 0.6, eyy - ry), (ex + sx * rx * 0.6, eyy - ry),
                        (ex + sx * rx, eyy), (ex + sx * rx * 0.6, eyy + ry), (ex - sx * rx * 0.6, eyy + ry)]
        em = c.poly(eye_poly, blur=0.004)
        c.blend(em, s["sclera"], 0.95)
        c.shade(em * np.clip((eyy - c.v) / ry + 0.3, 0, 1), 0.85)  # lid shadow on top of eyeball
        ir = 0.034 * esz * s["iris"]
        iy = eyy + (0.0 if not s["lids"] else ry * 0.15)
        c.blend(c.ellipse(ex, iy, ir, ir * 0.70, blur=0.003) * em,
                (48, 32, 26), 1.0)
        c.blend(c.ellipse(ex, iy, ir * 0.5, ir * 0.35, blur=0.002) * em, (10, 8, 8), 1.0)
        if s["lids"]:
            c.blend(em * np.clip((eyy - ry * 0.25 - c.v) / (ry * 0.5), 0, 1), (60, 46, 40), 0.65)
            c.blend(c.line([(ex - sx * rx, eyy + 0.003), (ex - sx * rx * 0.3, eyy - ry), (ex + sx * rx * 0.5, eyy - ry * 0.95),
                            (ex + sx * rx * 1.08, eyy - 0.006)], 0.024, 0.003), (18, 12, 10), 1.0)
            c.blend(c.line([(ex - sx * rx * 0.5, eyy + ry * 0.95), (ex + sx * rx * 0.6, eyy + ry * 0.8)], 0.006, 0.003),
                    shadow, 0.5)
            if s["double_lid"]:
                c.blend(c.line([(ex - sx * rx * 0.5, eyy - ry * 1.8), (ex + sx * rx * 0.7, eyy - ry * 1.7)], 0.006, 0.003),
                        shadow, 0.6)
        else:
            # lidless: thin pink rim all around, highlight gone
            c.blend(c.poly(eye_poly, blur=0.0) - c.poly([(x + (ex - x) * 0.12, y + (eyy - y) * 0.25) for x, y in eye_poly]),
                    (190, 120, 110), 0.5)
        c.blend(c.ellipse(ex - 0.012, iy - 0.006, 0.006, 0.004) * em, (250, 250, 245), 0.6 if s["lids"] else 0.0)

    # --- brows ---
    if s["brow"] > 0:
        for i, (ex, eyy) in enumerate(eyes):
            sx = -1 if i == 0 else 1
            by = eyy - 0.065 - (0.015 if not s["lids"] else 0) - 0.01 * (wide - 1)
            pts = [(ex - sx * 0.085, by + 0.012), (ex - sx * 0.02, by - 0.006), (ex + sx * 0.06, by - 0.004),
                   (ex + sx * 0.1, by + 0.012)]
            c.blend(c.line(pts, 0.03 * s["brow"], 0.006), s["brow_color"], 0.95)

    # --- hair over the forehead ---
    paint_front_hair(c, s)

    # --- accessories painted on the face ---
    if s["mask"] is not None:
        mk = c.poly([(0.08, 0.6), (0.3, 0.58), (0.5, 0.6), (0.7, 0.58), (0.92, 0.6), (0.86, 0.86), (0.6, 0.98),
                     (0.4, 0.98), (0.14, 0.86)], blur=0.006)
        c.blend(mk, s["mask"], 1.0)
        for k in range(3):  # pleats
            yy = 0.7 + k * 0.08
            c.shade(c.line([(0.16, yy), (0.5, yy + 0.01), (0.84, yy)], 0.01, 0.006) * mk, 0.78)
        c.shade(mk * np.clip((c.v - 0.6) / 0.4, 0, 1), 0.85)
        for sx in (-1, 1):  # ear loops
            c.blend(c.line([(0.5 + sx * 0.42, 0.62), (0.5 + sx * 0.47, 0.55)], 0.01, 0.002), mix(s["mask"], (40, 40, 40), 0.3), 0.9)
    if s["glasses"]:
        gc = (26, 24, 26)
        for (ex, eyy) in eyes:
            o = c.rect(ex - 0.115, eyy - 0.05, ex + 0.115, eyy + 0.05)
            inner = c.rect(ex - 0.098, eyy - 0.036, ex + 0.098, eyy + 0.036)
            c.blend(np.clip(o - inner, 0, 1), gc, 0.95)
            c.blend(inner, (200, 210, 220), 0.12)  # lens glare
        c.blend(c.line([(eyes[0][0] + 0.115, eyes[0][1] - 0.02), (eyes[1][0] - 0.115, eyes[1][1] - 0.02)], 0.014), gc, 0.95)
        for sx in (0, 1):
            ex = eyes[sx][0] + (-0.115 if sx == 0 else 0.115)
            c.blend(c.line([(ex, eyes[sx][1] - 0.03), (0.0 if sx == 0 else 1.0, 0.5)], 0.012), gc, 0.9)

    c.noise(3.0, 2)
    return c


def hair_shade(c, mask, s, strands=260):
    hc = s["hair_color"]
    c.blend(mask, hc, 1.0)
    c.streaks(mask, mix(hc, (140, 120, 110), 0.35), strands, 0.12, 0.005, 0.12, 0.6)
    c.streaks(mask, mix(hc, (0, 0, 0), 0.6), strands // 2, 0.1, 0.006, 0.12, 0.6)
    c.shade(mask * c.ellipse(0.4, 0.05, 0.3, 0.12, blur=0.05), 1.12)  # sheen


def paint_front_hair(c, s):
    st = s["hair"]
    fw = s["face_w"]
    if st == "messy":
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.55), (0.97, 0.5), (0.93, 0.34), (0.85, 0.26), (0.8, 0.33),
               (0.72, 0.25), (0.66, 0.34), (0.58, 0.26), (0.5, 0.36), (0.42, 0.27), (0.36, 0.33), (0.29, 0.25),
               (0.22, 0.31), (0.12, 0.27), (0.07, 0.36), (0.03, 0.5), (-0.1, 0.55)]
        hair_shade(c, c.poly(pts, blur=0.01), s)
    elif st == "short_neat":
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.5), (0.96, 0.46), (0.9, 0.28), (0.75, 0.22), (0.5, 0.21),
               (0.3, 0.23), (0.12, 0.28), (0.05, 0.46), (-0.1, 0.5)]
        hair_shade(c, c.poly(pts, blur=0.012), s)
    elif st == "side_part":
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.5), (0.96, 0.46), (0.9, 0.27), (0.7, 0.2), (0.4, 0.17),
               (0.28, 0.24), (0.14, 0.3), (0.05, 0.46), (-0.1, 0.5)]
        m = c.poly(pts, blur=0.01)
        hair_shade(c, m, s)
        c.blend(c.line([(0.33, 0.0), (0.31, 0.18)], 0.012, 0.004), mix(s["skin"], s["hair_color"], 0.5), 0.6)
    elif st == "buzz":
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.5), (0.95, 0.45), (0.9, 0.27), (0.7, 0.2), (0.5, 0.19),
               (0.3, 0.2), (0.1, 0.27), (0.05, 0.45), (-0.1, 0.5)]
        m = c.poly(pts, blur=0.015)
        c.blend(m, mix(s["skin"], (25, 22, 22), 0.7), 0.95)
        c.noise(0)  # keep
        rng = np.random.default_rng(s["seed"])
        dots = (rng.random((c.h, c.w)) < 0.35).astype(np.float32) * m
        c.blend(dots, (12, 10, 10), 0.6)
    elif st == "gray_thin":
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.5), (0.96, 0.45), (0.86, 0.2), (0.66, 0.1), (0.5, 0.12),
               (0.34, 0.1), (0.14, 0.2), (0.04, 0.45), (-0.1, 0.5)]
        m = c.poly(pts, blur=0.015)
        hair_shade(c, m, s, 200)
        c.streaks(m, (60, 56, 54), 120, 0.08, 0.005, 0.2, 0.5)
    elif st in ("long_bangs", "bob"):
        bang_y = 0.37 if st == "long_bangs" else 0.33
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 1.1), (0.92, 1.1), (0.9, 0.6), (0.86, 0.42), (0.8, bang_y),
               (0.66, bang_y + 0.015), (0.5, bang_y - 0.005), (0.34, bang_y + 0.015), (0.2, bang_y), (0.14, 0.42),
               (0.1, 0.6), (0.08, 1.1), (-0.1, 1.1)]
        if st == "bob":
            pts = [(x, min(y, 0.9)) for x, y in pts]
        m = c.poly(pts, blur=0.008)
        hair_shade(c, m, s, 320)
        # bangs strands direction downward
        c.streaks(m * c.rect(0.15, 0.1, 0.85, 0.4), mix(s["hair_color"], (0, 0, 0), 0.5), 80, 0.12, 0.006, 0.05, 0.7)
    elif st in ("bun", "ponytail"):
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.5), (0.96, 0.46), (0.9, 0.3), (0.72, 0.2), (0.5, 0.2),
               (0.28, 0.2), (0.1, 0.3), (0.04, 0.46), (-0.1, 0.5)]
        m = c.poly(pts, blur=0.01)
        hair_shade(c, m, s)
        # pulled-back combing lines
        c.streaks(m * c.rect(0.1, 0.0, 0.9, 0.3), mix(s["hair_color"], (120, 110, 100), 0.3), 60, 0.15, 0.004, 0.1,
                  0.5, direction=(0, -1))
    elif st == "scarf":
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.6), (0.96, 0.55), (0.88, 0.28), (0.7, 0.22), (0.5, 0.21),
               (0.3, 0.22), (0.12, 0.28), (0.04, 0.55), (-0.1, 0.6)]
        m = c.poly(pts, blur=0.01)
        hair_shade(c, m, s, 150)


# --------------------------------------------------------------------------------------------
# Wrap (sides + back). u: 0 = right side of head (near right ear), 0.5 = back, 1 = left side.
# --------------------------------------------------------------------------------------------
def paint_wrap(s):
    skin = s["skin"]
    c = Canvas(WW, WH, skin, seed=s["seed"] + 100)
    st = s["hair"]
    # ears at u=0.1 / 0.9
    for ex in (0.1, 0.9):
        c.blend(c.ellipse(ex, 0.55, 0.05, 0.1, blur=0.01), mix(skin, (170, 90, 80), 0.2), 0.9)
        c.shade(c.ellipse(ex, 0.55, 0.02, 0.06, blur=0.01), 0.7)
    c.shade(np.clip((c.v - 0.75) / 0.25, 0, 1), 0.8)
    if st in ("messy", "short_neat", "side_part", "gray_thin"):
        nape = 0.8
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.42), (0.95, 0.4), (0.86, 0.5), (0.8, nape), (0.6, nape + 0.04),
               (0.4, nape + 0.03), (0.2, nape), (0.14, 0.5), (0.05, 0.4), (-0.1, 0.42)]
        if st == "messy":
            pts[6:9] = [(0.65, nape + 0.08), (0.55, nape + 0.02), (0.45, nape + 0.09), (0.35, nape + 0.03)]
        hair_shade(c, c.poly(pts, blur=0.01), s, 400)
    elif st == "buzz":
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.4), (0.86, 0.45), (0.8, 0.78), (0.2, 0.78), (0.14, 0.45), (-0.1, 0.4)]
        m = c.poly(pts, blur=0.02)
        c.blend(m, mix(skin, (25, 22, 22), 0.7), 0.95)
        rng = np.random.default_rng(s["seed"])
        c.blend((rng.random((c.h, c.w)) < 0.35).astype(np.float32) * m, (12, 10, 10), 0.6)
    elif st in ("long_bangs", "bob", "scarf"):
        bottom = 1.2 if st == "long_bangs" else 0.95
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, bottom), (-0.1, bottom)]
        hair_shade(c, c.poly(pts), s, 500)
        if st == "bob":
            c.shade(c.rect(0, 0.85, 1, 1), 0.7)
    elif st in ("bun", "ponytail"):
        pts = [(-0.1, -0.1), (1.1, -0.1), (1.1, 0.42), (0.9, 0.44), (0.8, 0.82), (0.2, 0.82), (0.1, 0.44), (-0.1, 0.42)]
        m = c.poly(pts, blur=0.01)
        hair_shade(c, m, s, 300)
        c.streaks(m, mix(s["hair_color"], (0, 0, 0), 0.5), 100, 0.2, 0.004, 0.05, 0.6, direction=(0, -1))
    # always-hair patch for hair meshes (x 80..112 of atlas = u 0.25..0.75, y 0..14 = v 0..0.22)
    patch = c.rect(0.25, 0.0, 0.75, 0.22)
    if st == "buzz":
        pass
    else:
        hair_shade(c, patch, s, 120)
    c.noise(3.0, 2)
    return c


def build_head(name, s):
    front = finalize(paint_front(s).image(), (64, 64), grain=2.5, seed=s["seed"])
    wrap = finalize(paint_wrap(s).image(), (64, 64), grain=2.5, seed=s["seed"] + 1)
    atlas = Image.new("RGB", (128, 64))
    atlas.paste(front, (0, 0))
    atlas.paste(wrap, (64, 0))
    return atlas, front


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for name, s in CHARS.items():
        if only and name not in only:
            continue
        atlas, front = build_head(name, s)
        atlas.save(os.path.join(OUT, f"head_{name}.png"))
        front.save(os.path.join(OUT, f"face_{name}.png"))
        if name in DISTORT:
            d = dict(s)
            d.update(DISTORT[name])
            atlas_d, front_d = build_head(name, d)
            atlas_d.save(os.path.join(OUT, f"head_{name}_distort.png"))
            front_d.save(os.path.join(OUT, f"face_{name}_distort.png"))
        print("face", name)


if __name__ == "__main__":
    main()
