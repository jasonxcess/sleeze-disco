#!/usr/bin/env python3
"""Check or fix PS Vita LiveArea PNGs so VitaShell doesn't fail with 0x8010113D.

The Vita's package installer only accepts 8-bit indexed-palette PNGs
(IHDR bit depth 8, color type 3, not interlaced) in sce_sys/. RGB/RGBA
images display fine in the editor but make the install fail at ~99%.

usage:
  vita_livearea.py check <dir-or-vpk> [...]   # exit 1 if any PNG is bad
  vita_livearea.py fix <png> [...]            # rewrite in place as 8-bit palette
"""
import io, struct, sys, zipfile

SIZES = {"icon0.png": (128, 128), "bg.png": (840, 500), "bg0.png": (840, 500),
         "startup.png": (280, 158), "pic0.png": (960, 544)}


def ihdr(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    w, h, depth, ctype, _c, _f, interlace = struct.unpack(">IIBBBBB", data[16:29])
    return w, h, depth, ctype, interlace


def has_trns(data):
    pos = 8
    while pos + 8 <= len(data):
        ln, tag = struct.unpack(">I4s", data[pos:pos + 8])
        if tag == b"tRNS":
            return True
        if tag == b"IDAT":
            return False
        pos += 12 + ln
    return False


def problems(name, data):
    base = name.rsplit("/", 1)[-1]
    h = ihdr(data)
    if h is None:
        return ["not a PNG"]
    w, ht, depth, ctype, interlace = h
    out = []
    if (depth, ctype) != (8, 3):
        out.append(f"depth={depth} colortype={ctype} (need 8-bit palette: depth=8 colortype=3)")
    if interlace:
        out.append("interlaced")
    if base in SIZES and (w, ht) != SIZES[base]:
        out.append(f"size {w}x{ht} (need {SIZES[base][0]}x{SIZES[base][1]})")
    if base == "icon0.png" and has_trns(data):
        out.append("icon0 has transparency (not allowed)")
    return out


def iter_pngs(path):
    if path.lower().endswith(".vpk"):
        with zipfile.ZipFile(path) as z:
            for n in z.namelist():
                if n.startswith("sce_sys/") and n.lower().endswith(".png"):
                    yield f"{path}:{n}", z.read(n)
    else:
        import glob, os
        for p in sorted(glob.glob(os.path.join(path, "**", "*.png"), recursive=True)):
            yield p, open(p, "rb").read()


def check(paths):
    bad = 0
    for path in paths:
        for name, data in iter_pngs(path):
            pr = problems(name, data)
            print(("FAIL " if pr else "OK   ") + name + ("  " + "; ".join(pr) if pr else ""))
            bad += bool(pr)
    return 1 if bad else 0


def fix(paths):
    from PIL import Image
    for p in paths:
        im = Image.open(p).convert("RGB")  # drop alpha (icon0 must not have any)
        q = im.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)
        pal = q.getpalette()[:768]
        q.putpalette(pal + [0] * (768 - len(pal)))  # full 256 entries -> Pillow writes 8-bit
        buf = io.BytesIO()
        q.save(buf, "PNG", optimize=False, bits=8)
        data = buf.getvalue()
        pr = problems(p, data)
        if pr:
            sys.exit(f"{p}: conversion still bad: {pr}")
        open(p, "wb").write(data)
        print("fixed", p)


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("check", "fix"):
        sys.exit(__doc__)
    sys.exit(check(sys.argv[2:]) if sys.argv[1] == "check" else fix(sys.argv[2:]))
