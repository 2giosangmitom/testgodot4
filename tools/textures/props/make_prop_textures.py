#!/usr/bin/env python3
"""PSX prop textures (32-128 px, RGB565 + dither) with fictional Vietnamese brands.

Layouts used by tools/blender/props/build_props.py:
  - BOX layout (128x64): front(-Y) 0,0-48,40 | back(+Y) 48,0-96,40 | +X 96,0-128,40 |
                          -X 0,40-32,64 | top 32,40-80,64 | bottom 80,40-128,64
    Product barcodes are printed on the BACK face (+Y in Blender = -Z in Godot).
  - CYL layout (64x64): side 0,0-64,48 (u=0.5 front/-Y, u=0/1 back/+Y), top cap 0,48-16,64,
    bottom cap 16,48-32,64, extra 32,48-64,64. Barcode centered on the back (wraps the seam).
  - props_palette.png 64x64: 8x8 swatches, names in palette.json.

Run: python3 tools/textures/props/make_prop_textures.py
"""
import json
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "textures", "chars"))
from psxpaint import finalize  # noqa: E402

OUT = os.path.join(ROOT, "assets", "textures", "props")
FONT_B = "/usr/share/fonts/noto/NotoSans-Bold.ttf"
FONT_K = "/usr/share/fonts/noto/NotoSans-Black.ttf"
FONT_R = "/usr/share/fonts/noto/NotoSans-Regular.ttf"
S = 4  # paint scale
RNG = np.random.default_rng(5)

BOX = {"front": (0, 0, 48, 40), "back": (48, 0, 96, 40), "px": (96, 0, 128, 40), "nx": (0, 40, 32, 64),
       "top": (32, 40, 80, 64), "bottom": (80, 40, 128, 64)}
CYL = {"side": (0, 0, 64, 48), "top": (0, 48, 16, 64), "bottom": (16, 48, 32, 64), "extra": (32, 48, 64, 64)}

PALETTE = [
    ["red_plastic", "blue_plastic", "green_plastic", "white_plastic", "black_plastic", "gray_plastic", "pink_plastic", "yellow_plastic"],
    ["steel", "aluminum", "dark_steel", "brass", "chrome", "rust", "copper", "gold"],
    ["wood_light", "wood_dark", "wood_red", "bamboo", "straw", "rope", "cardboard", "paper"],
    ["cream_ceramic", "white_ceramic", "blue_ceramic", "red_lacquer", "sand", "ash", "wax", "cloth_gray"],
    ["glass", "water", "screen_dark", "rubber", "foam", "mop_strands", "kraft", "foil"],
    ["orange", "purple", "brown", "dark_red", "beige", "black", "white", "mid_gray"],
    ["red_window", "led_green", "flame_core", "flame_outer", "ember", "soot", "brick", "cement"],
    ["navy", "teal", "olive", "maroon", "khaki", "lilac", "mint", "salmon"],
]
COLORS = {
    "red_plastic": (190, 34, 30), "blue_plastic": (40, 90, 170), "green_plastic": (50, 140, 70),
    "white_plastic": (220, 220, 212), "black_plastic": (28, 28, 30), "gray_plastic": (120, 122, 124),
    "pink_plastic": (220, 130, 160), "yellow_plastic": (230, 190, 40),
    "steel": (150, 152, 156), "aluminum": (180, 182, 184), "dark_steel": (70, 72, 76), "brass": (176, 140, 60),
    "chrome": (200, 204, 210), "rust": (130, 70, 40), "copper": (170, 100, 60), "gold": (220, 176, 60),
    "wood_light": (176, 132, 84), "wood_dark": (96, 62, 38), "wood_red": (120, 52, 36), "bamboo": (196, 170, 100),
    "straw": (200, 168, 96), "rope": (150, 120, 80), "cardboard": (170, 128, 80), "paper": (230, 226, 210),
    "cream_ceramic": (226, 214, 186), "white_ceramic": (236, 236, 230), "blue_ceramic": (50, 80, 150),
    "red_lacquer": (150, 30, 26), "sand": (180, 160, 120), "ash": (110, 106, 100), "wax": (230, 220, 190),
    "cloth_gray": (110, 112, 116),
    "glass": (170, 196, 196), "water": (90, 120, 130), "screen_dark": (16, 20, 26), "rubber": (36, 36, 36),
    "foam": (220, 210, 170), "mop_strands": (190, 186, 172), "kraft": (160, 116, 70), "foil": (200, 200, 196),
    "orange": (230, 120, 30), "purple": (110, 60, 140), "brown": (100, 70, 50), "dark_red": (110, 20, 20),
    "beige": (210, 196, 160), "black": (14, 14, 14), "white": (244, 244, 240), "mid_gray": (128, 128, 128),
    "red_window": (200, 20, 20), "led_green": (60, 230, 90), "flame_core": (255, 240, 170),
    "flame_outer": (255, 150, 40), "ember": (255, 80, 20), "soot": (40, 36, 34), "brick": (150, 70, 50),
    "cement": (150, 150, 145),
    "navy": (30, 40, 80), "teal": (40, 130, 130), "olive": (110, 110, 50), "maroon": (110, 30, 40),
    "khaki": (170, 150, 110), "lilac": (180, 160, 210), "mint": (160, 220, 190), "salmon": (230, 140, 120),
}


def ci(c):
    return None if c is None else tuple(int(round(v)) for v in c)


class Tex:
    def __init__(self, w, h, bg=(128, 128, 128), mode="RGB"):
        self.w, self.h = w, h
        self.img = Image.new(mode, (w * S, h * S), bg if mode == "RGB" else bg + (255,) if len(bg) == 3 else bg)
        self.d = ImageDraw.Draw(self.img)

    def R(self, x0, y0, x1, y1):
        return [x0 * S, y0 * S, x1 * S - 1, y1 * S - 1]

    def rect(self, r, color, outline=None, width=1):
        self.d.rectangle(self.R(*r), fill=ci(color), outline=ci(outline), width=width * S if outline else 0)

    def grad(self, r, c0, c1, vertical=True):
        x0, y0, x1, y1 = [v * S for v in r]
        n = (y1 - y0) if vertical else (x1 - x0)
        for i in range(n):
            t = i / max(1, n - 1)
            c = tuple(int(c0[k] * (1 - t) + c1[k] * t) for k in range(3))
            if vertical:
                self.d.line([(x0, y0 + i), (x1 - 1, y0 + i)], fill=c)
            else:
                self.d.line([(x0 + i, y0), (x0 + i, y1 - 1)], fill=c)

    def ellipse(self, r, color, outline=None):
        self.d.ellipse(self.R(*r), fill=ci(color), outline=ci(outline))

    def poly(self, pts, color):
        self.d.polygon([(x * S, y * S) for x, y in pts], fill=ci(color))

    def line(self, pts, color, width=1.0):
        self.d.line([(x * S, y * S) for x, y in pts], fill=ci(color), width=max(1, int(width * S)))

    def text(self, x, y, s, size, color, font=FONT_B, anchor="mm", stroke=0, stroke_color=None):
        f = ImageFont.truetype(font, max(4, int(size * S)))
        self.d.text((x * S, y * S), s, font=f, fill=ci(color), anchor=anchor, stroke_width=int(stroke * S),
                    stroke_fill=ci(stroke_color))

    def text_fit(self, r, s, color, font=FONT_B, max_size=12, stroke=0, stroke_color=None):
        x0, y0, x1, y1 = r
        size = max_size
        while size > 2:
            f = ImageFont.truetype(font, int(size * S))
            bb = self.d.textbbox((0, 0), s, font=f, stroke_width=int(stroke * S))
            if bb[2] - bb[0] <= (x1 - x0) * S and bb[3] - bb[1] <= (y1 - y0) * S:
                break
            size -= 0.5
        self.text((x0 + x1) / 2, (y0 + y1) / 2, s, size, color, font, stroke=stroke, stroke_color=stroke_color)

    def barcode(self, r, seed=1, digits=True):
        """Pixel-aligned EAN-like barcode (bars >= 1 texel so it survives 64-128 px textures).
        Number uses the Vietnamese GS1 prefix 893 (random, fictional)."""
        x0, y0, x1, y1 = [int(round(v)) for v in r]
        self.rect((x0, y0, x1, y1), (250, 250, 250))
        rng = np.random.default_rng(seed)
        bars_y1 = y1 - (2 if digits and (y1 - y0) >= 8 else 1)
        x = x0 + 1
        black = True
        widths = [1, 1]
        while sum(widths) < (x1 - x0 - 4):
            widths.append(int(rng.choice([1, 1, 2])))
        widths += [1, 1]
        for wv in widths:
            if x + wv > x1 - 1:
                break
            if black:
                self.d.rectangle([x * S, (y0 + 1) * S, (x + wv) * S - 1, bars_y1 * S - 1], fill=(8, 8, 8))
            x += wv
            black = not black
        if digits and (y1 - y0) >= 8:
            for k in range(x0 + 1, x1 - 1, 2):  # digits read as a dotted row at this size
                self.d.rectangle([k * S, (y1 - 1.6) * S, (k + 1) * S - 1, (y1 - 0.6) * S], fill=(60, 60, 60))

    def noise(self, amount=6):
        a = np.asarray(self.img, dtype=np.float32)
        a[..., :3] += RNG.normal(0, amount, a.shape[:2])[..., None]
        self.img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), self.img.mode)
        self.d = ImageDraw.Draw(self.img)

    def save(self, name, dither=True):
        os.makedirs(OUT, exist_ok=True)
        if self.img.mode == "RGBA":
            alpha = self.img.split()[3].resize((self.w, self.h), Image.BOX).point(lambda v: 255 if v > 110 else 0)
            out = finalize(self.img.convert("RGB"), (self.w, self.h), grain=1.5, dither=dither, sharpen=False,
                           alpha=alpha)
        else:
            out = finalize(self.img, (self.w, self.h), grain=1.5, dither=dither, sharpen=True)
        out.save(os.path.join(OUT, name + ".png"))
        return out


def wrap_rect(t, r, cx_frac, width, draw):
    """Draw something centered at u=cx_frac of rect r, duplicating across the horizontal wrap."""
    x0, y0, x1, y1 = r
    W = x1 - x0
    for sh in (-W, 0, W):
        draw(x0 + cx_frac * W + sh)


# ------------------------------------------------------------------------------------------
def palette():
    t = Tex(64, 64)
    for r, row in enumerate(PALETTE):
        for c, name in enumerate(row):
            col = COLORS[name]
            t.grad((c * 8, r * 8, c * 8 + 8, r * 8 + 8), tuple(min(255, v * 1.08) for v in col),
                   tuple(v * 0.9 for v in col))
    # wood grain / straw streaks on their swatches
    for name in ("wood_light", "wood_dark", "wood_red", "bamboo", "straw", "mop_strands", "rope"):
        r = [i for i, row in enumerate(PALETTE) if name in row][0]
        c = PALETTE[r].index(name)
        for k in range(4):
            y = r * 8 + 1 + k * 2
            t.line([(c * 8, y), (c * 8 + 8, y + RNG.uniform(-0.5, 0.5))], tuple(v * 0.75 for v in COLORS[name]), 0.4)
    t.noise(5)
    t.save("props_palette", dither=False)
    meta = {name: [c * 8 + 1, r * 8 + 1, c * 8 + 7, r * 8 + 7] for r, row in enumerate(PALETTE) for c, name in enumerate(row)}
    json.dump({"size": [64, 64], "swatches": meta}, open(os.path.join(HERE, "palette.json"), "w"), indent=1)


def can(name, brand, sub, bg0, bg1, fg, accent, seed):
    t = Tex(64, 64)
    side = CYL["side"]
    t.grad(side, bg0, bg1)
    # rims
    t.rect((0, 0, 64, 3), (190, 192, 196))
    t.rect((0, 45, 64, 48), (170, 172, 176))
    # front logo panel (u=0.5)
    t.ellipse((22, 8, 42, 30), accent)
    t.text_fit((12, 10, 52, 22), brand, fg, FONT_K, 10, stroke=0.6, stroke_color=(20, 20, 20))
    t.text_fit((16, 24, 48, 31), sub, fg, FONT_B, 5)
    t.text_fit((18, 34, 46, 40), "330ml", fg, FONT_B, 4)
    # barcode on the back (u=0 / 1 wraps)
    wrap_rect(t, side, 0.0, 14, lambda cx: t.barcode((cx - 7, 24, cx + 7, 40), seed))
    wrap_rect(t, side, 0.0, 14, lambda cx: t.text_fit((cx - 9, 8, cx + 9, 20), "Thành phần: nước, đường", fg, FONT_R, 3))
    # top: aluminium with tab
    t.rect(CYL["top"], (186, 188, 192))
    t.ellipse((2, 50, 14, 62), (170, 172, 176), outline=(120, 120, 124))
    t.rect((6, 51, 10, 56), (140, 142, 146))
    t.rect(CYL["bottom"], (160, 162, 166))
    t.rect(CYL["extra"], (186, 188, 192))
    t.noise(4)
    t.save(name)


def noodle_pack():
    t = Tex(128, 64)
    red, yel = (200, 30, 26), (250, 210, 40)
    for k in ("front", "back", "px", "nx", "top", "bottom"):
        t.rect(BOX[k], red)
    f = BOX["front"]
    t.grad((0, 0, 48, 40), (214, 40, 30), (170, 20, 18))
    t.ellipse((4, 18, 44, 40), (236, 200, 120))           # bowl of noodles
    for k in range(8):
        t.line([(8 + k * 4, 26), (10 + k * 4, 34)], (250, 230, 160), 0.8)
    t.ellipse((26, 22, 34, 28), (230, 110, 90))            # shrimp
    t.text_fit((2, 2, 46, 12), "Mì Hảo Hạn", yel, FONT_K, 10, stroke=0.6, stroke_color=(90, 10, 10))
    t.text_fit((6, 12, 42, 18), "TÔM CHUA CAY", (255, 255, 255), FONT_B, 5)
    t.rect((36, 30, 47, 39), yel)
    t.text_fit((36, 30, 47, 39), "75g", red, FONT_B, 4)
    b = BOX["back"]
    t.rect((50, 2, 94, 20), (240, 230, 210))
    t.text_fit((51, 3, 93, 8), "HƯỚNG DẪN SỬ DỤNG", red, FONT_B, 4)
    for k in range(4):
        t.line([(52, 10 + k * 2.4), (92, 10 + k * 2.4)], (120, 100, 90), 0.4)
    t.barcode((58, 23, 86, 38), 11)
    t.rect(BOX["px"], (180, 24, 20))
    t.text_fit((97, 4, 127, 36), "HẢO HẠN", yel, FONT_K, 6)
    t.noise(4)
    t.save("noodle_pack")


def noodle_cup():
    t = Tex(64, 64)
    side = CYL["side"]
    t.grad(side, (250, 246, 236), (230, 222, 200))
    t.rect((0, 0, 64, 6), (200, 30, 26))
    t.rect((0, 42, 64, 48), (200, 30, 26))
    t.text_fit((14, 8, 50, 20), "Mì Ly", (200, 30, 26), FONT_K, 8)
    t.text_fit((10, 19, 54, 29), "Hảo Hạn", (200, 30, 26), FONT_K, 9)
    t.ellipse((22, 29, 42, 41), (240, 190, 90))
    t.text_fit((18, 30, 46, 40), "BÒ HẦM", (120, 30, 20), FONT_B, 4)
    wrap_rect(t, side, 0.0, 14, lambda cx: t.barcode((cx - 7, 24, cx + 7, 40), 12))
    # lid (foil) top + bottom
    t.rect(CYL["top"], (220, 216, 206))
    t.ellipse((1, 49, 15, 63), (236, 230, 216), outline=(200, 30, 26))
    t.rect(CYL["bottom"], (230, 226, 214))
    t.rect(CYL["extra"], (236, 230, 216))
    t.text_fit((34, 50, 62, 62), "Hảo Hạn", (200, 30, 26), FONT_K, 5)
    t.noise(4)
    t.save("noodle_cup")


def snack_bag():
    t = Tex(128, 64)
    for k in BOX:
        t.rect(BOX[k], (240, 160, 20))
    t.grad((0, 0, 48, 40), (250, 180, 30), (220, 110, 10))
    t.text_fit((2, 3, 46, 14), "Bim Bim", (200, 20, 20), FONT_K, 10, stroke=0.7, stroke_color=(255, 250, 220))
    t.text_fit((4, 13, 44, 21), "GIÒN RỤM", (255, 255, 255), FONT_K, 6, stroke=0.4, stroke_color=(150, 40, 0))
    for k, (x, y) in enumerate([(10, 28), (20, 31), (30, 27), (38, 32)]):
        t.ellipse((x - 4, y - 3, x + 4, y + 3), (250, 220, 120))  # chips
    t.text_fit((6, 34, 42, 39), "VỊ TÔM CAY", (120, 20, 0), FONT_B, 4)
    t.rect((50, 2, 94, 18), (255, 236, 190))
    for k in range(4):
        t.line([(52, 5 + k * 3), (92, 5 + k * 3)], (150, 100, 50), 0.4)
    t.barcode((58, 21, 86, 37), 13)
    t.rect(BOX["top"], (200, 120, 20))
    t.rect(BOX["bottom"], (200, 120, 20))
    for x in range(32, 80, 2):
        t.line([(x, 40), (x, 64)], (170, 90, 10), 0.4)
        t.line([(x + 48, 40), (x + 48, 64)], (170, 90, 10), 0.4)
    t.noise(4)
    t.save("snack_bag")


def water_bottle():
    t = Tex(64, 64)
    side = CYL["side"]
    t.grad(side, (170, 200, 214), (120, 160, 180))
    for x in range(0, 64, 4):
        t.line([(x, 0), (x, 48)], (200, 225, 235), 0.4)
    t.rect((0, 16, 64, 34), (30, 110, 190))  # label band
    t.rect((0, 16, 64, 18), (250, 250, 250))
    t.rect((0, 32, 64, 34), (250, 250, 250))
    t.text_fit((10, 18, 54, 26), "Trong Lành", (255, 255, 255), FONT_K, 8)
    t.text_fit((14, 26, 50, 32), "NƯỚC SUỐI 500ml", (220, 240, 255), FONT_B, 4)
    wrap_rect(t, side, 0.0, 12, lambda cx: t.barcode((cx - 6, 18, cx + 6, 32), 14))
    t.rect(CYL["top"], (30, 90, 180))       # cap
    t.rect(CYL["bottom"], (150, 190, 205))
    t.rect(CYL["extra"], (30, 90, 180))
    for x in range(32, 64, 2):
        t.line([(x, 48), (x, 64)], (20, 60, 130), 0.4)
    t.noise(3)
    t.save("water_bottle")


def cardboard():
    t = Tex(128, 64)
    for k in BOX:
        t.rect(BOX[k], (172, 128, 80))
    t.noise(6)
    t.d = ImageDraw.Draw(t.img)
    for k in ("front", "back"):
        x0, y0, x1, y1 = BOX[k]
        t.text_fit((x0 + 4, y0 + 4, x1 - 4, y0 + 14), "ÁNH DƯƠNG", (60, 40, 30), FONT_K, 7)
        t.text_fit((x0 + 4, y0 + 15, x1 - 4, y0 + 21), "HÀNG DỄ VỠ", (160, 30, 20), FONT_B, 5)
        t.poly([(x0 + 8, y1 - 6), (x0 + 12, y1 - 14), (x0 + 16, y1 - 6)], (60, 40, 30))  # this-side-up arrows
        t.poly([(x0 + 18, y1 - 6), (x0 + 22, y1 - 14), (x0 + 26, y1 - 6)], (60, 40, 30))
        t.rect((x1 - 18, y1 - 14, x1 - 3, y1 - 3), (240, 240, 232))  # shipping label
        t.barcode((x1 - 17, y1 - 11, x1 - 4, y1 - 4), 15, digits=False)
    tape = (200, 170, 110)
    t.rect((32 + 20, 40, 32 + 28, 64), tape)  # tape on top
    t.rect((0 + 20, 0, 0 + 28, 4), tape)
    t.rect((48 + 20, 0, 48 + 28, 4), tape)
    # inner (used by the open box): plain kraft in the -X region border
    t.save("cardboard")


def cash_register():
    t = Tex(64, 64)
    t.rect((0, 0, 64, 64), (60, 62, 66))
    # keypad region (0,0)-(32,32)
    t.rect((0, 0, 32, 32), (40, 42, 46))
    for r in range(5):
        for c in range(5):
            col = (210, 210, 205) if c < 4 else (200, 60, 50) if r < 2 else (70, 160, 80)
            t.rect((2 + c * 6, 2 + r * 6, 6 + c * 6, 6 + r * 6), col)
    # display region (32,0)-(64,16)
    t.rect((32, 0, 64, 16), (20, 30, 24))
    t.text_fit((34, 2, 62, 14), "25.000", (90, 240, 120), FONT_B, 9)
    # drawer front (32,16)-(64,32)
    t.rect((32, 16, 64, 32), (52, 54, 58))
    t.rect((44, 22, 52, 25), (20, 20, 20))
    # receipt slot / body (0,32)-(64,64)
    t.rect((0, 32, 64, 64), (66, 68, 72))
    t.rect((4, 40, 28, 44), (20, 20, 20))
    t.text_fit((34, 40, 62, 50), "ÁNH DƯƠNG", (230, 140, 40), FONT_K, 5)
    t.noise(3)
    t.save("cash_register")


def laptop():
    t = Tex(64, 64)
    t.rect((0, 0, 64, 64), (50, 52, 56))
    # screen (0,0)-(40,26): desktop
    t.grad((0, 0, 40, 26), (40, 70, 120), (20, 40, 80))
    t.rect((2, 2, 7, 6), (230, 200, 80))
    t.rect((2, 8, 7, 12), (200, 200, 220))
    t.rect((10, 6, 34, 20), (230, 230, 230))
    t.rect((10, 6, 34, 8), (40, 90, 170))
    for k in range(4):
        t.line([(12, 10 + k * 2.5), (30, 10 + k * 2.5)], (90, 90, 90), 0.4)
    t.rect((0, 23, 40, 26), (30, 30, 34))
    # keyboard (0,26)-(40,52)
    t.rect((0, 26, 40, 52), (60, 62, 66))
    for r in range(5):
        for c in range(10):
            t.rect((1.5 + c * 3.8, 28 + r * 3.5, 4.5 + c * 3.8, 30.5 + r * 3.5), (24, 24, 26))
    t.rect((14, 46, 26, 51), (70, 72, 76))  # touchpad
    # lid back (40,0)-(64,32)
    t.rect((40, 0, 64, 32), (90, 92, 96))
    t.ellipse((48, 12, 56, 20), (130, 132, 136))
    t.noise(3)
    t.save("laptop")


def phone():
    t = Tex(32, 64)
    t.rect((0, 0, 32, 64), (30, 30, 34))
    # screen (0,0)-(16,32): lock screen with time
    t.grad((0, 0, 16, 32), (40, 50, 90), (90, 50, 80))
    t.text_fit((1, 6, 15, 12), "23:47", (240, 240, 250), FONT_B, 5)
    t.text_fit((2, 12, 14, 15), "Thứ Tư", (220, 220, 230), FONT_R, 2.5)
    t.rect((2, 18, 14, 22), (230, 230, 235))
    t.rect((7, 29, 9, 30), (200, 200, 210))
    # back (16,0)-(32,32)
    t.rect((16, 0, 32, 32), (40, 60, 90))
    t.rect((18, 2, 23, 9), (20, 20, 22))
    t.ellipse((19, 3, 22, 6), (60, 60, 70))
    t.text_fit((17, 22, 31, 26), "LUMO", (180, 190, 210), FONT_B, 3)
    t.noise(2)
    t.save("phone")


def old_photo():
    t = Tex(64, 64)
    t.rect((0, 0, 64, 64), (90, 40, 26))       # red-brown lacquered frame wood
    for k in range(6):
        t.line([(0, k * 10 + 3), (64, k * 10 + 5)], (70, 30, 20), 0.6)
    # portrait region (8,6)-(40,46): sepia old man
    t.grad((8, 6, 40, 46), (170, 150, 120), (120, 100, 80))
    t.ellipse((15, 12, 33, 34), (196, 176, 146))                  # face
    t.ellipse((14, 9, 34, 20), (60, 50, 40))                       # hair / khăn xếp
    t.rect((19, 21, 22, 23), (60, 50, 40))
    t.rect((26, 21, 29, 23), (60, 50, 40))
    t.line([(21, 29), (27, 29)], (90, 70, 60), 0.8)
    t.poly([(10, 46), (14, 36), (24, 33), (34, 36), (38, 46)], (50, 40, 34))  # áo the
    t.line([(24, 36), (24, 46)], (140, 120, 90), 0.5)
    # crack across the glass
    t.line([(10, 8), (20, 20), (18, 30), (30, 44)], (235, 235, 230), 0.6)
    t.line([(20, 20), (36, 18)], (235, 235, 230), 0.5)
    # back / stand (40,0)-(64,64): plain card
    t.rect((40, 0, 64, 64), (120, 100, 70))
    t.noise(5)
    t.save("old_photo")


def joss_paper():
    t = Tex(64, 64)
    t.rect((0, 0, 64, 64), (220, 170, 70))
    t.rect((0, 0, 32, 32), (226, 186, 70))
    t.rect((6, 6, 26, 26), (236, 206, 90))                 # gold foil square
    t.ellipse((10, 10, 22, 22), (210, 50, 30))
    cjk = "/usr/share/fonts/noto-cjk/NotoSansCJK-Bold.ttc"
    if os.path.exists(cjk):
        t.text_fit((10, 10, 22, 22), "福", (250, 220, 100), cjk, 8)
    t.rect((32, 0, 64, 32), (200, 40, 30))                 # red paper
    t.text_fit((34, 8, 62, 24), "VÀNG MÃ", (250, 210, 80), FONT_K, 6)
    t.rect((0, 32, 64, 64), (210, 180, 120))               # stack edge
    for y in range(32, 64, 2):
        t.line([(0, y), (64, y)], (180, 140, 80), 0.5)
    t.noise(4)
    t.save("joss_paper")


def wardrobe():
    t = Tex(64, 128)
    t.rect((0, 0, 64, 128), (200, 216, 236))
    t.rect((2, 2, 62, 80), (180, 200, 230))                 # door panels
    t.line([(32, 2), (32, 80)], (120, 140, 170), 0.8)
    for x0 in (2, 33):
        for k in range(6):
            t.ellipse((x0 + 6 + (k % 2) * 12, 8 + k * 11, x0 + 13 + (k % 2) * 12, 15 + k * 11), (240, 200, 210))
    t.rect((28, 36, 30, 46), (240, 240, 240))
    t.rect((34, 36, 36, 46), (240, 240, 240))
    for k in range(3):                                        # drawers
        y = 84 + k * 14
        t.rect((2, y, 62, y + 12), (170, 192, 226))
        t.rect((26, y + 4, 38, y + 7), (240, 240, 240))
    t.noise(3)
    t.save("wardrobe")


def fridge():
    t = Tex(64, 64)
    t.grad((0, 0, 64, 64), (226, 228, 226), (200, 202, 200))
    t.line([(0, 40), (64, 40)], (150, 152, 150), 0.8)       # freezer seam (front 0..40 = main door)
    t.rect((50, 6, 54, 34), (170, 172, 174))                 # handle
    t.text_fit((8, 4, 40, 10), "TUYẾT SƠN", (60, 90, 150), FONT_K, 5)
    t.rect((10, 22, 22, 32), (240, 240, 230))                 # sticker
    t.text_fit((10, 22, 22, 32), "A+", (60, 160, 80), FONT_B, 5)
    t.rect((0, 44, 64, 64), (60, 60, 62))                     # back grille
    for x in range(0, 64, 3):
        t.line([(x, 44), (x, 64)], (40, 40, 42), 0.5)
    t.noise(3)
    t.save("fridge")


def mattress():
    t = Tex(64, 64)
    t.rect((0, 0, 64, 64), (210, 190, 200))
    for k in range(0, 64, 8):                                 # stripes
        t.rect((k, 0, k + 3, 40), (170, 140, 170))
    for k in range(12):
        x, y = RNG.uniform(2, 60), RNG.uniform(2, 38)
        t.ellipse((x - 2, y - 2, x + 2, y + 2), (230, 120, 140))
    t.rect((0, 40, 32, 64), (240, 236, 228))                 # pillow
    t.rect((32, 40, 64, 64), (90, 120, 160))                 # blanket (chăn)
    for k in range(5):
        t.line([(32, 44 + k * 4), (64, 44 + k * 4)], (70, 100, 140), 0.6)
    t.noise(5)
    t.save("mattress")


def stove():
    t = Tex(64, 64)
    t.rect((0, 0, 64, 64), (40, 40, 44))
    t.ellipse((4, 4, 36, 36), (24, 24, 26))                  # burner top area
    t.ellipse((12, 12, 28, 28), (90, 92, 96))
    t.ellipse((16, 16, 24, 24), (30, 30, 32))
    t.rect((36, 0, 64, 32), (200, 200, 204))                 # front panel steel
    t.ellipse((40, 8, 52, 20), (30, 30, 32))                 # knob
    t.text_fit((38, 22, 62, 30), "BẾP GA MINI", (40, 40, 40), FONT_B, 3)
    t.rect((0, 36, 64, 64), (180, 40, 30))                   # gas canister (red/orange)
    t.text_fit((4, 42, 60, 56), "GAS 250g", (250, 240, 220), FONT_K, 6)
    t.noise(4)
    t.save("stove")


def fan_grille():
    t = Tex(64, 64, bg=(0, 0, 0, 0), mode="RGBA")
    c = (200, 200, 205, 255)
    for r in range(6, 32, 5):
        t.d.ellipse([(32 - r) * S, (32 - r) * S, (32 + r) * S, (32 + r) * S], outline=c, width=int(0.9 * S))
    for k in range(16):
        a = k / 16 * 2 * np.pi
        t.d.line([(32 * S, 32 * S), ((32 + 31 * np.cos(a)) * S, (32 + 31 * np.sin(a)) * S)], fill=c, width=int(0.8 * S))
    t.d.ellipse([26 * S, 26 * S, 38 * S, 38 * S], fill=(60, 120, 190, 255))
    t.save("fan_grille", dither=False)


def dirt_stain():
    t = Tex(64, 64, bg=(0, 0, 0, 0), mode="RGBA")
    rng = np.random.default_rng(3)
    for _ in range(40):
        x, y = rng.normal(32, 9, 2)
        r = rng.uniform(2, 9)
        col = tuple(int(v) for v in rng.uniform([60, 46, 30], [100, 80, 54])) + (255,)
        t.d.ellipse([(x - r) * S, (y - r * 0.7) * S, (x + r) * S, (y + r * 0.7) * S], fill=col)
    for _ in range(14):  # drips / splashes
        x, y = rng.normal(32, 16, 2)
        r = rng.uniform(0.6, 1.8)
        t.d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=(70, 54, 36, 255))
    t.save("dirt_stain", dither=False)


def incense():
    t = Tex(32, 32)
    t.rect((0, 0, 32, 20), (150, 110, 80))                   # incense powder part (top)
    for x in range(0, 32, 2):
        t.line([(x, 0), (x, 20)], (130, 90, 64), 0.4)
    t.rect((0, 20, 32, 32), (200, 30, 40))                   # red stems
    t.rect((0, 18, 32, 20), (230, 200, 80))                  # gold paper band
    t.save("incense")


def incense_bowl():
    t = Tex(64, 32)
    t.grad((0, 0, 64, 24), (230, 222, 200), (200, 190, 168))
    t.rect((0, 2, 64, 4), (40, 70, 140))
    t.rect((0, 20, 64, 22), (40, 70, 140))
    for k in range(4):                                        # blue dragon-ish swirls
        x = k * 16 + 8
        t.line([(x - 5, 14), (x - 2, 8), (x + 2, 16), (x + 5, 9)], (40, 70, 150), 0.9)
        t.ellipse((x - 1.5, 10, x + 1.5, 13), (40, 70, 150))
    t.rect((0, 24, 32, 32), (140, 126, 110))                 # ash/sand top
    for _ in range(30):
        x, y = RNG.uniform(0, 32), RNG.uniform(24, 32)
        t.ellipse((x - 0.5, y - 0.5, x + 0.5, y + 0.5), (80, 74, 70))
    t.rect((32, 24, 64, 32), (180, 40, 40))                  # burnt stick stubs
    t.noise(4)
    t.save("incense_bowl")


def main():
    os.makedirs(OUT, exist_ok=True)
    palette()
    can("can_tra_xanh", "Trà Xanh Mát", "TRÀ XANH KHÔNG ĐỘ", (60, 160, 70), (20, 100, 40), (255, 255, 240), (240, 230, 120), 21)
    can("can_sam", "SẤM", "NƯỚC TĂNG LỰC", (220, 30, 30), (140, 10, 10), (255, 220, 40), (30, 30, 30), 22)
    can("can_cafe", "Cà Phê Sữa Đá", "LON 100% ROBUSTA", (120, 72, 40), (60, 34, 20), (250, 236, 210), (200, 150, 90), 23)
    can("can_cam", "Cam Ép Vui", "NƯỚC CAM CÓ GAS", (250, 150, 30), (210, 90, 10), (255, 255, 255), (60, 140, 50), 24)
    noodle_pack()
    noodle_cup()
    snack_bag()
    water_bottle()
    cardboard()
    cash_register()
    laptop()
    phone()
    old_photo()
    joss_paper()
    wardrobe()
    fridge()
    mattress()
    stove()
    fan_grille()
    dirt_stain()
    incense()
    incense_bowl()
    print("prop textures ->", OUT)


if __name__ == "__main__":
    main()
