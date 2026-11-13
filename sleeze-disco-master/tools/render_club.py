"""Render the Night Dance Club Lowpoly stage (map/source/Club.fbx) into
pre-rendered backdrop layers for the HTML build.

Layers (same camera + bounds, so they composite exactly):
  far    — the room shell + furniture, WITHOUT the light fixtures
  lights — disco ball + hanging spotlights + neon (mat 4/9/10/11 and the
           Disco / Hanging_SpotLight / SpotLight_* nodes). Drawn over the
           far layer in-game and pulsed on the beat.

Usage: python3 tools/render_club.py [--preview]  (preview = 480x272)
Writes assets/bg_club_far.png and assets/bg_club_lights.png.
"""
import sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from rig import Model, view_yaw, raster

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FBX = os.path.join(ROOT, 'map', 'source', 'Club.fbx')
TEX = os.path.join(ROOT, 'map', 'textures')
OUT_FAR = os.path.join(ROOT, 'assets', 'bg_club_far.png')
OUT_LIT = os.path.join(ROOT, 'assets', 'bg_club_lights.png')

# Parts that belong in the lights layer: glowing fixtures, not furniture.
LIGHT_MATS = {4, 9, 10, 11}  # neon, Disco, DiscoAura, SpotLight
LIGHT_OWNERS = ('Disco', 'Hanging_SpotLight', 'SpotLight_')

def is_light(p):
    if p['mat'] in LIGHT_MATS:
        return True
    o = p['owner'] or ''
    return any(o.startswith(s) for s in LIGHT_OWNERS)

def split_pose(model, G):
    """Pose once, then split the concatenated arrays back per part."""
    P, N, F, UV, MAT, _ = model.pose(None, 0, G=G)
    out = []
    voff = foff = 0
    for p in model.parts:
        nv = len(p['V'])
        nf = len(p['F'])
        out.append((P[voff:voff + nv], N[voff:voff + nv],
                    F[foff:foff + nf] - voff, UV[voff:voff + nv],
                    MAT[foff:foff + nf]))
        voff += nv
        foff += nf
    return out

def render_subset(model, parts, view, bounds, size, amb=0.35):
    Ps = np.vstack([p[0] for p in parts])
    Ns = np.vstack([p[1] for p in parts])
    Fs, UVs, Ms, off = [], [], [], 0
    for p in parts:
        Fs.append(p[2] + off)
        UVs.append(p[3])
        Ms.append(p[4])
        off += len(p[0])
    return raster(model, Ps, Ns, np.vstack(Fs), np.vstack(UVs),
                  np.concatenate(Ms), size, view, bounds, amb=amb)

def main():
    preview = '--preview' in sys.argv
    W, H = (480, 272) if preview else (960, 544)
    t0 = time.time()
    m = Model(FBX, TEX)
    G = m.globals({}, 0)
    parts = split_pose(m, G)
    print('parts:', len(parts), 'load+pose %.1fs' % (time.time() - t0), flush=True)

    # 3/4 view from the +z side, looking into the room (same convention
    # as the sheet bakes: largest view-Z is nearest).
    yaw = np.radians(float(os.environ.get('CLUB_YAW', '25')))
    vw = view_yaw(yaw)
    Pall = np.vstack([p[0] for p in parts])
    Nall = np.vstack([p[1] for p in parts])
    X, Y, Z, _, _, _ = vw(Pall, Nall)
    # Full room height drives the frame; width follows the canvas aspect.
    y0, y1 = -180.0, 1152.0
    bw = (y1 - y0) * W / H
    xc = (X.min() + X.max()) / 2 + float(os.environ.get('CLUB_XSHIFT', '0'))
    bounds = (xc - bw / 2, xc + bw / 2, y0, y1)
    print('view X range %.0f..%.0f  bounds' % (X.min(), X.max()), [round(b) for b in bounds], flush=True)

    light_idx = {i for i, p in enumerate(m.parts) if is_light(p)}
    far = [p for i, p in enumerate(parts) if i not in light_idx]
    lit = [p for i, p in enumerate(parts) if i in light_idx]
    print('far parts:', len(far), ' light parts:', len(lit), flush=True)

    t0 = time.time()
    # Moody club: low ambient so the white marble walls don't blow out.
    img_far = render_subset(m, far, vw, bounds, (H, W), amb=0.12)
    print('far render %.1fs' % (time.time() - t0), flush=True)
    t0 = time.time()
    img_lit = render_subset(m, lit, vw, bounds, (H, W), amb=0.35)
    print('lights render %.1fs' % (time.time() - t0), flush=True)

    # The far layer is a dim backdrop — darken it in post so the neon
    # fighters and EQ bars stay the brightest thing on screen.
    img_far[..., :3] *= float(os.environ.get('CLUB_DARKEN', '0.55'))

    for img, out in ((img_far, OUT_FAR), (img_lit, OUT_LIT)):
        im = Image.fromarray((np.clip(img, 0, 1) * 255).astype('uint8'), 'RGBA')
        if preview:
            out = out.replace('.png', '_preview.png')
        im.save(out)
        print(out, im.size, os.path.getsize(out), 'bytes', flush=True)

if __name__ == '__main__':
    main()
