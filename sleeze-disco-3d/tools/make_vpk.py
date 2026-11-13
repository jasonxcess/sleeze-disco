#!/usr/bin/env python3
"""Re-pack a Godot-vita exported VPK with a correct param.sfo.

The 3.5-rc5-vita1 exporter writes some param.sfo fields into the wrong slots
(seen here: TITLE_ID got the title string; in a test export VERSION got the
title). This tool keeps eboot.bin, module/, game_data/game.pck and the
LiveArea files from the Godot export and writes a fresh param.sfo laid out
exactly like vita-mksfoex's output (same keys, formats and max lengths as the
official godot-vita demo VPK).

usage: make_vpk.py <godot_export.vpk> <out.vpk> [--title T] [--title-id ID] [--app-ver XX.YY]
"""
import struct, sys, zipfile, argparse, re


def livearea_problems(name, data):
    """The Vita installer rejects any sce_sys PNG that is not 8-bit palette
    (IHDR depth=8, colortype=3, non-interlaced) with error 0x8010113D at ~99%."""
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return ["not a PNG"]
    depth, ctype, interlace = data[24], data[25], data[28]
    out = []
    if (depth, ctype) != (8, 3):
        out.append("depth=%d colortype=%d, need 8-bit palette (fix: python3 tools/vita_livearea.py fix <png>)" % (depth, ctype))
    if interlace:
        out.append("interlaced")
    return out

def sfo(title, title_id, app_ver, parental=0):
    # (key, fmt, value, max_len); fmt 0x204 = utf8 string, 0x404 = u32
    E = [
        ("APP_VER", 0x204, app_ver, 8),
        ("ATTRIBUTE", 0x404, 32768, 4),
        ("ATTRIBUTE2", 0x404, 12, 4),
        ("ATTRIBUTE_MINOR", 0x404, 16, 4),
        ("BOOT_FILE", 0x204, "", 32),
        ("CATEGORY", 0x204, "gd", 4),
        ("CONTENT_ID", 0x204, "", 48),
        ("EBOOT_APP_MEMSIZE", 0x404, 0, 4),
        ("EBOOT_ATTRIBUTE", 0x404, 0, 4),
        ("EBOOT_PHY_MEMSIZE", 0x404, 0, 4),
        ("LAREA_TYPE", 0x404, 0, 4),
        ("NP_COMMUNICATION_ID", 0x204, "", 16),
        ("PARENTAL_LEVEL", 0x404, parental, 4),
        ("PSP2_DISP_VER", 0x204, "00.000", 8),
        ("PSP2_SYSTEM_VER", 0x404, 0, 4),
        ("STITLE", 0x204, title[:51], 52),
        ("TITLE", 0x204, title[:127], 128),
        ("TITLE_ID", 0x204, title_id, 12),
        ("VERSION", 0x204, "00.00", 8),
    ]
    keys = b""
    koffs = []
    for k, *_ in E:
        koffs.append(len(keys))
        keys += k.encode() + b"\0"
    while len(keys) % 4:
        keys += b"\0"
    kt = 20 + 16 * len(E)
    dt = kt + len(keys)
    index, data = b"", b""
    for (k, fmt, v, mx), ko in zip(E, koffs):
        if fmt == 0x404:
            raw = struct.pack("<I", v); ln = 4
        else:
            raw = v.encode() + b"\0"; ln = len(raw)
            assert ln <= mx, k
        index += struct.pack("<HHIII", ko, fmt, ln, mx, len(data))
        data += raw.ljust(mx, b"\0")
    return struct.pack("<IIIII", 0x46535000, 0x101, kt, dt, len(E)) + index + keys + data

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("--title", default="SLEEZE DISCO 3D")
    ap.add_argument("--title-id", default="SLZD00002")
    ap.add_argument("--app-ver", default="01.00")
    a = ap.parse_args()
    assert re.fullmatch(r"[A-Z]{4}\d{5}", a.title_id), "TITLE_ID must be 4 capitals + 5 digits"
    assert re.fullmatch(r"\d\d\.\d\d", a.app_ver), "APP_VER must be XX.YY"
    zin = zipfile.ZipFile(a.src)
    bad = []
    for n in zin.namelist():
        if n.startswith("sce_sys/") and n.lower().endswith(".png"):
            bad += ["%s: %s" % (n, p) for p in livearea_problems(n, zin.read(n))]
    if bad:
        sys.exit("refusing to pack, VitaShell would fail with 0x8010113D:\n  " + "\n  ".join(bad))
    with zipfile.ZipFile(a.dst, "w", zipfile.ZIP_DEFLATED) as zout:
        zout.writestr("sce_sys/param.sfo", sfo(a.title, a.title_id, a.app_ver))
        for it in zin.infolist():
            if it.filename == "sce_sys/param.sfo":
                continue
            # pck + eboot are large and already dense; store keeps install fast
            comp = zipfile.ZIP_STORED if it.filename.endswith((".pck", ".bin", ".suprx", ".skprx")) else zipfile.ZIP_DEFLATED
            zout.writestr(zipfile.ZipInfo(it.filename, date_time=it.date_time), zin.read(it.filename), compress_type=comp)
    print("wrote", a.dst)

if __name__ == "__main__":
    main()
