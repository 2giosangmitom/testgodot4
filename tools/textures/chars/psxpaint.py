"""Tiny procedural painting helpers for PSX-style textures (PIL + numpy).

Paint at high resolution with soft masks in normalized coordinates (0..1, v down),
then `finalize()` downsamples like a photo, adds grain, and quantizes to RGB565
with a 4x4 Bayer dither (PS1 look).
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0 - 0.5


def rgb(c):
    return np.array(c[:3], dtype=np.float32)


class Canvas:
    def __init__(self, w, h, color=(128, 128, 128), seed=0):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 3), dtype=np.float32)
        self.px[:] = rgb(color)
        self.rng = np.random.default_rng(seed)
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        self.u = (xx + 0.5) / w
        self.v = (yy + 0.5) / h

    # ---------- masks (float HxW in 0..1) ----------
    def _mask_from_draw(self, fn, blur):
        img = Image.new("L", (self.w, self.h), 0)
        d = ImageDraw.Draw(img)
        fn(d)
        if blur > 0:
            img = img.filter(ImageFilter.GaussianBlur(blur * self.w))
        return np.asarray(img, dtype=np.float32) / 255.0

    def P(self, x, y):
        return (x * self.w, y * self.h)

    def ellipse(self, cx, cy, rx, ry, blur=0.0):
        return self._mask_from_draw(
            lambda d: d.ellipse([self.P(cx - rx, cy - ry), self.P(cx + rx, cy + ry)], fill=255), blur)

    def rect(self, x0, y0, x1, y1, blur=0.0):
        return self._mask_from_draw(lambda d: d.rectangle([self.P(x0, y0), self.P(x1, y1)], fill=255), blur)

    def poly(self, pts, blur=0.0):
        return self._mask_from_draw(lambda d: d.polygon([self.P(*p) for p in pts], fill=255), blur)

    def line(self, pts, width, blur=0.0):
        wpx = max(1, int(round(width * self.w)))
        return self._mask_from_draw(lambda d: d.line([self.P(*p) for p in pts], fill=255, width=wpx, joint="curve"), blur)

    def radial(self, cx, cy, rx, ry, power=2.0):
        d = np.sqrt(((self.u - cx) / rx) ** 2 + ((self.v - cy) / ry) ** 2)
        return np.clip(1.0 - d, 0, 1) ** power

    # ---------- painting ----------
    def blend(self, mask, color, alpha=1.0):
        m = (np.clip(mask, 0, 1) * alpha)[..., None]
        self.px = self.px * (1 - m) + rgb(color) * m

    def shade(self, mask, factor):
        """factor <1 darkens, >1 lightens, weighted by mask."""
        m = np.clip(mask, 0, 1)[..., None]
        self.px = self.px * (1 + (factor - 1) * m)

    def tint(self, mask, color, amount):
        self.blend(mask, color, amount)

    def noise(self, amount, scale=1):
        h, w = self.h // scale + 1, self.w // scale + 1
        n = self.rng.normal(0, amount, (h, w)).astype(np.float32)
        n = np.kron(n, np.ones((scale, scale), dtype=np.float32))[: self.h, : self.w]
        self.px += n[..., None]

    def streaks(self, mask, color, count, length, width=0.004, angle_jitter=0.15, alpha=0.5, direction=(0, 1)):
        """Random hair/straw strands inside mask."""
        img = Image.new("L", (self.w, self.h), 0)
        d = ImageDraw.Draw(img)
        ys, xs = np.nonzero(mask > 0.5)
        if len(xs) == 0:
            return
        for _ in range(count):
            i = self.rng.integers(len(xs))
            x, y = xs[i] / self.w, ys[i] / self.h
            dx, dy = direction
            dx += self.rng.normal(0, angle_jitter)
            ln = length * self.rng.uniform(0.5, 1.2)
            d.line([self.P(x, y), self.P(x + dx * ln, y + dy * ln)], fill=int(255 * alpha * self.rng.uniform(0.5, 1)),
                   width=max(1, int(width * self.w)))
        m = np.asarray(img, dtype=np.float32) / 255.0 * np.clip(mask, 0, 1)
        self.blend(m, color, 1.0)

    def image(self):
        return Image.fromarray(np.clip(self.px, 0, 255).astype(np.uint8), "RGB")


def finalize(img, size, grain=3.0, seed=1, dither=True, sharpen=True, posterize_bits=5, alpha=None):
    """Downsample like a photo, add grain, quantize to RGB565-ish with Bayer dither."""
    small = img.resize(size, Image.LANCZOS)
    if sharpen:
        small = small.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
    a = np.asarray(small, dtype=np.float32).copy()
    rng = np.random.default_rng(seed)
    a += rng.normal(0, grain, a.shape[:2])[..., None]
    if dither:
        h, w = a.shape[:2]
        b = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
        a += b[..., None] * 8.0
    a = np.clip(a, 0, 255)
    # RGB565
    r = (a[..., 0].astype(np.uint8) >> 3) << 3
    g = (a[..., 1].astype(np.uint8) >> 2) << 2
    bch = (a[..., 2].astype(np.uint8) >> 3) << 3
    out = np.stack([r, g, bch], -1)
    if posterize_bits < 5:
        sh = 8 - posterize_bits
        out = (out >> sh) << sh
    out = np.clip(out.astype(np.int32) + np.array([4, 2, 4]), 0, 255).astype(np.uint8)  # re-center quantization
    im = Image.fromarray(out, "RGB")
    if alpha is not None:
        al = alpha.resize(size, Image.NEAREST)
        im = im.convert("RGBA")
        im.putalpha(al)
    return im


def quantize565(img):
    """Quantize an already-small image (no resize)."""
    return finalize(img, img.size, grain=0, dither=False, sharpen=False)
