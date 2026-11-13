#!/usr/bin/env python3
"""Patch the TITLE_ID inside a Vita VPK's param.sfo (in place, no re-layout).

Why: the SonicMastr godot-vita fork editor's CLI `--export` ignores the
`param_sfo/title_id` preset option and writes the project name
("Sleeze Disco") as TITLE_ID. The v1 VPK (exported via the editor UI)
has the correct SLEEZDSC1. This script fixes the CLI export's SFO after
the fact: it overwrites the TITLE_ID value bytes in place (new value is
shorter than the old one, so all offsets stay valid) and updates the
entry's data_len. TITLE/STITLE ("Sleeze Disco") are left alone.

Usage: patch_title_id.py <input.vpk> <output.vpk> [TITLE_ID]
Default TITLE_ID: SLEEZDSC1.
"""
import struct
import sys
import zipfile

DEFAULT_TITLE_ID = "SLEEZDSC1"


def patch_sfo(data: bytearray, title_id: str) -> bytearray:
    magic, _ver, kts, dts, n = struct.unpack_from("<IIIII", data, 0)
    assert magic == 0x46535000, "not a param.sfo (bad magic)"
    new_val = title_id.encode() + b"\x00"
    for i in range(n):
        off = 20 + i * 16
        ko, fmt, dlen, dmax, doff = struct.unpack_from("<HHIII", data, off)
        kend = data.index(b"\x00", kts + ko)
        key = data[kts + ko:kend].decode()
        if key != "TITLE_ID":
            continue
        assert fmt in (0x0402, 0x0204), "TITLE_ID is not a string entry"
        assert len(new_val) <= dmax, "new TITLE_ID does not fit (max %d)" % dmax
        assert len(new_val) <= dlen, "new TITLE_ID longer than old value"
        # Overwrite the value in place; zero the leftover tail bytes.
        start = dts + doff
        data[start:start + len(new_val)] = new_val
        for j in range(len(new_val), dlen):
            data[start + j] = 0
        # data_len lives at entry offset + 4 (after key_offset u16 + fmt u16).
        struct.pack_into("<I", data, off + 4, len(new_val))
        return data
    raise SystemExit("TITLE_ID entry not found in param.sfo")


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    title_id = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_TITLE_ID
    assert len(title_id) == 9, "Vita TITLE_ID must be 9 characters"
    with zipfile.ZipFile(src, "r") as zin:
        entries = [(info, zin.read(info.filename)) for info in zin.infolist()]
    patched = None
    out_entries = []
    for info, blob in entries:
        if info.filename == "sce_sys/param.sfo":
            patched = patch_sfo(bytearray(blob), title_id)
            out_entries.append((info, bytes(patched)))
        else:
            out_entries.append((info, blob))
    if patched is None:
        raise SystemExit("sce_sys/param.sfo not found in " + src)
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for info, blob in out_entries:
            zout.writestr(info, blob)
    print("patched TITLE_ID -> %s in %s" % (title_id, dst))


if __name__ == "__main__":
    main()
