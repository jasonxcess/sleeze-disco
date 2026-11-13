#!/usr/bin/env python3
"""Sleeze Disco — split the web sprite sheets into POT frames for Godot.
Source: ~/workspace/games/sleeze-disco-v7/sleeze-disco-master/assets/sheet_*.png
Meta: PORT_SPEC.md §13.1 (ANIM_SHEETS, verbatim).

Layout: every frame is padded to a 512x256 POT canvas. The frame is placed
so its ground point (anchorX, groundY) lands at canvas (256, 232) — i.e.
frame left = 256 - anchorX, frame top = 232 - groundY. That puts the
ground point 104 px below the texture centre, so in Godot the sprite
child sits at (0, -104 * scale) with the fighter node's origin at the
feet. No per-frame offset math at runtime.

Only the clips each character actually uses are split (see CLIPS_NEEDED):
the player needs all 20 clips; VEX needs its fight clips; thug/dead use
their 10-clip subsets (CLIP_FALLBACK covers the rest at runtime).

Output: assets/sheets/<key>/<clip>_<idx:03d>.png (idx = frame number
within the clip, 0-based).
Usage: python3 tools/split_sheets.py [--src DIR] [--out DIR]
"""
import argparse, os
from PIL import Image

# sheet key -> (source file, frame w, frame h, anchorX, groundY)
SHEETS = {
    "psxm": ("sheet_psxm_player.png", 243, 225, 108, 216.1),
    "psxw": ("sheet_psxw_vex.png", 392, 214, 220, 205.1),
    "thug": ("sheet_thug.png", 195, 209, 82, 200.1),
    "dead": ("sheet_dead_skeleton.png", 236, 232, 87, 223.1),
}

# clip -> [startFrame, frameCount], 16 columns (verbatim from ANIM_SHEETS).
CLIPS_FULL = {
    "idle": [0, 9], "walk": [9, 14], "punch": [23, 11], "kick": [34, 10],
    "throw": [44, 11], "windup": [55, 7], "hit": [62, 8], "knock": [70, 12],
    "getup": [82, 16], "block": [98, 6], "upper": [104, 10], "taunt": [114, 10],
    "hiphop": [124, 24], "headspin": [148, 8], "flair": [156, 10],
    "spinback": [166, 14], "sweep": [180, 12], "armada": [192, 12],
    "meialua": [204, 12], "spinflip": [216, 12],
}
CLIPS_SUBSET = {
    "idle": [0, 9], "walk": [9, 14], "punch": [23, 11], "kick": [34, 10],
    "throw": [44, 11], "windup": [55, 7], "hit": [62, 8], "knock": [70, 12],
    "upper": [82, 10], "taunt": [92, 10],
}

# Which clips each sheet actually needs in the Godot build.
CLIPS_NEEDED = {
    "psxm": list(CLIPS_FULL.keys()),  # player: every clip (fights + dance + finisher)
    "psxw": ["idle", "walk", "punch", "kick", "windup", "hit", "knock",
             "upper", "taunt"],  # VEX: fight clips only
    "thug": list(CLIPS_SUBSET.keys()),  # stan / bruiser / boss1
    "dead": list(CLIPS_SUBSET.keys()),  # charger / boss2
}

CANVAS_W, CANVAS_H = 512, 256
GROUND_X, GROUND_Y = 256, 232  # ground point in the padded canvas


def split_sheet(key, src_dir, out_dir):
    fname, fw, fh, anchor_x, ground_y = SHEETS[key]
    path = os.path.join(src_dir, fname)
    sheet = Image.open(path).convert("RGBA")
    cols = sheet.width // fw
    clips = CLIPS_FULL if key in ("psxm", "psxw") else CLIPS_SUBSET
    total = 0
    for clip in CLIPS_NEEDED[key]:
        start, count = clips[clip]
        clip_dir = os.path.join(out_dir, key)
        os.makedirs(clip_dir, exist_ok=True)
        for i in range(count):
            f = start + i
            col, row = f % cols, f // cols
            frame = sheet.crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh))
            canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
            px = int(round(GROUND_X - anchor_x))
            py = int(round(GROUND_Y - ground_y))
            canvas.paste(frame, (px, py), frame)
            canvas.save(os.path.join(clip_dir, "%s_%03d.png" % (clip, i)))
            total += 1
    print("%s: %d frames -> %s" % (key, total, os.path.join(out_dir, key)))
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="/home/hatch/workspace/games/sleeze-disco-v7/sleeze-disco-master/assets")
    ap.add_argument("--out", default="assets/sheets")
    a = ap.parse_args()
    total = 0
    for key in SHEETS:
        total += split_sheet(key, a.src, a.out)
    print("total frames: %d" % total)


if __name__ == "__main__":
    main()
