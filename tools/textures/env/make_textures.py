#!/usr/bin/env python3
"""Procedural PS1-style environment textures for "Đèn Đường Cuối Ngõ".

Usage:  python3 tools/textures/env/make_textures.py [out_dir]
Default out_dir = assets/textures/env

Every texture is <= 256 px, quantized to a small palette and then to 15-bit
colour (5 bits per channel) for the PSX look. Texel density convention used by
the Blender env builders: 128 px per metre (a 256 px wall texture tiles every 2 m).
Deterministic: fixed RNG seeds, so re-running produces identical files.
"""
import os
import sys
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
if "--sheet" in sys.argv:
    _args = [a for a in _args if a != sys.argv[sys.argv.index("--sheet") + 1]]
OUT = _args[0] if _args else os.path.join(ROOT, "assets", "textures", "env")

FONT_DIRS = ["/usr/share/fonts/noto", "/usr/share/fonts/TTF", "/usr/share/fonts/truetype/dejavu",
             "/usr/share/fonts/dejavu", "/usr/share/fonts/truetype/noto"]


def find_font(names):
    for n in names:
        for d in FONT_DIRS:
            p = os.path.join(d, n)
            if os.path.exists(p):
                return p
    raise SystemExit("No Vietnamese-capable font found (need NotoSans or DejaVuSans)")


FONT_BOLD = find_font(["NotoSans-Black.ttf", "NotoSans-Bold.ttf", "DejaVuSans-Bold.ttf"])
FONT_REG = find_font(["NotoSans-Bold.ttf", "DejaVuSans-Bold.ttf", "DejaVuSans.ttf"])
FONT_COND = find_font(["DejaVuSansCondensed-Bold.ttf", "NotoSans-Bold.ttf"])
FONT_HAND = find_font(["DejaVuSans-Oblique.ttf", "DejaVuSans.ttf"])


def font(path, size):
    return ImageFont.truetype(path, size)


# ---------------------------------------------------------------- noise utils
def rng_for(name):
    return np.random.default_rng(sum(ord(c) * (i + 7) for i, c in enumerate(name)))


def vnoise(h, w, cy, cx, rng):
    """Tileable value noise, cells cy x cx, smoothstep interpolated."""
    g = rng.random((cy, cx))
    ys = np.arange(h) * cy / h
    xs = np.arange(w) * cx / w
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    fy = ys - y0; fx = xs - x0
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % cy; x1 = (x0 + 1) % cx
    a = g[y0][:, x0]; b = g[y0][:, x1]; c = g[y1][:, x0]; d = g[y1][:, x1]
    fx = fx[None, :]; fy = fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(h, w, rng, base=4, octaves=4, persist=0.5):
    out = np.zeros((h, w)); amp = 1.0; tot = 0.0; c = base
    for _ in range(octaves):
        m = max(h, w)
        out += vnoise(h, w, max(1, round(c * h / m)), max(1, round(c * w / m)), rng) * amp
        tot += amp; amp *= persist; c *= 2
    return out / tot


def white(h, w, rng):
    return rng.random((h, w))


def to_img(arr):
    return Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8))


def to_arr(img):
    return np.asarray(img.convert("RGB")).astype(np.float64) / 255.0


def col(hexs):
    hexs = hexs.lstrip("#")
    return np.array([int(hexs[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def lerp(a, b, t):
    t = np.asarray(t)
    if t.ndim == 2:
        t = t[..., None]
    return a * (1 - t) + b * t


def shade(img, f):
    if f.ndim == 2:
        f = f[..., None]
    return img * f


def drips(h, w, rng, n=20, top=True, length=(0.2, 0.9), width=(1, 4)):
    """Vertical water-stain streaks (tileable in x)."""
    m = np.zeros((h, w))
    for _ in range(n):
        x = rng.integers(0, w); y0 = rng.integers(0, h)
        ln = int(h * rng.uniform(*length)); wd = rng.integers(width[0], width[1] + 1)
        for k in range(ln):
            y = (y0 + k) % h
            a = (1 - k / ln) * rng.uniform(0.6, 1.0)
            x += rng.choice([-1, 0, 0, 0, 0, 1]) if rng.random() < 0.3 else 0
            for dx in range(wd):
                m[y, (x + dx) % w] = max(m[y, (x + dx) % w], a)
    return m


def blobs(h, w, rng, n, rmin, rmax):
    m = np.zeros((h, w))
    yy, xx = np.mgrid[0:h, 0:w]
    for _ in range(n):
        cy, cx = rng.integers(0, h), rng.integers(0, w); r = rng.uniform(rmin, rmax)
        dy = np.minimum(abs(yy - cy), h - abs(yy - cy)); dx = np.minimum(abs(xx - cx), w - abs(xx - cx))
        d = np.sqrt(dy ** 2 + dx ** 2) / r
        m = np.maximum(m, np.clip(1 - d, 0, 1))
    return m


def crack_lines(draw, w, h, rng, n, color, seg=(6, 16), steps=(4, 12), width=1):
    for _ in range(n):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        ang = rng.uniform(0, 2 * math.pi)
        for _ in range(rng.integers(*steps)):
            ang += rng.uniform(-0.8, 0.8)
            l = rng.uniform(*seg)
            nx, ny = x + math.cos(ang) * l, y + math.sin(ang) * l
            for ox in (-w, 0, w):
                for oy in (-h, 0, h):
                    draw.line([(x + ox, y + oy), (nx + ox, ny + oy)], fill=color, width=width)
            x, y = nx, ny


# ---------------------------------------------------------------- output
WRITTEN = []


def finish(arr_or_img, name, colors=32, alpha=None, alpha_levels=2):
    if isinstance(arr_or_img, Image.Image):
        img = arr_or_img.convert("RGB")
    else:
        img = to_img(arr_or_img)
    q = img.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    a = np.asarray(q).astype(np.uint8) & 0xF8  # 15-bit colour
    a = a | (a >> 5)  # spread to full range (0xF8 -> 0xFF)
    if alpha is not None:
        al = np.asarray(alpha).astype(np.float64)
        if al.max() > 1.0:
            al = al / 255.0
        if alpha_levels == 2:
            al = (al > 0.5).astype(np.float64)
        else:
            al = np.round(al * (alpha_levels - 1)) / (alpha_levels - 1)
        out = np.dstack([a, (al * 255).astype(np.uint8)])
        im = Image.fromarray(out, "RGBA")
    else:
        im = Image.fromarray(a, "RGB")
    p = os.path.join(OUT, name + ".png")
    im.save(p, optimize=True)
    WRITTEN.append((name, im.size, "A" if alpha is not None else ""))


# ---------------------------------------------------------------- text helpers
def text_fit(draw, box, text, fpath, fill, max_size=64, stroke=0, stroke_fill=None, anchor="mm", spacing=1.0):
    x0, y0, x1, y1 = box
    size = max_size
    while size > 6:
        f = font(fpath, size)
        bb = draw.textbbox((0, 0), text, font=f, stroke_width=stroke)
        if bb[2] - bb[0] <= (x1 - x0) and bb[3] - bb[1] <= (y1 - y0):
            break
        size -= 1
    f = font(fpath, size)
    draw.text(((x0 + x1) / 2, (y0 + y1) / 2), text, font=f, fill=fill, anchor=anchor,
              stroke_width=stroke, stroke_fill=stroke_fill)
    return size


def sign_image(w, h, bg, lines, fg, scale=4, border=None, stroke=0, stroke_fill=None, deco=None, rng=None, grime=0.25):
    """Render a shop sign at scale x resolution then downsample for a crunchy pixel look.
    lines: list of (text, rel_box(x0,y0,x1,y1 in 0..1), font_path, color or None)"""
    W, H = w * scale, h * scale
    im = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(im)
    if deco:
        deco(d, W, H)
    if border:
        bw = max(2, scale * 2)
        d.rectangle([bw // 2, bw // 2, W - bw // 2 - 1, H - bw // 2 - 1], outline=border, width=bw)
    for text, rb, fp, c in lines:
        box = (rb[0] * W, rb[1] * H, rb[2] * W, rb[3] * H)
        text_fit(d, box, text, fp, c or fg, max_size=H, stroke=stroke * scale // 2, stroke_fill=stroke_fill)
    im = im.resize((w, h), Image.Resampling.BOX)
    arr = to_arr(im)
    if rng is not None and grime > 0:
        n = fbm(h, w, rng, base=4, octaves=3)
        arr = shade(arr, 1 - grime * np.clip(n - 0.35, 0, 1) * 1.6)
        st = drips(h, w, rng, n=w // 10, length=(0.2, 0.7), width=(1, 2))
        arr = shade(arr, 1 - 0.25 * grime * 4 * st)
    return arr


# ================================================================ textures
def t_asphalt(name="asphalt", line=False):
    s = 256; rng = rng_for(name)
    base = col("4a4a4d")
    n = fbm(s, s, rng, base=8, octaves=4)
    w = white(s, s, rng)
    arr = lerp(base * 0.75, base * 1.25, n)
    arr = shade(arr, 0.85 + 0.3 * w)  # aggregate specks
    arr = lerp(arr, col("8a8a88"), (w > 0.97) * 0.6)
    patch = np.clip((fbm(s, s, rng, base=3, octaves=3) - 0.62) * 6, 0, 1)
    arr = lerp(arr, col("323236"), patch * 0.6)
    oil = blobs(s, s, rng, 3, 6, 14)
    arr = shade(arr, 1 - 0.2 * oil)
    if line:
        # dashed centre line along u (x) at v centre: 1 m dash, 1 m gap
        y0 = s // 2 - 5
        dash = np.zeros((s, s)); dash[y0:y0 + 10, 10:118] = 1
        worn = fbm(s, s, rng, base=16, octaves=2)
        arr = lerp(arr, col("d8d4c0"), dash * (worn > 0.35) * 0.9)
    im = to_img(arr); d = ImageDraw.Draw(im)
    crack_lines(d, s, s, rng, 6, (28, 28, 30), seg=(5, 14), steps=(6, 14))
    finish(im, name, colors=24)


def t_sidewalk():
    """Hanoi sidewalk: 25 cm square cement-brick tiles, red/grey mixed, chipped."""
    s = 128; rng = rng_for("sidewalk"); t = 32
    arr = np.zeros((s, s, 3))
    cols = [col("8e5a4a"), col("9a6c5a"), col("7d7a74"), col("8a8580"), col("7a4b40")]
    n = fbm(s, s, rng, base=8, octaves=3); w = white(s, s, rng)
    for j in range(4):
        for i in range(4):
            c = cols[rng.integers(0, len(cols))] * rng.uniform(0.9, 1.08)
            arr[j * t:(j + 1) * t, i * t:(i + 1) * t] = c
    arr = shade(arr, 0.8 + 0.3 * n + 0.12 * w)
    # grout lines
    g = np.zeros((s, s)); g[::t, :] = 1; g[:, ::t] = 1; g[t - 1::t, :] = 0.5; g[:, t - 1::t] = 0.5
    arr = lerp(arr, col("3a3634"), g * 0.8)
    stain = blobs(s, s, rng, 5, 6, 20)
    arr = shade(arr, 1 - 0.3 * stain)
    im = to_img(arr); d = ImageDraw.Draw(im)
    crack_lines(d, s, s, rng, 3, (50, 44, 40), seg=(3, 8), steps=(3, 7))
    finish(im, "sidewalk", colors=24)


def t_concrete(name="concrete", base="8a8782", s=128):
    rng = rng_for(name)
    n = fbm(s, s, rng, base=4, octaves=5); w = white(s, s, rng)
    c = col(base)
    arr = lerp(c * 0.75, c * 1.12, n)
    arr = shade(arr, 0.9 + 0.15 * w)
    pits = (white(s, s, rng) > 0.985)
    arr = shade(arr, 1 - 0.4 * pits)
    st = drips(s, s, rng, n=10, length=(0.3, 1.0), width=(1, 3))
    arr = lerp(arr, col("4a4a40"), st * 0.35)
    im = to_img(arr); d = ImageDraw.Draw(im)
    crack_lines(d, s, s, rng, 2, tuple(int(v * 255 * 0.5) for v in c), seg=(3, 9), steps=(3, 8))
    finish(im, name, colors=24)


def t_wall(name, paint, under="b0a898", s=256):
    """Peeling lime-wash wall (2 m tile): paint over grey plaster with exposed brick patches,
    moss and black water stains streaking down."""
    rng = rng_for(name)
    p = col(paint); u = col(under)
    n = fbm(s, s, rng, base=4, octaves=5)
    n2 = fbm(s, s, rng, base=8, octaves=4)
    w = white(s, s, rng)
    arr = lerp(p * 0.82, p * 1.08, n)
    arr = shade(arr, 0.94 + 0.08 * w)
    # older paint layer showing through (blotchy)
    old = fbm(s, s, rng, base=3, octaves=3)
    arr = lerp(arr, p * np.array([0.92, 0.95, 0.88]), np.clip((old - 0.55) * 4, 0, 1) * 0.6)
    # peeling: plaster exposed where noise high
    peel = np.clip((n2 - 0.66) * 9, 0, 1)
    plaster = lerp(u * 0.85, u * 1.05, w)
    arr = lerp(arr, plaster, peel)
    # brick showing inside the worst peels
    brick = np.clip((n2 - 0.76) * 12, 0, 1)
    yy, xx = np.mgrid[0:s, 0:s]
    mortar = ((yy % 10) < 2) | (((xx + (yy // 10 % 2) * 14) % 28) < 2)
    bc = np.where(mortar[..., None], col("8c8478")[None, None], col("8e4a36")[None, None] * (0.85 + 0.3 * w[..., None]))
    arr = lerp(arr, bc, brick)
    # peel edge darkening
    edge = np.clip(1 - abs(n2 - 0.66) * 30, 0, 1)
    arr = shade(arr, 1 - 0.25 * edge)
    # water stains (dark) and moss (green-black) streaks from top of tile, plus damp band
    st = drips(s, s, rng, n=26, length=(0.15, 0.8), width=(1, 5))
    st = np.array(Image.fromarray((st * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))) / 255.0
    arr = lerp(arr, col("3d3a2c"), st * 0.55)
    moss = np.clip((fbm(s, s, rng, base=6, octaves=3) - 0.6) * 4, 0, 1)
    arr = lerp(arr, col("4a5530"), moss * 0.45 * (0.6 + 0.4 * w[..., None].squeeze()))
    # grime speckle
    arr = shade(arr, 1 - 0.18 * (w > 0.93))
    im = to_img(arr); d = ImageDraw.Draw(im)
    crack_lines(d, s, s, rng, 4, tuple(int(v * 255 * 0.55) for v in p), seg=(3, 10), steps=(4, 10))
    finish(im, name, colors=40)


def t_brick():
    s = 128; rng = rng_for("brick")
    w = white(s, s, rng); n = fbm(s, s, rng, base=8, octaves=3)
    arr = np.zeros((s, s, 3))
    bh, bw = 8, 32  # 6.25 cm x 25 cm (approx Vietnamese brick w/ mortar)
    for j in range(s // bh):
        off = (j % 2) * bw // 2
        for i in range(-1, s // bw + 1):
            c = col("94503a") * rng.uniform(0.75, 1.15) * np.array([1, rng.uniform(0.9, 1.05), 1])
            x0 = i * bw + off
            for x in range(x0, x0 + bw):
                arr[j * bh:(j + 1) * bh, x % s] = c
    arr = shade(arr, 0.85 + 0.2 * w + 0.1 * n)
    yy, xx = np.mgrid[0:s, 0:s]
    mortar = ((yy % bh) == 0) | (((xx + ((yy // bh) % 2) * bw // 2) % bw) == 0)
    arr[mortar] = col("7b7468") * 0.9
    st = drips(s, s, rng, n=8, length=(0.3, 0.9), width=(1, 3))
    arr = lerp(arr, col("2e2a22"), st * 0.4)
    finish(arr, "brick", colors=24)


def t_tiles(name, c1, c2, grout, t, checker=True, s=128, wear=0.3, pattern=False):
    rng = rng_for(name)
    w = white(s, s, rng); n = fbm(s, s, rng, base=4, octaves=4)
    arr = np.zeros((s, s, 3))
    for j in range(s // t):
        for i in range(s // t):
            c = (c1 if ((i + j) % 2 == 0 or not checker) else c2) * rng.uniform(0.93, 1.05)
            arr[j * t:(j + 1) * t, i * t:(i + 1) * t] = c
    if pattern:  # "gạch bông" style: a diamond inside each tile
        yy, xx = np.mgrid[0:s, 0:s]
        ly = (yy % t) - t / 2; lx = (xx % t) - t / 2
        dia = (abs(ly) + abs(lx)) < t * 0.32
        ring = (abs(abs(ly) + abs(lx) - t * 0.42) < 1.2)
        arr[dia] = arr[dia] * 0.35 + c2 * 0.65
        arr[ring] = col("5a3a2a")
    arr = shade(arr, 0.9 + 0.12 * n + 0.05 * w)
    g = np.zeros((s, s)); g[::t, :] = 1; g[:, ::t] = 1
    arr = lerp(arr, col(grout), g)
    dirt = np.clip((fbm(s, s, rng, base=4, octaves=3) - 0.45) * 2.5, 0, 1)
    arr = lerp(arr, col("4a4034"), dirt * wear)
    # scuffs
    sc = blobs(s, s, rng, 6, 2, 6)
    arr = shade(arr, 1 - 0.2 * sc)
    im = to_img(arr); d = ImageDraw.Draw(im)
    crack_lines(d, s, s, rng, 1, tuple(int(v * 255) for v in col(grout)), seg=(3, 7), steps=(2, 5))
    finish(im, name, colors=24)


def t_wood(name="wood_planks", base="7a5233", plank=20, s=128, vertical=False, paint=None):
    rng = rng_for(name)
    yy, xx = np.mgrid[0:s, 0:s]
    n = fbm(s, s, rng, base=4, octaves=3)
    grain_n = vnoise(s, s, 64, 4, rng) if not vertical else vnoise(s, s, 4, 64, rng)
    arr = np.zeros((s, s, 3))
    c = col(base)
    coord = yy if not vertical else xx
    along = xx if not vertical else yy
    for k in range(s // plank + 1):
        m = (coord >= k * plank) & (coord < (k + 1) * plank)
        arr[m] = c * rng.uniform(0.8, 1.15)
    grain = np.sin((coord * 0.9 + grain_n * 12 + n * 6) * 1.7) * 0.5 + 0.5
    arr = shade(arr, 0.82 + 0.25 * grain)
    seam = (coord % plank) == 0
    arr[seam] = c * 0.35
    # butt joints
    for k in range(s // plank + 1):
        x = rng.integers(0, s)
        m = (coord >= k * plank) & (coord < (k + 1) * plank) & (along == x)
        arr[m] = c * 0.4
    knots = blobs(s, s, rng, 4, 2, 4)
    arr = shade(arr, 1 - 0.45 * knots)
    if paint is not None:
        pc = col(paint)
        peel = np.clip((fbm(s, s, rng, base=6, octaves=4) - 0.62) * 8, 0, 1)
        parr = shade(np.ones((s, s, 3)) * pc, 0.88 + 0.12 * n)
        parr[seam] = pc * 0.45
        arr = lerp(parr, arr, peel)
    dirt = drips(s, s, rng, n=6, length=(0.3, 0.8), width=(1, 3))
    arr = lerp(arr, col("2a2018"), dirt * 0.3)
    finish(arr, name, colors=24)


def t_door_wood():
    """Classic Vietnamese panel door, varnished brown, 128x256 mapped 0..1 on a 0.9x2.1 door."""
    w, h = 128, 256; rng = rng_for("door_wood")
    n = fbm(h, w, rng, base=4, octaves=4)
    yy, xx = np.mgrid[0:h, 0:w]
    gn = vnoise(h, w, 4, 48, rng)
    c = col("7a4a28")
    arr = shade(np.ones((h, w, 3)) * c, 0.8 + 0.25 * (np.sin(xx * 0.8 + gn * 10) * 0.5 + 0.5) * 0.6 + 0.2 * n)
    im = to_img(arr); d = ImageDraw.Draw(im)
    dark = (60, 34, 18); light = (150, 96, 58)
    # 4 raised panels + upper louvre panel
    panels = [(14, 14, 60, 80), (68, 14, 114, 80), (14, 92, 60, 168), (68, 92, 114, 168), (14, 180, 60, 242), (68, 180, 114, 242)]
    for x0, y0, x1, y1 in panels:
        d.rectangle([x0, y0, x1, y1], outline=dark, width=2)
        d.line([(x0 + 2, y0 + 2), (x1 - 2, y0 + 2)], fill=light)
        d.line([(x0 + 2, y0 + 2), (x0 + 2, y1 - 2)], fill=light)
        d.rectangle([x0 + 6, y0 + 6, x1 - 6, y1 - 6], outline=(98, 60, 32))
    # louvres in the top panels
    for y in range(20, 78, 6):
        d.line([(18, y), (56, y)], fill=dark); d.line([(72, y), (110, y)], fill=dark)
    # wear near handle, scratches
    arr = to_arr(im)
    hand = np.exp(-(((xx - 110) / 14.0) ** 2 + ((yy - 128) / 22.0) ** 2))
    arr = lerp(arr, col("3a2414"), hand * 0.6)
    bot = np.clip((yy - 220) / 36.0, 0, 1)
    arr = lerp(arr, col("3b3024"), bot * 0.5 * (0.5 + n[..., None].squeeze() * 0.5))
    finish(arr, "door_wood", colors=28)


def t_door_dorm():
    """Old blue-painted wooden door, flaking, with sticker residue and a lighter plate area."""
    w, h = 128, 256; rng = rng_for("door_dorm")
    yy, xx = np.mgrid[0:h, 0:w]
    n = fbm(h, w, rng, base=4, octaves=5)
    wood = t_wood_arr(h, w, rng)
    blue = col("4f7fa8")
    arr = shade(np.ones((h, w, 3)) * blue, 0.85 + 0.2 * n)
    peel = np.clip((fbm(h, w, rng, base=8, octaves=4) - 0.63) * 9, 0, 1)
    peel = np.maximum(peel, np.clip((yy - 200) / 56.0, 0, 1) * np.clip((n - 0.35) * 4, 0, 1))
    arr = lerp(arr, wood, peel)
    im = to_img(arr); d = ImageDraw.Draw(im)
    for x0, y0, x1, y1 in [(12, 12, 116, 110), (12, 124, 116, 240)]:
        d.rectangle([x0, y0, x1, y1], outline=(40, 62, 84), width=2)
        d.line([(x0 + 2, y0 + 2), (x1 - 2, y0 + 2)], fill=(120, 160, 190))
    # sticker remnants (khoan cắt bê tông ads) and tape
    for _ in range(4):
        x, y = rng.integers(14, 100), rng.integers(120, 230)
        d.rectangle([x, y, x + rng.integers(8, 20), y + rng.integers(4, 10)], fill=(200, 196, 180))
    f = font(FONT_COND, 9)
    d.text((22, 196), "KHOAN CẮT", font=f, fill=(170, 40, 30))
    d.text((22, 206), "BÊ TÔNG", font=f, fill=(170, 40, 30))
    arr = to_arr(im)
    hand = np.exp(-(((xx - 112) / 12.0) ** 2 + ((yy - 128) / 20.0) ** 2))
    arr = lerp(arr, col("2a2a2a"), hand * 0.55)
    st = drips(h, w, rng, n=10, length=(0.2, 0.6), width=(1, 2))
    arr = lerp(arr, col("2a3036"), st * 0.3)
    finish(arr, "door_dorm", colors=32)


def t_wood_arr(h, w, rng):
    yy, xx = np.mgrid[0:h, 0:w]
    gn = vnoise(h, w, 4, 32, rng)
    g = np.sin(xx * 0.7 + gn * 8) * 0.5 + 0.5
    return shade(np.ones((h, w, 3)) * col("6b5038"), 0.75 + 0.35 * g)


def t_railing(name="railing", s=128):
    """Iron railing/gate 1 m x 1 m alpha cutout: top & bottom rails, bars every 12 cm, scroll motif."""
    rng = rng_for(name)
    big = s * 4
    a = Image.new("L", (big, big), 0); d = ImageDraw.Draw(a)
    d.rectangle([0, 6 * 4, big, 12 * 4], fill=255)
    d.rectangle([0, big - 14 * 4, big, big - 8 * 4], fill=255)
    for i in range(8):
        x = int((i + 0.5) * big / 8)
        d.rectangle([x - 6, 0, x + 6, big], fill=255)
    for i in range(8):  # small diamonds between bars
        x = int((i + 1) * big / 8) % big; y = big // 2
        d.polygon([(x, y - 40), (x + 26, y), (x, y + 40), (x - 26, y)], outline=255, width=8)
    a = a.resize((s, s), Image.Resampling.BOX)
    n = fbm(s, s, rng, base=8, octaves=3)
    arr = lerp(col("2c3a36"), col("6a3a22"), np.clip((n - 0.45) * 3, 0, 1))  # green paint / rust
    arr = shade(arr, 0.85 + 0.3 * white(s, s, rng))
    finish(arr, name, colors=16, alpha=a)


def t_shutter(name, base, ads=True):
    """Roller shutter (cửa cuốn): horizontal corrugated slats, 256 px = 2 m."""
    s = 256; rng = rng_for(name)
    yy, xx = np.mgrid[0:s, 0:s]
    c = col(base)
    prof = np.sin((yy % 8) / 8.0 * math.pi * 2) * 0.5 + 0.5
    arr = shade(np.ones((s, s, 3)) * c, 0.72 + 0.35 * prof)
    arr[(yy % 8) == 0] = c * 0.4
    n = fbm(s, s, rng, base=6, octaves=4)
    arr = shade(arr, 0.85 + 0.25 * n)
    rust = np.clip((fbm(s, s, rng, base=10, octaves=3) - 0.6) * 5, 0, 1)
    arr = lerp(arr, col("6e3e22"), rust * 0.7)
    st = drips(s, s, rng, n=20, length=(0.2, 0.8), width=(1, 3))
    arr = lerp(arr, col("30302a"), st * 0.4)
    im = to_img(arr); d = ImageDraw.Draw(im)
    if ads:
        f = font(FONT_COND, 11); f2 = font(FONT_COND, 14)
        for (x, y, txt, ff, fill) in [(18, 40, "KHOAN CẮT BÊ TÔNG", f, (190, 40, 30)),
                                      (30, 54, "09x.xxx.xxx", f, (190, 40, 30)),
                                      (150, 150, "THÔNG CỐNG", f2, (30, 30, 30)),
                                      (140, 168, "HÚT BỂ PHỐT", f, (30, 30, 30))]:
            d.text((x, y), txt, font=ff, fill=fill)
        # tag / scribble
        for _ in range(3):
            x, y = rng.integers(0, s - 40), rng.integers(80, s - 20)
            pts = [(x + k * 4, y + rng.integers(-6, 6)) for k in range(10)]
            d.line(pts, fill=(40, 40, 60), width=2)
    finish(im, name, colors=28)


def t_chalkboard():
    w, h = 256, 128; rng = rng_for("chalkboard")
    n = fbm(h, w, rng, base=6, octaves=4)
    arr = lerp(col("1f3a2c"), col("2f4c3a"), n)
    smudge = np.clip(fbm(h, w, rng, base=3, octaves=3) - 0.4, 0, 1)
    arr = lerp(arr, col("6a7f72"), smudge * 0.45)
    im = to_img(arr); d = ImageDraw.Draw(im)
    chalk = (210, 214, 200)
    d.text((70, 6), "Thứ Hai, ngày 18 tháng 11", font=font(FONT_HAND, 11), fill=chalk)
    d.text((100, 20), "Bài 7: Tích phân", font=font(FONT_HAND, 12), fill=chalk)
    d.text((12, 44), "∫ f(x)dx = F(b) − F(a)", font=font(FONT_HAND, 11), fill=(200, 200, 160))
    d.text((12, 62), "VD1: ∫ (2x + 1) dx", font=font(FONT_HAND, 10), fill=chalk)
    d.text((12, 76), "= x² + x + C", font=font(FONT_HAND, 10), fill=chalk)
    d.text((150, 60), "Trực nhật: Nam", font=font(FONT_HAND, 10), fill=(220, 190, 160))
    d.rectangle([0, 0, w - 1, h - 1], outline=(92, 70, 44), width=4)
    d.line([(4, h - 6), (w - 4, h - 6)], fill=(120, 96, 64), width=3)  # chalk ledge
    finish(im, "chalkboard", colors=20)


def t_desk_wood():
    t_wood("desk_wood", base="9a6a3a", plank=32, s=128)
    # carve scratches into it
    p = os.path.join(OUT, "desk_wood.png")
    im = Image.open(p).convert("RGB"); d = ImageDraw.Draw(im); rng = rng_for("desk_scratch")
    for _ in range(14):
        x, y = rng.integers(0, 128), rng.integers(0, 128)
        d.line([(x, y), (x + rng.integers(-14, 14), y + rng.integers(-6, 6))], fill=(70, 46, 26))
    d.text((40, 60), "N♥L", font=font(FONT_HAND, 10), fill=(64, 40, 22))
    WRITTEN.pop(); finish(im, "desk_wood", colors=24)


def t_shelf_metal():
    s = 128; rng = rng_for("shelf_metal")
    n = fbm(s, s, rng, base=4, octaves=3)
    arr = lerp(col("b8bcbc"), col("d4d6d2"), n)
    yy, xx = np.mgrid[0:s, 0:s]
    holes = ((yy % 8) == 4) & ((xx % 8) == 4)
    arr[holes] = col("404448")
    # price-tag rail band at top (blue) with yellow price tags
    arr[0:10] = col("2a5aa0")
    for x in range(4, s, 32):
        arr[2:9, x:x + 14] = col("f0d040")
        arr[4:7, x + 2:x + 12] = col("303030")
    arr[10:12] = col("707478")
    sc = blobs(s, s, rng, 6, 2, 5)
    arr = shade(arr, 1 - 0.25 * sc)
    finish(arr, "shelf_metal", colors=20)


def t_fridge_back():
    """Interior of a drinks fridge: rows of cans & bottles (fictional colours), lit."""
    s = 128; rng = rng_for("fridge_back")
    im = Image.new("RGB", (s, s), (200, 210, 214)); d = ImageDraw.Draw(im)
    palette = [(200, 30, 30), (30, 120, 50), (240, 200, 40), (30, 60, 160), (230, 120, 30), (220, 220, 220), (120, 30, 120), (30, 150, 170)]
    for row in range(4):
        y1 = (row + 1) * 32 - 3
        d.rectangle([0, y1, s, y1 + 3], fill=(150, 156, 160))
        x = 1
        while x < s - 6:
            c = palette[rng.integers(0, len(palette))]
            kind = rng.random()
            if kind < 0.5:  # can
                d.rectangle([x, y1 - 12, x + 6, y1 - 1], fill=c)
                d.line([(x, y1 - 11), (x + 6, y1 - 11)], fill=(230, 230, 230))
                x += 8
            else:  # bottle
                d.rectangle([x, y1 - 20, x + 7, y1 - 1], fill=c)
                d.rectangle([x + 2, y1 - 26, x + 5, y1 - 20], fill=c)
                d.rectangle([x, y1 - 14, x + 7, y1 - 9], fill=(240, 240, 230))
                x += 9
    arr = to_arr(im)
    n = fbm(s, s, rng, base=4, octaves=2)
    arr = shade(arr, 0.85 + 0.2 * n)
    finish(arr, "fridge_back", colors=32)


def t_glass(name="glass", tint="9ab8c0", alpha=0.3, s=64):
    rng = rng_for(name)
    yy, xx = np.mgrid[0:s, 0:s]
    n = fbm(s, s, rng, base=4, octaves=3)
    arr = lerp(col(tint) * 0.8, col(tint) * 1.15, n)
    streak = (((xx + yy) % s) < 3).astype(float) * 0.7 + ((((xx + yy) + s // 3) % s) < 1) * 0.4
    smudge = np.clip((fbm(s, s, rng, base=3, octaves=2) - 0.6) * 3, 0, 1)
    arr = lerp(arr, np.ones(3), streak * 0.4)
    arr = lerp(arr, col("8a8a80"), smudge * 0.5)
    a = np.clip(alpha + 0.2 * streak + 0.15 * smudge + 0.06 * (n - 0.5), 0, 1)
    finish(arr, name, colors=12, alpha=a, alpha_levels=8)


def t_signs():
    rng = rng_for("signs")

    def sun(d, W, H):
        d.ellipse([W * 0.02, H * 0.12, W * 0.02 + H * 0.76, H * 0.88], fill=(255, 150, 30))
        d.ellipse([W * 0.02 + H * 0.12, H * 0.24, W * 0.02 + H * 0.64, H * 0.76], fill=(255, 220, 90))
        d.rectangle([0, H * 0.84, W, H], fill=(255, 150, 30))
    arr = sign_image(256, 64, (18, 92, 64), [("TIỆN LỢI 24h", (0.2, 0.06, 0.98, 0.56), FONT_BOLD, (255, 255, 240)),
                                            ("ÁNH DƯƠNG", (0.32, 0.54, 0.86, 0.84), FONT_REG, (255, 214, 80))],
                     (255, 255, 255), deco=sun, rng=rng, grime=0.12)
    finish(arr, "sign_store", colors=24)

    arr = sign_image(128, 64, (238, 232, 210), [("NHÀ TRỌ", (0.05, 0.05, 0.95, 0.6), FONT_BOLD, (190, 24, 24)),
                                               ("Sinh viên - Giá rẻ", (0.08, 0.62, 0.92, 0.9), FONT_REG, (30, 60, 140))],
                     (0, 0, 0), border=(190, 24, 24), rng=rng, grime=0.4)
    finish(arr, "sign_dorm", colors=20)

    arr = sign_image(256, 64, (180, 22, 20), [("PHỞ GÀ HƯƠNG", (0.04, 0.04, 0.96, 0.62), FONT_BOLD, (255, 222, 40)),
                                             ("Phở gà ta - Miến - Bún thang", (0.1, 0.62, 0.9, 0.92), FONT_REG, (255, 255, 255))],
                     (0, 0, 0), rng=rng, grime=0.3)
    finish(arr, "sign_pho", colors=20)

    arr = sign_image(256, 64, (24, 70, 170), [("SỬA XE MINH", (0.04, 0.04, 0.96, 0.62), FONT_BOLD, (255, 255, 255)),
                                             ("Vá săm - Thay dầu - Rửa xe", (0.08, 0.62, 0.92, 0.92), FONT_REG, (255, 230, 60))],
                     (0, 0, 0), rng=rng, grime=0.35)
    finish(arr, "sign_suaxe", colors=20)

    arr = sign_image(256, 64, (240, 210, 40), [("TẠP HÓA BÀ SÁU", (0.04, 0.04, 0.96, 0.62), FONT_BOLD, (200, 20, 20)),
                                              ("Bia - Nước ngọt - Gạo - Thẻ cào", (0.06, 0.62, 0.94, 0.92), FONT_REG, (20, 60, 150))],
                     (0, 0, 0), rng=rng, grime=0.35)
    finish(arr, "sign_taphoa", colors=20)

    def stars(d, W, H):
        for x in (0.05, 0.95):
            cx, cy, r = W * x, H * 0.5, H * 0.3
            pts = []
            for k in range(10):
                rr = r if k % 2 == 0 else r * 0.4
                a = -math.pi / 2 + k * math.pi / 5
                pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
            d.polygon(pts, fill=(255, 220, 40))
    arr = sign_image(256, 32, (190, 20, 20), [("PHƯỜNG XANH - SẠCH - ĐẸP - VĂN MINH", (0.11, 0.1, 0.89, 0.9), FONT_BOLD, (255, 225, 40))],
                     (0, 0, 0), deco=stars, rng=rng, grime=0.2)
    finish(arr, "banner_street", colors=16)

    arr = sign_image(256, 32, (190, 20, 20), [("CHÀO MỪNG NĂM HỌC MỚI 2026 - 2027", (0.04, 0.1, 0.96, 0.9), FONT_BOLD, (255, 225, 40))],
                     (0, 0, 0), rng=rng, grime=0.2)
    finish(arr, "banner_school", colors=16)

    arr = sign_image(256, 32, (20, 50, 130), [("TRƯỜNG ĐẠI HỌC KỸ THUẬT ĐÔ THỊ", (0.03, 0.1, 0.97, 0.9), FONT_BOLD, (255, 255, 255))],
                     (0, 0, 0), rng=rng, grime=0.25)
    finish(arr, "sign_school", colors=16)

    arr = sign_image(64, 32, (30, 90, 170), [("ĐIỂM DỪNG", (0.05, 0.05, 0.95, 0.5), FONT_BOLD, (255, 255, 255)),
                                            ("XE BUÝT", (0.05, 0.5, 0.95, 0.95), FONT_BOLD, (255, 255, 255))],
                     (0, 0, 0), rng=rng, grime=0.2)
    finish(arr, "sign_bus", colors=12)

    # number plate placeholder for dorm doors (blank enamel plate; level adds Label3D)
    arr = sign_image(64, 32, (230, 228, 214), [], (0, 0, 0), border=(40, 60, 120), rng=rng, grime=0.4)
    finish(arr, "plate_blank", colors=8)

    arr = sign_image(64, 32, (230, 228, 214), [("ĐẨY", (0.1, 0.1, 0.9, 0.9), FONT_BOLD, (200, 30, 30))],
                     (0, 0, 0), rng=rng, grime=0.1)
    finish(arr, "sticker_push", colors=8)

    arr = sign_image(128, 64, (240, 240, 230), [("MỞ CỬA 24/24", (0.05, 0.05, 0.95, 0.5), FONT_BOLD, (200, 30, 30)),
                                               ("Cả ngày lễ, Tết", (0.1, 0.55, 0.9, 0.9), FONT_REG, (20, 90, 60))],
                     (0, 0, 0), rng=rng, grime=0.05)
    finish(arr, "sticker_open", colors=12)


def t_posters():
    rng = rng_for("posters")
    # Cho thuê phòng (64x128 = 0.5 x 1 m? used at ~0.3x0.42 m)
    w, h = 64, 96
    im = Image.new("RGB", (w * 4, h * 4), (236, 232, 214)); d = ImageDraw.Draw(im)
    text_fit(d, (8, 8, w * 4 - 8, 120), "CHO THUÊ", FONT_BOLD, (200, 20, 20))
    text_fit(d, (8, 120, w * 4 - 8, 200), "PHÒNG", FONT_BOLD, (200, 20, 20))
    text_fit(d, (12, 210, w * 4 - 12, 250), "Khép kín, giờ giấc tự do", FONT_REG, (30, 30, 30))
    text_fit(d, (12, 255, w * 4 - 12, 295), "LH: 09x.xxx.xxxx", FONT_REG, (30, 30, 120))
    for i in range(8):  # tear-off tabs
        x = 8 + i * 30
        d.rectangle([x, 310, x + 24, h * 4 - 6], outline=(60, 60, 60), width=2)
        if i in (2, 5):
            d.rectangle([x, 310, x + 24, h * 4], fill=(120, 116, 104))
    arr = to_arr(im.resize((w, h), Image.Resampling.BOX))
    arr = shade(arr, 1 - 0.2 * drips(h, w, rng, n=5, length=(0.3, 0.8)))
    finish(arr, "poster_rent", colors=16)

    # Tìm người thân (lost person) — photo silhouette
    w, h = 64, 96
    im = Image.new("RGB", (w * 4, h * 4), (240, 240, 232)); d = ImageDraw.Draw(im)
    text_fit(d, (6, 6, w * 4 - 6, 70), "TÌM NGƯỜI THÂN", FONT_BOLD, (10, 10, 10))
    d.rectangle([60, 80, 196, 230], fill=(120, 120, 116))
    d.ellipse([98, 100, 158, 170], fill=(60, 60, 58))
    d.rectangle([84, 165, 172, 230], fill=(60, 60, 58))
    for k in range(6):
        y = 245 + k * 22
        d.line([(16, y), (w * 4 - 16 - rng.integers(0, 60), y)], fill=(40, 40, 40), width=6)
    text_fit(d, (10, 245 - 18, w * 4 - 10, 245), "Mất tích từ đêm 13/11", FONT_REG, (180, 20, 20))
    arr = to_arr(im.resize((w, h), Image.Resampling.BOX))
    arr = lerp(arr, col("c8c0a0"), fbm(h, w, rng, base=3, octaves=3) * 0.4)
    finish(arr, "poster_lost", colors=16)

    # landlord notice board paper (64x64)
    w, h = 64, 64
    im = Image.new("RGB", (w * 4, h * 4), (232, 228, 210)); d = ImageDraw.Draw(im)
    text_fit(d, (8, 6, w * 4 - 8, 50), "THÔNG BÁO", FONT_BOLD, (180, 20, 20))
    lines = ["Đóng tiền nhà trước ngày 5", "Khóa cổng lúc 23h", "Không phơi đồ ở hành lang", "Phòng 205: KHÔNG VÀO"]
    for k, t in enumerate(lines):
        text_fit(d, (10, 60 + k * 46, w * 4 - 10, 100 + k * 46), t, FONT_REG, (20, 20, 20))
    arr = to_arr(im.resize((w, h), Image.Resampling.BOX))
    finish(arr, "notice_paper", colors=12)


def t_roof_tiles():
    s = 128; rng = rng_for("roof_tiles")
    yy, xx = np.mgrid[0:s, 0:s]
    rowh = 16; colw = 16
    off = ((yy // rowh) % 2) * (colw // 2)
    lx = ((xx + off) % colw) / colw; ly = (yy % rowh) / rowh
    curve = np.sin(lx * math.pi)  # round channel tiles
    arr = shade(np.ones((s, s, 3)) * col("8e3c24"), 0.55 + 0.55 * curve * (0.5 + 0.5 * ly))
    arr[(yy % rowh) == rowh - 1] = col("3a1a10")
    n = fbm(s, s, rng, base=6, octaves=3)
    arr = shade(arr, 0.8 + 0.3 * n)
    moss = np.clip((fbm(s, s, rng, base=4, octaves=3) - 0.55) * 4, 0, 1)
    arr = lerp(arr, col("3c4426"), moss * 0.6)
    finish(arr, "roof_tiles", colors=20)


def t_lacquer_red():
    s = 128; rng = rng_for("lacquer_red")
    n = fbm(s, s, rng, base=4, octaves=4)
    arr = lerp(col("6e1a14"), col("a2321e"), n)
    peel = np.clip((fbm(s, s, rng, base=8, octaves=4) - 0.62) * 8, 0, 1)
    wood = t_wood_arr(s, s, rng) * 0.7
    arr = lerp(arr, wood, peel)
    yy, xx = np.mgrid[0:s, 0:s]
    gold = ((yy % 64) < 3) & (white(s, s, rng) > 0.3)
    arr[gold] = col("a8883a")
    st = drips(s, s, rng, n=10, length=(0.3, 0.9), width=(1, 3))
    arr = lerp(arr, col("2a1410"), st * 0.4)
    finish(arr, "lacquer_red", colors=20)


def t_altar():
    """Shrine altar front 128x128: red lacquer frame, gold carved border, faded centre panel."""
    s = 128; rng = rng_for("altar")
    n = fbm(s, s, rng, base=4, octaves=4)
    arr = lerp(col("5a1610"), col("8c2a1a"), n)
    im = to_img(arr); d = ImageDraw.Draw(im)
    gold = (170, 136, 58)
    d.rectangle([6, 6, s - 7, s - 7], outline=gold, width=3)
    d.rectangle([16, 16, s - 17, s - 17], outline=gold, width=1)
    for k in range(8):  # cloud/scroll motifs
        x = 20 + k * 12
        d.arc([x, 20, x + 10, 30], 180, 360, fill=gold, width=2)
        d.arc([x, s - 30, x + 10, s - 20], 0, 180, fill=gold, width=2)
    d.ellipse([s // 2 - 18, s // 2 - 18, s // 2 + 18, s // 2 + 18], outline=gold, width=2)  # longevity medallion
    d.line([(s // 2, s // 2 - 12), (s // 2, s // 2 + 12)], fill=gold, width=2)
    d.line([(s // 2 - 10, s // 2), (s // 2 + 10, s // 2)], fill=gold, width=2)
    d.rectangle([s // 2 - 8, s // 2 - 8, s // 2 + 8, s // 2 + 8], outline=gold)
    arr = to_arr(im)
    peel = np.clip((fbm(s, s, rng, base=8, octaves=3) - 0.6) * 6, 0, 1)
    arr = lerp(arr, col("4a3a2c"), peel * 0.8)
    arr = lerp(arr, col("1c120c"), drips(s, s, rng, n=12, length=(0.2, 0.7), width=(1, 2)) * 0.4)
    finish(arr, "altar", colors=20)


def t_bark():
    s = 128; rng = rng_for("bark")
    yy, xx = np.mgrid[0:s, 0:s]
    vn = vnoise(s, s, 4, 24, rng)
    fib = np.sin(xx * 0.6 + vn * 14) * 0.5 + 0.5
    n = fbm(s, s, rng, base=4, octaves=4)
    arr = lerp(col("3e3a30"), col("7a7262"), fib * 0.6 + n * 0.4)
    moss = np.clip((fbm(s, s, rng, base=6, octaves=3) - 0.55) * 4, 0, 1)
    arr = lerp(arr, col("3e4a28"), moss * 0.55)
    arr = shade(arr, 0.85 + 0.2 * white(s, s, rng))
    finish(arr, "bark", colors=20)


def t_leaves():
    s = 128; rng = rng_for("leaves")
    big = s * 2
    rgb = Image.new("RGB", (big, big), (30, 50, 24)); a = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(rgb); da = ImageDraw.Draw(a)
    for _ in range(420):
        x, y = rng.uniform(0, big), rng.uniform(0, big)
        r = rng.uniform(5, 11); ang = rng.uniform(0, math.pi * 2)
        c = tuple(int(v) for v in np.array([34, 70, 28]) * rng.uniform(0.6, 1.5))
        pts = [(x + math.cos(ang) * r * 1.6, y + math.sin(ang) * r * 1.6),
               (x + math.cos(ang + 1.7) * r * 0.6, y + math.sin(ang + 1.7) * r * 0.6),
               (x - math.cos(ang) * r * 0.6, y - math.sin(ang) * r * 0.6),
               (x + math.cos(ang - 1.7) * r * 0.6, y + math.sin(ang - 1.7) * r * 0.6)]
        for ox in (-big, 0, big):
            for oy in (-big, 0, big):
                p2 = [(px + ox, py + oy) for px, py in pts]
                d.polygon(p2, fill=c); da.polygon(p2, fill=255)
    rgb = rgb.resize((s, s), Image.Resampling.NEAREST); a = a.resize((s, s), Image.Resampling.BOX)
    finish(rgb, "leaves", colors=16, alpha=a)


def t_grass_dirt():
    s = 128; rng = rng_for("grass_dirt")
    n = fbm(s, s, rng, base=4, octaves=5); w = white(s, s, rng)
    dirt = lerp(col("5a4a36"), col("7a6448"), n)
    grass = lerp(col("3a4a22"), col("5a6a30"), w)
    m = np.clip((fbm(s, s, rng, base=6, octaves=3) - 0.45) * 5, 0, 1)
    arr = lerp(dirt, grass, m * (w > 0.3))
    arr = shade(arr, 0.85 + 0.2 * w)
    stones = (white(s, s, rng) > 0.985)
    arr[stones] = col("9a9488")
    finish(arr, "grass_dirt", colors=20)


def t_cables():
    """Tangled overhead power/telecom cables, alpha. Tiles horizontally (1 texture = 2 m)."""
    w, h = 256, 64; rng = rng_for("cables")
    big = 4
    a = Image.new("L", (w * big, h * big), 0); da = ImageDraw.Draw(a)
    rgb = Image.new("RGB", (w * big, h * big), (16, 16, 18)); d = ImageDraw.Draw(rgb)
    for k in range(22):
        y0 = rng.uniform(0.1, 0.6) * h * big; sag = rng.uniform(0.05, 0.35) * h * big
        ph = rng.uniform(0, 1); per = rng.choice([1, 2])
        width = int(rng.choice([4, 4, 6, 8]))
        c = (16, 16, 18) if rng.random() < 0.8 else (40, 40, 40)
        pts = []
        for i in range(65):
            t = i / 64.0
            y = y0 + sag * (1 - (2 * ((t * per + ph) % 1) - 1) ** 2) + math.sin(t * 6.28 * 3 + k) * 4
            pts.append((t * w * big, y))
        d.line(pts, fill=c, width=width); da.line(pts, fill=255, width=width)
    for _ in range(4):  # coils
        x, y = rng.uniform(0, w * big), rng.uniform(0.3, 0.8) * h * big
        for r in range(10, 34, 6):
            da.ellipse([x - r, y - r * 0.6, x + r, y + r * 0.6], outline=255, width=4)
            d.ellipse([x - r, y - r * 0.6, x + r, y + r * 0.6], outline=(20, 20, 20), width=4)
    rgb = rgb.resize((w, h), Image.Resampling.NEAREST); a = a.resize((w, h), Image.Resampling.BOX)
    finish(rgb, "cables", colors=6, alpha=np.clip(np.asarray(a) / 255.0 * 1.6, 0, 1))


def t_ceiling_panel():
    s = 128; rng = rng_for("ceiling_panel")
    n = fbm(s, s, rng, base=4, octaves=3)
    arr = lerp(col("c8c4b4"), col("dedad0"), n)
    arr = shade(arr, 0.92 + 0.1 * white(s, s, rng))
    yy, xx = np.mgrid[0:s, 0:s]
    grid = ((yy % 64) < 3) | ((xx % 64) < 3)
    arr[grid] = col("8c8a84")
    stain = blobs(s, s, rng, 2, 10, 22)
    arr = lerp(arr, col("a08a5a"), np.clip(stain * 1.5, 0, 0.6))
    ring = (abs(stain - 0.15) < 0.04)
    arr[ring] = col("7a6440")
    finish(arr, "ceiling_panel", colors=16)


def t_emissive():
    # fluorescent tube (u along tube)
    w, h = 64, 16
    yy, xx = np.mgrid[0:h, 0:w]
    v = 1 - abs(yy - h / 2) / (h / 2)
    arr = lerp(col("b8d8c0"), col("f4fff4"), np.clip(v * 1.4, 0, 1)[..., None])
    arr[:, :4] = col("707070"); arr[:, -4:] = col("707070")
    arr[:, 4:8] = arr[:, 4:8] * 0.75
    finish(arr, "fluoro_tube", colors=8)
    # sodium lamp lens
    s = 32; yy, xx = np.mgrid[0:s, 0:s]
    r = np.sqrt((yy - s / 2) ** 2 + (xx - s / 2) ** 2) / (s / 2)
    arr = lerp(col("ffd890"), col("e07a18"), np.clip(r, 0, 1)[..., None])
    finish(arr, "lamp_sodium", colors=8)
    # warm bulb
    arr = lerp(col("fff6d0"), col("e8b050"), np.clip(r, 0, 1)[..., None])
    finish(arr, "lamp_bulb", colors=8)
    # lit window (curtains, warm), 64x64
    rng = rng_for("window_lit")
    s = 64
    n = fbm(s, s, rng, base=4, octaves=3)
    arr = lerp(col("c88a40"), col("f0c070"), n)
    yy, xx = np.mgrid[0:s, 0:s]
    folds = np.sin(xx * 0.8) * 0.5 + 0.5
    arr = shade(arr, 0.75 + 0.3 * folds)
    bars = (xx % 10 < 2) | (yy < 3) | (yy > s - 4) | (xx < 3) | (xx > s - 4)
    arr[bars] = col("1c1a18")
    finish(arr, "window_lit", colors=12)
    # tv glow under door strip
    arr = np.ones((8, 32, 3)) * col("5a7ad0")
    finish(arr, "tv_glow", colors=4)


def t_window_bars():
    """Window with security bars (song sắt) over dark glass, 128x128 = 1 x 1 m."""
    s = 128; rng = rng_for("window_bars")
    yy, xx = np.mgrid[0:s, 0:s]
    n = fbm(s, s, rng, base=4, octaves=3)
    glass = lerp(col("141a1e"), col("2c363c"), n)
    glass = lerp(glass, col("4a5a62"), (((xx + yy * 0.6) % 50) < 6) * 0.5)
    arr = glass.copy()
    frame = (xx < 8) | (xx >= s - 8) | (yy < 8) | (yy >= s - 8) | ((xx >= 60) & (xx < 66))
    arr[frame] = col("6a5a44")
    bars = ((xx % 16) >= 6) & ((xx % 16) < 9)
    hbar = ((yy % 42) >= 20) & ((yy % 42) < 23)
    arr[bars | hbar] = col("2a3a34")
    arr = lerp(arr, col("6a3a22"), np.clip((fbm(s, s, rng, base=8, octaves=2) - 0.6) * 3, 0, 1) * (bars | hbar) * 0.7)
    sill = yy >= s - 10
    arr[sill] = col("8a8478")
    finish(arr, "window_bars", colors=20)


def t_incense_ash():
    s = 64; rng = rng_for("incense_ash")
    n = fbm(s, s, rng, base=4, octaves=4); w = white(s, s, rng)
    arr = lerp(col("6a665e"), col("b8b4a8"), n)
    arr = shade(arr, 0.85 + 0.25 * w)
    im = to_img(arr); d = ImageDraw.Draw(im)
    for _ in range(26):  # burnt-out incense stick stubs (red)
        x, y = rng.integers(2, s - 2), rng.integers(2, s - 2)
        d.line([(x, y), (x + rng.integers(-3, 4), y + rng.integers(-3, 4))], fill=(150, 30, 30))
    finish(im, "incense_ash", colors=12)


def t_misc():
    # painted metal (poles, gates, frames) green-grey
    t_concrete("metal_paint", base="4a5a52", s=64)
    t_concrete("metal_dark", base="34363a", s=64)
    t_concrete("metal_alu", base="a8acae", s=64)
    # plastic (stools, chairs) — slight fleck
    for nm, c in (("plastic_red", "c02a24"), ("plastic_blue", "2a5ab0"), ("plastic_green", "2a8a4a")):
        s = 32; rng = rng_for(nm)
        arr = shade(np.ones((s, s, 3)) * col(c), 0.9 + 0.15 * fbm(s, s, rng, base=2, octaves=2))
        finish(arr, nm, colors=6)
    # AC unit front grille
    s = 64; rng = rng_for("ac_unit")
    yy, xx = np.mgrid[0:s, 0:s]
    arr = shade(np.ones((s, s, 3)) * col("c8c8c0"), 0.9 + 0.1 * fbm(s, s, rng, base=4, octaves=2))
    r = np.sqrt((yy - 32) ** 2 + (xx - 24) ** 2)
    arr[(r < 20) & ((r.astype(int) % 4) < 2)] = col("5a5a58")
    arr[:, 50:] = arr[:, 50:] * 0.9
    arr = lerp(arr, col("4a4030"), drips(s, s, rng, n=6, length=(0.3, 0.9), width=(1, 2)) * 0.5)
    finish(arr, "ac_unit", colors=12)
    # cardboard box with fictional print
    s = 64; rng = rng_for("cardboard")
    im = to_img(shade(np.ones((s, s, 3)) * col("a8845a"), 0.9 + 0.15 * fbm(s, s, rng, base=4, octaves=3)))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 28, s, 34], fill=(150, 130, 90))
    text_fit(d, (6, 6, 58, 24), "MÌ GÓI", FONT_BOLD, (170, 40, 30))
    text_fit(d, (6, 38, 58, 56), "30 gói x 75g", FONT_REG, (60, 40, 30))
    finish(im, "cardboard", colors=12)
    # motorbike paint (maroon, Dream-like) & black plastic/tyre
    s = 64; rng = rng_for("bike_paint")
    arr = shade(np.ones((s, s, 3)) * col("6a1e22"), 0.85 + 0.25 * fbm(s, s, rng, base=4, octaves=2))
    arr[28:32, :] = col("d0c8b0")  # pinstripe
    finish(arr, "bike_paint", colors=10)
    arr = shade(np.ones((32, 32, 3)) * col("1e1e20"), 0.9 + 0.2 * fbm(32, 32, rng, base=4, octaves=2))
    finish(arr, "rubber", colors=6)
    # mattress / fabric
    s = 64; rng = rng_for("fabric")
    yy, xx = np.mgrid[0:s, 0:s]
    arr = np.where((((yy // 8) + (xx // 8)) % 2 == 0)[..., None], col("b8a8c8")[None, None], col("e0d8e8")[None, None])
    arr = shade(arr, 0.85 + 0.2 * fbm(s, s, rng, base=4, octaves=3))
    finish(arr, "fabric", colors=10)
    # bathroom wall tiles (white 20 cm)
    t_tiles("tile_bath", col("d8dcd6"), col("c8d0cc"), "707470", 32, checker=False, s=128, wear=0.45)
    # cork notice board
    s = 64; rng = rng_for("cork")
    arr = shade(np.ones((s, s, 3)) * col("9a7448"), 0.75 + 0.4 * white(s, s, rng))
    finish(arr, "cork", colors=10)
    # clock face
    s = 64
    im = Image.new("RGB", (s * 4, s * 4), (40, 40, 40)); d = ImageDraw.Draw(im)
    d.ellipse([8, 8, s * 4 - 8, s * 4 - 8], fill=(232, 228, 210))
    for k in range(12):
        a = k * math.pi / 6
        d.line([(128 + math.cos(a) * 96, 128 + math.sin(a) * 96), (128 + math.cos(a) * 112, 128 + math.sin(a) * 112)], fill=(20, 20, 20), width=8)
    d.line([(128, 128), (128, 52)], fill=(20, 20, 20), width=8)
    d.line([(128, 128), (180, 150)], fill=(20, 20, 20), width=10)
    finish(im.resize((s, s), Image.Resampling.BOX), "clock_face", colors=8)
    # cracked photo frame (portrait silhouette, sepia, crack)
    s = 64; rng = rng_for("photo")
    im = Image.new("RGB", (s, s), (30, 22, 14)); d = ImageDraw.Draw(im)
    d.rectangle([6, 4, 57, 59], fill=(150, 130, 96))
    d.ellipse([22, 12, 42, 34], fill=(70, 56, 40)); d.rectangle([16, 32, 48, 59], fill=(70, 56, 40))
    crack_lines(d, s, s, rng, 2, (230, 230, 220), seg=(4, 9), steps=(3, 6))
    finish(im, "photo_cracked", colors=10)
    # joss paper (vàng mã): yellow/gold square with red stamp
    s = 64; rng = rng_for("joss")
    im = to_img(shade(np.ones((s, s, 3)) * col("d8b040"), 0.85 + 0.2 * fbm(s, s, rng, base=4, octaves=2)))
    d = ImageDraw.Draw(im)
    d.rectangle([18, 18, 46, 46], fill=(200, 160, 50)); d.rectangle([24, 24, 40, 40], outline=(170, 30, 20), width=2)
    finish(im, "joss_paper", colors=8)
    # terracotta (pots, planters)
    t_concrete("terracotta", base="9a5236", s=64)
    # water / dark puddle
    s = 64; rng = rng_for("puddle")
    arr = lerp(col("101418"), col("2a343a"), fbm(s, s, rng, base=4, octaves=3))
    finish(arr, "puddle", colors=8)
    # tarp (blue tarpaulin)
    s = 64; rng = rng_for("tarp")
    arr = shade(np.ones((s, s, 3)) * col("2a5a9a"), 0.75 + 0.35 * fbm(s, s, rng, base=3, octaves=4))
    finish(arr, "tarp", colors=10)
    # laptop screen / phone card rack / cigarettes: generic colourful rack
    s = 64; rng = rng_for("rack")
    im = Image.new("RGB", (s, s), (60, 60, 64)); d = ImageDraw.Draw(im)
    pal = [(220, 220, 220), (200, 40, 40), (40, 80, 160), (240, 200, 40), (40, 140, 60)]
    for r in range(4):
        for c in range(8):
            d.rectangle([c * 8 + 1, r * 16 + 2, c * 8 + 6, r * 16 + 13], fill=pal[rng.integers(0, 5)])
    finish(im, "rack_goods", colors=12)
    # snack packets on shelves (front face of filled shelf)
    s = 128; rng = rng_for("shelf_goods")
    im = Image.new("RGB", (s, s), (90, 90, 96)); d = ImageDraw.Draw(im)
    pal = [(220, 50, 40), (240, 200, 40), (40, 120, 200), (60, 160, 70), (230, 130, 30), (240, 240, 230), (150, 60, 150)]
    for r in range(4):
        x = 0
        while x < s:
            ww = int(rng.integers(6, 14)); hh = int(rng.integers(14, 28)); c = pal[rng.integers(0, len(pal))]
            y1 = (r + 1) * 32 - 2
            d.rectangle([x, y1 - hh, x + ww - 1, y1], fill=c)
            d.rectangle([x + 2, y1 - hh + 4, x + ww - 3, y1 - hh + 7], fill=(250, 250, 250))
            x += ww + 1
        d.rectangle([0, (r + 1) * 32 - 2, s, (r + 1) * 32], fill=(180, 184, 186))
    finish(im, "shelf_goods", colors=24)
    # laptop screen dim
    arr = np.ones((32, 32, 3)) * col("3a5a8a"); arr[2:6, 2:30] = col("dddddd")
    finish(arr, "screen", colors=6)
    # black-white checker? stove/gas: use metal_alu. mirror: glass.
    t_glass("mirror", tint="b0c4c8", alpha=0.95, s=32)
    t_glass("glass", tint="9ab8c0", alpha=0.16, s=64)
    t_glass("glass_dirty", tint="8a9a8a", alpha=0.45, s=64)


def contact_sheet(path):
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".png"))
    cell = 136; cols = 10; rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 12)), (255, 0, 255))
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        im = Image.open(os.path.join(OUT, f)).convert("RGBA")
        im.thumbnail((128, 128), Image.Resampling.NEAREST)
        if im.width < 64:
            im = im.resize((im.width * 2, im.height * 2), Image.Resampling.NEAREST)
        x, y = (i % cols) * cell, (i // cols) * (cell + 12)
        sheet.paste(im, (x + 4, y + 4), im)
        d.text((x + 2, y + cell - 4), f[:-4][:22], fill=(255, 255, 255))
    sheet.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    t_asphalt("asphalt"); t_asphalt("asphalt_line", line=True)
    t_sidewalk()
    t_concrete("concrete"); t_concrete("concrete_dark", base="5c5a56")
    t_wall("wall_yellow", "d8b860"); t_wall("wall_green", "a8c0a0"); t_wall("wall_white", "d8d6cc")
    t_wall("wall_blue", "8cacc4"); t_wall("wall_pink", "c89a94")
    t_brick()
    t_tiles("tile_red", col("9a4a32"), col("8a4230"), "4a3028", 32, checker=False, wear=0.35)
    t_tiles("tile_checker", col("a04a34"), col("c8b490"), "5a4a3a", 32, checker=True, wear=0.3)
    t_tiles("tile_beige", col("d4ccb4"), col("ccc4ac"), "8a8474", 64, checker=False, wear=0.25)
    t_tiles("tile_pattern", col("c8bc9c"), col("7a3a2a"), "5a4a3a", 32, checker=False, wear=0.3, pattern=True)
    t_wood("wood_planks"); t_wood("wood_dark", base="4a3222", plank=16)
    t_door_wood(); t_door_dorm()
    t_railing("railing"); t_railing("iron_gate")
    t_shutter("shutter_grey", "8c9090"); t_shutter("shutter_green", "5a7a6a"); t_shutter("shutter_blue", "5a6a8a", ads=False)
    t_chalkboard(); t_desk_wood(); t_shelf_metal(); t_fridge_back()
    t_signs(); t_posters(); t_roof_tiles(); t_lacquer_red(); t_altar(); t_bark(); t_leaves()
    t_grass_dirt(); t_cables(); t_ceiling_panel(); t_emissive(); t_window_bars(); t_incense_ash(); t_misc()
    for n, sz, a in sorted(WRITTEN):
        print(f"{n:18s} {sz[0]}x{sz[1]} {a}")
    print(f"{len(WRITTEN)} textures -> {OUT}")
    if "--sheet" in sys.argv:
        contact_sheet(sys.argv[sys.argv.index("--sheet") + 1])


if __name__ == "__main__":
    main()
