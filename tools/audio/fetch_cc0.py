#!/usr/bin/env python3
"""Download CC0 sound packs into tools/audio/_downloads/<source>/ (gitignored).

Only sources whose page states CC0 are listed here; the license page was checked by hand and
is re-checked automatically (the script looks for the CC0 marker on the page before downloading).
Nothing from the downloads is ever executed — archives are only unpacked (zip, path-sanitised).

Run:  python3 -I tools/audio/fetch_cc0.py [--force]
"""
from __future__ import annotations

import argparse
import http.cookiejar
import json
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DL = ROOT / "_downloads"
UA = "Mozilla/5.0 (X11; Linux x86_64) asset-fetch"

# Kenney packs: page -> zip via the site's signed download-link endpoint. All Kenney assets are CC0.
KENNEY = ["impact-sounds", "interface-sounds", "rpg-audio", "ui-audio"]

# OpenGameArt: (page slug, [file urls]) — each page lists "License(s): CC0".
OGA = [
    ("dog-barking-mono", ["https://opengameart.org/sites/default/files/dog_barking_mono.wav"]),
    ("boiling-water-loops", ["https://opengameart.org/sites/default/files/cooking_with_cover_01.ogg",
                             "https://opengameart.org/sites/default/files/cooking_without_cover_01.ogg"]),
    ("breathing-tired", ["https://opengameart.org/sites/default/files/breathing%20tired.wav"]),
    ("horror-breathing", ["https://opengameart.org/sites/default/files/horrorbreathing.zip"]),
    ("100-cc0-metal-and-wood-sfx", ["https://opengameart.org/sites/default/files/100-CC0-wood-metal-SFX.zip"]),
    ("10-book-page-flips", ["https://opengameart.org/sites/default/files/book_flips_-_starninjas.zip"]),
]


def opener():
    cj = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    op.addheaders = [("User-Agent", UA)]
    return op


def fetch(op, url, referer=None) -> bytes:
    req = urllib.request.Request(url)
    if referer:
        req.add_header("Referer", referer)
    with op.open(req, timeout=120) as r:
        return r.read()


def safe_unzip(zp: Path, dest: Path) -> int:
    n = 0
    with zipfile.ZipFile(zp) as z:
        for info in z.infolist():
            name = info.filename.replace("\\", "/")
            if info.is_dir() or name.startswith("/") or ".." in name.split("/"):
                continue
            if not name.lower().endswith((".ogg", ".wav", ".mp3", ".flac", ".txt", ".md")):
                continue  # audio + license text only
            out = (dest / name).resolve()
            if not str(out).startswith(str(dest.resolve())):
                continue
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(z.read(info))
            n += 1
    return n


def get_kenney(op, slug, force):
    dest = DL / "kenney" / slug
    if dest.exists() and any(dest.rglob("*.ogg")) and not force:
        print(f"[kenney] {slug}: cached")
        return True
    page_url = f"https://kenney.nl/assets/{slug}"
    page = fetch(op, page_url).decode("utf8", "replace")
    if "publicdomain/zero/1.0" not in page:
        print(f"[kenney] {slug}: CC0 marker not found on page — skipped")
        return False
    m = re.search(r"data-download-id='([0-9a-f]+)'", page)
    if not m:
        print(f"[kenney] {slug}: no download id — skipped")
        return False
    info = json.loads(fetch(op, f"https://kenney.nl/download-link/{m.group(1)}", referer=page_url))
    if "url" not in info:
        print(f"[kenney] {slug}: download refused {info}")
        return False
    dest.mkdir(parents=True, exist_ok=True)
    zp = dest / f"{slug}.zip"
    zp.write_bytes(fetch(op, info["url"], referer=page_url))
    n = safe_unzip(zp, dest / "files")
    zp.unlink()
    (dest / "SOURCE.txt").write_text(f"{page_url}\nLicense: CC0 1.0 (Kenney, www.kenney.nl)\n")
    print(f"[kenney] {slug}: {n} files")
    return True


def get_oga(op, slug, urls, force):
    dest = DL / "oga" / slug
    if dest.exists() and (dest / "SOURCE.txt").exists() and not force:
        print(f"[oga] {slug}: cached")
        return True
    page_url = f"https://opengameart.org/content/{slug}"
    page = fetch(op, page_url).decode("utf8", "replace")
    if "license-name'>CC0<" not in page:
        print(f"[oga] {slug}: CC0 not listed on page — skipped")
        return False
    author = re.search(r"Author:.*?<a[^>]*>([^<]+)</a>", page, re.S)
    dest.mkdir(parents=True, exist_ok=True)
    for u in urls:
        fn = urllib.request.unquote(u.rsplit("/", 1)[1])
        data = fetch(op, u, referer=page_url)
        p = dest / fn
        p.write_bytes(data)
        if fn.endswith(".zip"):
            safe_unzip(p, dest / "files")
            p.unlink()
    (dest / "SOURCE.txt").write_text(
        f"{page_url}\nAuthor: {author.group(1).strip() if author else '?'}\nLicense: CC0 1.0\n")
    print(f"[oga] {slug}: ok")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    op = opener()
    ok = 0
    for s in KENNEY:
        try:
            ok += get_kenney(op, s, a.force)
        except Exception as e:  # network / site changes: synthesis is the fallback
            print(f"[kenney] {s}: FAILED {e}")
    for slug, urls in OGA:
        try:
            ok += get_oga(op, slug, urls, a.force)
        except Exception as e:
            print(f"[oga] {slug}: FAILED {e}")
    print(f"{ok}/{len(KENNEY) + len(OGA)} sources available")
    return 0


if __name__ == "__main__":
    sys.exit(main())
