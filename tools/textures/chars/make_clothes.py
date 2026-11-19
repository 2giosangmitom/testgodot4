#!/usr/bin/env python3
"""Clothing textures + per-character 128x128 body atlases (layout: atlas_layout.json).

Output (assets/textures/chars/):
  body_<name>.png        body atlas used by the character glb
  body_nam_store.png     Nam in the store uniform (swap-in texture for night-shift cutscenes)
  cloth_<garment>.png    64x64 swatches of each garment (front view of the chest/legs cells)

Run: python3 tools/textures/chars/make_clothes.py
"""
import os
import sys
import json
import zlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from psxpaint import Canvas, finalize  # noqa: E402
from make_faces import CHARS as FACES  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "chars")
LAYOUT = json.load(open(os.path.join(HERE, "atlas_layout.json")))
CELLS = LAYOUT["cells"]
S = 4  # paint scale
FONT = "/usr/share/fonts/noto/NotoSans-Bold.ttf"


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


class Atlas:
    def __init__(self, seed=0):
        self.c = Canvas(128 * S, 128 * S, (40, 40, 40), seed=seed)
        self.rng = np.random.default_rng(seed)

    def cellmask(self, cell):
        x0, y0, x1, y1 = CELLS[cell]
        return self.c.rect(x0 / 128, y0 / 128, (x1 - 0.01) / 128, (y1 - 0.01) / 128)

    def L(self, cell, x, y):
        x0, y0, x1, y1 = CELLS[cell]
        return ((x0 + x * (x1 - x0)) / 128, (y0 + y * (y1 - y0)) / 128)

    def size(self, cell):
        x0, y0, x1, y1 = CELLS[cell]
        return (x1 - x0) / 128, (y1 - y0) / 128

    def fill(self, cell, color):
        self.c.blend(self.cellmask(cell), color)

    def rect(self, cell, x0, y0, x1, y1, color, alpha=1.0, blur=0.0, wrap=True):
        m = np.zeros_like(self.c.u)
        shifts = (-1, 0, 1) if wrap else (0,)
        for sh in shifts:
            a = self.L(cell, x0 + sh, y0)
            b = self.L(cell, x1 + sh, y1)
            m = np.maximum(m, self.c.rect(a[0], a[1], b[0], b[1], blur=blur))
        self.c.blend(m * self.cellmask(cell), color, alpha)

    def poly(self, cell, pts, color, alpha=1.0, blur=0.0):
        m = self.c.poly([self.L(cell, x, y) for x, y in pts], blur=blur)
        self.c.blend(m * self.cellmask(cell), color, alpha)

    def line(self, cell, pts, width, color, alpha=1.0):
        m = self.c.line([self.L(cell, x, y) for x, y in pts], width, blur=0.002)
        self.c.blend(m * self.cellmask(cell), color, alpha)

    def dot(self, cell, x, y, r, color, alpha=1.0):
        cx, cy = self.L(cell, x, y)
        m = self.c.ellipse(cx, cy, r, r)
        self.c.blend(m * self.cellmask(cell), color, alpha)

    def shade_cyl(self, cell, strength=0.25, top=0.0, bottom=0.0):
        """Darken the sides/back of a tube cell (lit from the front)."""
        x0, y0, x1, y1 = CELLS[cell]
        cu = (self.c.u * 128 - x0) / (x1 - x0)
        cv = (self.c.v * 128 - y0) / (y1 - y0)
        f = np.abs(cu - 0.5) * 2  # 0 front, 1 back
        m = self.cellmask(cell)
        self.c.shade(m * f ** 1.5, 1 - strength)
        if top:
            self.c.shade(m * np.clip(1 - cv * 4, 0, 1), 1 - top)
        if bottom:
            self.c.shade(m * np.clip((cv - 0.75) * 4, 0, 1), 1 - bottom)

    def folds(self, cell, color, n=10, vertical=True, alpha=0.25):
        for _ in range(n):
            x = self.rng.uniform(0, 1)
            y = self.rng.uniform(0, 0.6)
            ln = self.rng.uniform(0.2, 0.6)
            if vertical:
                self.line(cell, [(x, y), (x + self.rng.normal(0, 0.03), y + ln)], 0.004, color, alpha)
            else:
                self.line(cell, [(x, y), (x + ln * 0.5, y + self.rng.normal(0, 0.05))], 0.004, color, alpha)

    def noise_cell(self, cell, amount):
        m = self.cellmask(cell)
        n = self.rng.normal(0, amount, self.c.u.shape).astype(np.float32)
        self.c.px += (n * m)[..., None]

    def text(self, cell, x, y, txt, size_px, color, anchor="mm"):
        """Text in atlas pixels*S (painted then blended)."""
        img = Image.new("L", (self.c.w, self.c.h), 0)
        d = ImageDraw.Draw(img)
        font = ImageFont.truetype(FONT, int(size_px * S))
        px, py = self.L(cell, x, y)
        d.text((px * self.c.w, py * self.c.h), txt, font=font, fill=255, anchor=anchor)
        m = np.asarray(img, dtype=np.float32) / 255
        self.c.blend(m * self.cellmask(cell), color)

    def image(self):
        return finalize(self.c.image(), (128, 128), grain=2.0, seed=3, sharpen=False)


# --------------------------------------------------------------------------------------------
# Garments
# --------------------------------------------------------------------------------------------
TOPS = {
    "school_shirt": dict(color=(222, 224, 222), kind="shirt", sleeve="short", tucked=True),
    "school_shirt_f": dict(color=(228, 228, 226), kind="shirt", sleeve="short", tucked=True, fitted=True),
    "store_polo": dict(color=(228, 112, 30), kind="polo", sleeve="short", tucked=False, logo=True),
    "guard": dict(color=(176, 156, 110), kind="guard", sleeve="long", tucked=True),
    "tshirt_gray": dict(color=(118, 124, 120), kind="tee", sleeve="short", tucked=False, print_color=(190, 60, 50)),
    "tshirt_navy": dict(color=(44, 52, 82), kind="tee", sleeve="short", tucked=False, print_color=(200, 200, 190)),
    "tshirt_pink": dict(color=(222, 170, 176), kind="tee", sleeve="short", tucked=False, print_color=(250, 250, 250)),
    "shirt_blue_long": dict(color=(160, 182, 206), kind="shirt", sleeve="long", tucked=True),
    "ao_ba_ba": dict(color=(96, 70, 52), kind="baba", sleeve="long", tucked=False),
    "floral_blouse": dict(color=(150, 92, 110), kind="floral", sleeve="long", tucked=False),
    "jacket_brown": dict(color=(90, 66, 46), kind="jacket", sleeve="long", tucked=False),
    "raincoat": dict(color=(56, 110, 160), kind="raincoat", sleeve="long", tucked=False),
    "faded_shirt": dict(color=(196, 198, 190), kind="shirt", sleeve="long", tucked=True, buttoned_top=True),
}
BOTTOMS = {
    "trousers_black": dict(color=(34, 34, 38), kind="trousers"),
    "trousers_gray": dict(color=(70, 72, 76), kind="trousers"),
    "khaki": dict(color=(160, 140, 98), kind="trousers"),
    "jeans": dict(color=(58, 80, 120), kind="jeans"),
    "silk_black": dict(color=(24, 22, 24), kind="silk"),
    "shorts_black": dict(color=(30, 30, 34), kind="shorts"),
    "skirt_navy": dict(color=(36, 42, 70), kind="skirt"),
}
SHOES = ["sandals", "flipflops", "sneakers", "leather", "flats", "barefoot"]


def paint_skin(a, skin):
    for cell in ("hand", "neck", "skin"):
        a.fill(cell, skin)
    a.shade_cyl("hand", 0.25)
    for k in range(3):  # finger grooves on the mitten
        x = 0.38 + k * 0.08
        a.line("hand", [(x, 0.55), (x, 1.0)], 0.003, mix(skin, (60, 30, 20), 0.5), 0.5)
    a.shade_cyl("neck", 0.3, top=0.35)
    a.fill("black", (18, 18, 20))


def paint_top(a, t, skin):
    col = t["color"]
    dark = mix(col, (0, 0, 0), 0.35)
    light = mix(col, (255, 255, 255), 0.3)
    for cell in ("chest", "abdomen", "upper_arm", "lower_arm"):
        a.fill(cell, col)
    kind = t["kind"]
    # sleeves
    if t["sleeve"] == "short":
        a.rect("upper_arm", -0.1, 0.62, 1.1, 1.0, skin)
        a.rect("upper_arm", -0.1, 0.58, 1.1, 0.64, dark, 0.6)
        a.fill("lower_arm", skin)
    else:
        a.rect("lower_arm", -0.1, 0.86, 1.1, 1.0, dark if kind != "raincoat" else col, 0.7)  # cuff
        a.rect("lower_arm", -0.1, 0.84, 1.1, 0.87, mix(dark, (0, 0, 0), 0.3), 0.6)
    # hem over hips when untucked
    if not t["tucked"]:
        hem = 0.45 if kind not in ("raincoat", "baba", "floral") else 0.7
        a.rect("hips", -0.1, 0.0, 1.1, hem, col)
        a.rect("hips", -0.1, hem - 0.06, 1.1, hem, dark, 0.7)

    if kind in ("shirt", "guard"):
        # collar + placket + buttons
        a.poly("chest", [(0.38, 0.0), (0.5, 0.28), (0.62, 0.0)], skin if not t.get("buttoned_top") else col)
        a.poly("chest", [(0.36, 0.0), (0.47, 0.32), (0.5, 0.26), (0.42, 0.0)], light)
        a.poly("chest", [(0.64, 0.0), (0.53, 0.32), (0.5, 0.26), (0.58, 0.0)], light)
        a.line("chest", [(0.36, 0.0), (0.47, 0.32)], 0.003, dark, 0.7)
        a.line("chest", [(0.64, 0.0), (0.53, 0.32)], 0.003, dark, 0.7)
        if t.get("buttoned_top"):
            a.poly("chest", [(0.4, 0.0), (0.5, 0.12), (0.6, 0.0)], light)
        for cell, ys in (("chest", (0.4, 0.75)), ("abdomen", (0.2, 0.75))):
            a.line(cell, [(0.5, 0.0), (0.5, 1.0)], 0.004, dark, 0.5)
            for y in ys:
                a.dot(cell, 0.51, y, 0.004, light if kind == "shirt" else (90, 70, 40), 0.9)
        a.rect("chest", 0.56, 0.42, 0.68, 0.8, dark, 0.35)  # pocket
        a.line("chest", [(0.56, 0.42), (0.68, 0.42)], 0.003, dark, 0.8)
        if kind == "guard":
            a.rect("chest", 0.32, 0.38, 0.44, 0.8, dark, 0.35)
            a.rect("chest", 0.31, 0.36, 0.45, 0.48, mix(col, (0, 0, 0), 0.2))   # flaps
            a.rect("chest", 0.55, 0.36, 0.69, 0.48, mix(col, (0, 0, 0), 0.2))
            a.rect("chest", 0.2, 0.0, 0.3, 0.12, mix(col, (40, 30, 10), 0.4))   # epaulettes
            a.rect("chest", 0.7, 0.0, 0.8, 0.12, mix(col, (40, 30, 10), 0.4))
            a.rect("chest", 0.33, 0.55, 0.43, 0.62, (30, 40, 90))               # name tag
            a.rect("upper_arm", 0.2, 0.15, 0.32, 0.4, (40, 50, 100))            # shoulder patch
            a.rect("upper_arm", 0.68, 0.15, 0.8, 0.4, (40, 50, 100))
            a.dot("upper_arm", 0.26, 0.27, 0.006, (220, 190, 60))
            a.dot("upper_arm", 0.74, 0.27, 0.006, (220, 190, 60))
        a.folds("chest", dark, 6)
        a.folds("abdomen", dark, 8)
    elif kind == "polo":
        a.poly("chest", [(0.4, 0.0), (0.5, 0.1), (0.6, 0.0)], skin)
        a.poly("chest", [(0.33, 0.0), (0.48, 0.22), (0.5, 0.12), (0.4, 0.0)], (245, 245, 240))
        a.poly("chest", [(0.67, 0.0), (0.52, 0.22), (0.5, 0.12), (0.6, 0.0)], (245, 245, 240))
        a.rect("chest", 0.47, 0.1, 0.53, 0.5, dark, 0.4)
        a.dot("chest", 0.5, 0.25, 0.003, (245, 245, 240))
        a.dot("chest", 0.5, 0.4, 0.003, (245, 245, 240))
        # "Ánh Dương" logo: yellow sun + white wordmark on the left chest, big on the back
        a.dot("chest", 0.62, 0.52, 0.016, (255, 214, 60))
        a.rect("chest", 0.655, 0.47, 0.73, 0.58, (250, 250, 245))
        a.rect("abdomen", -0.1, 0.0, 1.1, 0.12, (250, 250, 245), 0.9)  # white stripe band
        a.text("chest", 0.0, 0.62, "ÁNH DƯƠNG", 3.6, (250, 250, 245))
        a.text("chest", 1.0, 0.62, "ÁNH DƯƠNG", 3.6, (250, 250, 245))
        a.dot("chest", 0.0, 0.32, 0.02, (255, 214, 60))
        a.dot("chest", 1.0, 0.32, 0.02, (255, 214, 60))
        a.rect("upper_arm", -0.1, 0.5, 1.1, 0.6, (250, 250, 245))
        a.folds("abdomen", dark, 8)
    elif kind == "tee":
        a.poly("chest", [(0.4, 0.0), (0.5, 0.14), (0.6, 0.0)], skin)
        a.line("chest", [(0.39, 0.0), (0.5, 0.15), (0.61, 0.0)], 0.005, dark, 0.8)
        pc = t["print_color"]
        a.rect("chest", 0.42, 0.42, 0.58, 0.9, pc, 0.85)  # print
        a.rect("chest", 0.45, 0.5, 0.55, 0.62, col, 0.9)
        a.text("chest", 0.5, 0.78, "HN", 4.5, col)
        a.folds("chest", dark, 6)
        a.folds("abdomen", dark, 10)
    elif kind == "baba":
        a.poly("chest", [(0.42, 0.0), (0.5, 0.1), (0.58, 0.0)], skin)
        a.line("chest", [(0.5, 0.08), (0.5, 1.0)], 0.004, dark, 0.7)
        a.line("abdomen", [(0.5, 0.0), (0.5, 1.0)], 0.004, dark, 0.7)
        for y in (0.3, 0.6, 0.9):
            a.dot("chest", 0.5, y, 0.004, (30, 20, 15))
        a.rect("abdomen", 0.3, 0.3, 0.42, 0.9, dark, 0.4)  # low pockets
        a.rect("abdomen", 0.58, 0.3, 0.7, 0.9, dark, 0.4)
        a.folds("chest", dark, 10)
        a.folds("abdomen", dark, 10)
    elif kind == "floral":
        a.poly("chest", [(0.4, 0.0), (0.5, 0.18), (0.6, 0.0)], skin)
        for cell in ("chest", "abdomen", "upper_arm", "lower_arm", "hips"):
            for _ in range(40 if cell in ("chest", "abdomen") else 18):
                x, y = a.rng.uniform(-0.05, 1.05), a.rng.uniform(0, 1)
                if cell == "hips" and y > 0.65:
                    continue
                if cell == "lower_arm" and y > 0.85:
                    continue
                a.dot(cell, x, y, 0.006, a.rng.choice([(230, 220, 200), (240, 200, 90), (120, 160, 120)]), 0.85)
        a.folds("chest", dark, 8)
    elif kind == "jacket":
        a.poly("chest", [(0.42, 0.0), (0.5, 0.2), (0.58, 0.0)], (60, 60, 64))
        for cell in ("chest", "abdomen"):
            a.line(cell, [(0.5, 0.0), (0.5, 1.0)], 0.006, (150, 150, 150), 0.9)  # zipper
        a.rect("abdomen", 0.3, 0.3, 0.42, 0.7, dark, 0.5)
        a.rect("abdomen", 0.58, 0.3, 0.7, 0.7, dark, 0.5)
        a.rect("chest", -0.1, 0.0, 1.1, 0.06, dark, 0.6)
        a.folds("chest", dark, 12)
        a.folds("abdomen", dark, 12)
        a.folds("upper_arm", dark, 6)
        a.folds("lower_arm", dark, 6)
    elif kind == "raincoat":
        a.poly("chest", [(0.42, 0.0), (0.5, 0.12), (0.58, 0.0)], skin)
        a.fill("skirt", col)
        a.rect("skirt", -0.1, 0.92, 1.1, 1.0, dark, 0.8)
        for cell in ("chest", "abdomen", "skirt", "upper_arm", "hips"):  # shiny plastic highlights + wrinkles
            for _ in range(10):
                x, y = a.rng.uniform(0, 1), a.rng.uniform(0, 0.8)
                a.line(cell, [(x, y), (x + a.rng.normal(0, 0.05), y + a.rng.uniform(0.1, 0.4))], 0.004,
                       light, 0.6)
            a.folds(cell, dark, 8, alpha=0.5)
    # shading
    a.shade_cyl("chest", 0.3, top=0.15)
    a.shade_cyl("abdomen", 0.3)
    a.shade_cyl("upper_arm", 0.3)
    a.shade_cyl("lower_arm", 0.3)
    if kind == "raincoat":
        a.shade_cyl("skirt", 0.3)


def paint_bottom(a, b, skin):
    col = b["color"]
    dark = mix(col, (0, 0, 0), 0.4)
    light = mix(col, (255, 255, 255), 0.18)
    kind = b["kind"]
    a.fill("hips", col)
    for cell in ("upper_leg", "lower_leg"):
        a.fill(cell, col)
    a.rect("hips", -0.1, 0.0, 1.1, 0.14, (36, 26, 20))  # belt
    a.rect("hips", 0.47, 0.0, 0.53, 0.14, (170, 160, 130))  # buckle
    a.line("hips", [(0.5, 0.14), (0.5, 0.8)], 0.004, dark, 0.7)  # fly
    a.line("hips", [(0.33, 0.14), (0.27, 0.6)], 0.004, dark, 0.6)
    a.line("hips", [(0.67, 0.14), (0.73, 0.6)], 0.004, dark, 0.6)
    for cell in ("upper_leg", "lower_leg"):
        a.line(cell, [(0.5, 0.0), (0.5, 1.0)], 0.003, light, 0.4)  # crease
        a.line(cell, [(0.25, 0.0), (0.25, 1.0)], 0.003, dark, 0.5)  # seams
        a.line(cell, [(0.75, 0.0), (0.75, 1.0)], 0.003, dark, 0.5)
    if kind == "jeans":
        for cell in ("upper_leg", "lower_leg", "hips"):
            for _ in range(160):
                x, y = a.rng.uniform(0, 1), a.rng.uniform(0, 1)
                a.line(cell, [(x, y), (x + 0.03, y + 0.005)], 0.002, mix(col, (200, 210, 230), 0.4), 0.35)
        a.rect("upper_leg", 0.38, 0.2, 0.62, 0.9, mix(col, (200, 210, 230), 0.25), 0.6, blur=0.01)  # faded thighs
        a.line("hips", [(0.27, 0.6), (0.4, 0.62)], 0.003, (190, 150, 70), 0.6)
        a.rect("lower_leg", -0.1, 0.9, 1.1, 1.0, dark, 0.6)
    elif kind == "silk":
        for cell in ("upper_leg", "lower_leg"):
            for _ in range(6):
                x = a.rng.uniform(0, 1)
                a.line(cell, [(x, 0), (x + 0.04, 1)], 0.01, (70, 70, 80), 0.35)
        a.rect("lower_leg", -0.1, 0.94, 1.1, 1.0, skin)  # wide, short trouser leg shows ankle
        a.rect("hips", -0.1, 0.0, 1.1, 0.14, col)
    elif kind == "shorts":
        a.rect("upper_leg", -0.1, 0.55, 1.1, 1.0, skin)
        a.rect("upper_leg", -0.1, 0.5, 1.1, 0.56, dark)
        a.fill("lower_leg", skin)
        a.rect("hips", -0.1, 0.0, 1.1, 0.14, mix(col, (255, 255, 255), 0.1))  # elastic waist
        a.line("hips", [(0.47, 0.14), (0.45, 0.4)], 0.003, (220, 220, 220), 0.8)
        a.line("hips", [(0.53, 0.14), (0.55, 0.4)], 0.003, (220, 220, 220), 0.8)
        a.rect("hips", 0.24, 0.14, 0.27, 1.0, (220, 220, 220), 0.6)  # side stripes
        a.rect("hips", 0.73, 0.14, 0.76, 1.0, (220, 220, 220), 0.6)
    elif kind == "skirt":
        a.fill("upper_leg", skin)
        a.fill("lower_leg", skin)
        a.fill("skirt", col)
        for k in range(16):  # pleats
            a.line("skirt", [(k / 16, 0.0), (k / 16, 1.0)], 0.003, dark, 0.6)
        a.rect("skirt", -0.1, 0.94, 1.1, 1.0, dark, 0.5)
        a.rect("hips", -0.1, 0.0, 1.1, 1.0, col)
        a.shade_cyl("skirt", 0.3)
    for cell in ("upper_leg", "lower_leg"):
        a.shade_cyl(cell, 0.3)
        a.folds(cell, dark, 6)
    a.shade_cyl("hips", 0.3)


def paint_shoes(a, kind, skin):
    a.fill("foot", skin)
    a.shade_cyl("foot", 0.35)
    if kind == "sandals":  # dép quai hậu: dark sole, two straps + heel strap
        a.rect("foot", -0.1, 0.0, 0.2, 1.0, (40, 34, 30))
        a.rect("foot", 0.8, 0.0, 1.1, 1.0, (40, 34, 30))
        a.rect("foot", -0.1, 0.35, 1.1, 0.45, (60, 48, 40))
        a.rect("foot", -0.1, 0.65, 1.1, 0.75, (60, 48, 40))
        a.rect("foot", 0.15, 0.0, 0.85, 0.1, (60, 48, 40))
    elif kind == "flipflops":
        a.rect("foot", -0.1, 0.0, 0.18, 1.0, (40, 70, 140))
        a.rect("foot", 0.82, 0.0, 1.1, 1.0, (40, 70, 140))
        a.line("foot", [(0.3, 0.6), (0.5, 0.85), (0.7, 0.6)], 0.006, (240, 240, 240), 0.9)
    elif kind == "sneakers":
        a.fill("foot", (226, 226, 222))
        a.rect("foot", -0.1, 0.0, 0.18, 1.0, (120, 120, 118))
        a.rect("foot", 0.82, 0.0, 1.1, 1.0, (120, 120, 118))
        for k in range(4):
            a.line("foot", [(0.42, 0.35 + k * 0.1), (0.58, 0.35 + k * 0.1)], 0.003, (90, 90, 100), 0.9)
        a.line("foot", [(0.3, 0.3), (0.62, 0.9)], 0.004, (40, 80, 160), 0.8)
        a.shade_cyl("foot", 0.3)
    elif kind in ("leather", "flats"):
        a.fill("foot", (26, 24, 24))
        a.rect("foot", 0.4, 0.3, 0.6, 0.8, (60, 58, 58), 0.7, blur=0.01)
        if kind == "flats":
            a.rect("foot", 0.3, 0.0, 0.7, 0.45, skin)
    elif kind == "barefoot":
        a.fill("foot", mix(skin, (200, 200, 190), 0.25))
        a.rect("foot", -0.1, 0.0, 0.18, 1.0, mix(skin, (40, 30, 30), 0.5))
        a.rect("foot", 0.82, 0.0, 1.1, 1.0, mix(skin, (40, 30, 30), 0.5))
        a.shade_cyl("foot", 0.3)


def paint_acc(a, acc):
    # nón lá (conical hat): straw rings
    a.fill("hat", (206, 190, 140))
    for k in range(14):
        y = k / 14
        a.line("hat", [(0, y), (1, y)], 0.003, (150, 130, 90), 0.8)
    for _ in range(100):
        x, y = a.rng.uniform(0, 1), a.rng.uniform(0, 1)
        a.line("hat", [(x, y), (x + 0.02, y + 0.06)], 0.002, (236, 224, 180), 0.6)
    a.rect("hat", -0.1, 0.92, 1.1, 1.0, (130, 110, 70))
    # headscarf (khăn): dark brown with faint check
    a.fill("scarf", (70, 48, 40))
    for k in range(10):
        a.line("scarf", [(k / 10, 0), (k / 10, 1)], 0.004, (96, 64, 52), 0.6)
        a.line("scarf", [(0, k / 10), (1, k / 10)], 0.004, (52, 36, 30), 0.6)
    # backpack
    bc = acc.get("bag_color", (40, 48, 70))
    a.fill("bag", bc)
    a.rect("bag", 0.2, 0.45, 0.8, 0.9, mix(bc, (0, 0, 0), 0.3))
    a.line("bag", [(0.2, 0.45), (0.8, 0.45)], 0.004, (160, 160, 160), 0.9)
    a.rect("bag", 0.0, 0.0, 0.12, 1.0, (20, 20, 22))
    a.rect("bag", 0.88, 0.0, 1.0, 1.0, (20, 20, 22))


# --------------------------------------------------------------------------------------------
# Characters
# --------------------------------------------------------------------------------------------
OUTFITS = {
    "nam": dict(top="school_shirt", bottom="trousers_black", shoes="sandals"),
    "nam_store": dict(face="nam", top="store_polo", bottom="trousers_black", shoes="sandals"),
    "hung": dict(top="tshirt_gray", bottom="shorts_black", shoes="flipflops"),
    "linh": dict(top="school_shirt_f", bottom="jeans", shoes="sneakers"),
    "bac_tu": dict(top="guard", bottom="khaki", shoes="leather"),
    "chi_hanh": dict(top="store_polo", bottom="trousers_black", shoes="flats"),
    "thay_khai": dict(top="shirt_blue_long", bottom="trousers_gray", shoes="leather"),
    "ba_cu": dict(top="ao_ba_ba", bottom="silk_black", shoes="sandals"),
    "student_m1": dict(top="tshirt_navy", bottom="jeans", shoes="sneakers", bag_color=(140, 40, 40)),
    "student_m2": dict(top="school_shirt", bottom="trousers_black", shoes="sandals", bag_color=(40, 48, 70)),
    "student_f1": dict(top="tshirt_pink", bottom="jeans", shoes="sneakers", bag_color=(230, 230, 220)),
    "student_f2": dict(top="school_shirt_f", bottom="skirt_navy", shoes="sandals"),
    "passerby_m1": dict(top="raincoat", bottom="trousers_gray", shoes="flipflops"),
    "passerby_m2": dict(top="jacket_brown", bottom="jeans", shoes="sneakers"),
    "passerby_f1": dict(top="floral_blouse", bottom="silk_black", shoes="sandals"),
    "gazer": dict(top="faded_shirt", bottom="trousers_gray", shoes="barefoot"),
    "mimic_hung": dict(top="tshirt_gray", bottom="shorts_black", shoes="flipflops"),
    "mimic_linh": dict(top="school_shirt_f", bottom="jeans", shoes="sneakers"),
}


def build_body(name, o):
    face = FACES[o.get("face", name)]
    skin = face["skin"]
    a = Atlas(seed=zlib.crc32(name.encode()) & 0xFFFF)
    a.c.px[:] = np.array(skin, dtype=np.float32)
    paint_skin(a, skin)
    paint_bottom(a, BOTTOMS[o["bottom"]], skin)
    paint_top(a, TOPS[o["top"]], skin)
    paint_shoes(a, o["shoes"], skin)
    paint_acc(a, o)
    if name == "gazer":  # pale, slightly grey-green
        a.c.px = a.c.px * np.array([0.92, 0.96, 0.94], dtype=np.float32)
    return a.image()


def swatches():
    for tname, t in TOPS.items():
        a = Atlas(seed=7)
        paint_top(a, t, (210, 165, 128))
        img = a.image()
        x0, y0, x1, y1 = CELLS["chest"]
        _, ya, _, yb = CELLS["abdomen"]
        sw = img.crop((x0, y0, x1, yb)).resize((64, 64), Image.NEAREST)
        sw.save(os.path.join(OUT, f"cloth_{tname}.png"))
    for bname, b in BOTTOMS.items():
        a = Atlas(seed=8)
        paint_bottom(a, b, (210, 165, 128))
        img = a.image()
        x0, y0, x1, y1 = CELLS["upper_leg"]
        sw = img.crop((x0, y0, x1 + 32, y1)).resize((64, 64), Image.NEAREST)
        sw.save(os.path.join(OUT, f"cloth_{bname}.png"))
    for s in SHOES:
        a = Atlas(seed=9)
        a.c.px[:] = 0
        paint_shoes(a, s, (210, 165, 128))
        img = a.image()
        x0, y0, x1, y1 = CELLS["foot"]
        img.crop((x0, y0, x1, y1)).resize((64, 32), Image.NEAREST).save(os.path.join(OUT, f"cloth_shoes_{s}.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for name, o in OUTFITS.items():
        if only and name not in only:
            continue
        build_body(name, o).save(os.path.join(OUT, f"body_{name}.png"))
        print("body", name)
    if not only:
        swatches()


if __name__ == "__main__":
    main()
