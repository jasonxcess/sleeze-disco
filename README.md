# Sleeze Disco — Beat Kune Do (PS Vita)

Original rhythm beat-'em-up for the PS Vita, inspired by (not a port of) Dead as Disco.
Built by the artist's AI manager (dawgy) with the artist (Shawn Jackson / Jason /
SleezeTeamJason). Target hardware: PS Vita PCH-2000, firmware 3.65, HENkaku Enso.
Engine: Godot 3.5 (SonicMastr godot-vita 3.5-rc5, GLES2).
Title IDs: 3D build `SLZD00002`, 2D build `SLZD00001`.

This repo is the full handoff: every build, the design doc, the crash dump, and the
problem brief. Start here, then read the question list at the bottom.

## Layout

- `godot3/` — the 2D Godot 3.5 codebase (Nov 12, validated headless, zero errors):
  scripts/ (RhythmManager, PlayerController, FXManager, Enemy, Main), scenes/,
  data/ (beatmaps), project.godot, export_presets.cfg, PORT_SPEC.md, STYLE.md,
  sprite PNGs + backgrounds + BGM loops. The `assets/sheets/` split frames are
  NOT committed — they are derived; regenerate with
  `python3 sleeze-disco-2d/tools/split_sheets.py`.
- `src/` — the original V1 C/VitaSDK modules (rhythm, player, fx).
  V1 was rejected by the artist ("looked retro") — kept for reference only.
- `web/` — the working 2D HTML5 prototypes (v2 reskin + touch variant).
- `sleeze-disco-master/` — the final web game (v7.6, all 6 phases): index.html,
  tools/ (Mixamo bake pipeline), assets/ (5 PSX sprite sheets + 5 sprites +
  club backdrops), map/ (Night Dance Club Lowpoly FBX + textures),
  HANDOFF.md, ROADMAP.md, playtest-notes.md.
- `sleeze-disco-3d/` — the 3D Godot source, v0.2 state: scripts/ (Arena, Player,
  Enemy, Beat, Anim, CameraRig, Diag, Bot), scenes/, tools/make_vpk.py, data/,
  assets/models/*.glb, assets/music/sleezetroit.mp3 (artist's own song, 100 BPM),
  project.godot, HANDOFF.md, README.md, CREDITS.md.
- `sleeze-disco-2d/` — the 2D Vita build source, v1: scripts/, scenes/, tools/
  (split_sheets.py, make_bgm.py, render_tracks.py), assets/ (audio, backgrounds,
  fonts, sprites), project.godot, export_presets.cfg.
- `docs/sleeze-disco-design-document.pdf` — the 14-page design doc (Nov 12).
- `dumps/psp2core-1794588481-0x00000629ad-eboot.bin_7_ko27.psp2dmp` — crash
  dump #1 (v0.1.2, mode A). Gzip-compressed ELF core. A second dump exists for
  v0.2 mode A (psp2core-1794590754-0x00007727db) — not yet copied off the Vita.

Built VPKs are NOT in this repo (binaries — the artist has them). Godot
`.import/` caches are not committed; they regenerate on import.

## The game

Beat Kune Do rhythm combat: PERFECT ±65ms / GOOD ±130ms (3D build windows),
Square punch, Triangle kick, Circle drumstick throw, Cross dodge, L counter/parry,
R finisher. Enemies Stan / Charger / Bruiser (stuns after 4 PERFECTs) / VEX boss
(3 phases at 66%/33% HP). Story: the club is a lab, the bouncers are scientists,
the skeletons are earlier dates; the protagonist fights/dances to the beat to get out.
Chapters: Neon Alley 100 BPM, Dive Bar 120 BPM, VEX 140 BPM. PSX low-poly cast
(PSXprop Male Character 02, PSX Low Poly Woman, thug, crowd), unshaded flat materials,
palette gold/red/cyan/pink/purple on near-black. 2D build controls: □ punch,
△ kick, ○ throw, ✕ dodge, L parry, R finisher, Select dance, Start pause.

## The problem — timeline

- v0.1 (Nov 13): hung on the Godot boot splash 1+ min while music played.
- v0.1.1 (diagnostic): staged load (club/nav/fx/fighters/env/present 1–5) + boot.log.
  On-device result, profile A (SAFE): fighters stage 20s, env stage 167s, then
  "present 1/5" is the last log line — never booted. All modes A/B/C/D identical.
- v0.1.2: measured root cause — the whole scene is only ~28k tris (player 645,
  thug 3,199, vex 894, crowd 898, club 15,165), so geometry was NOT the problem.
  The 167s stall was shader compilation: no camera existed before the fighters
  stage, so every shader variant compiled at once on the first frame with a camera,
  plus lit variants. Fix: all materials unshaded + lights removed, real shader
  warm-up camera after _build_club, glow post-FX off + emission zeroed, club
  stripped at load (15,165 -> ~6,161 tris), animation keys cut ~14%.
  On-device result, mode A: IT BOOTED. Fight running (HUD, RANK D, SLEEZETROIT
  100 BPM) but 1–5 FPS, overlay "26 draws · 18k verts", then CRASHED C2-12828-1.
- v0.2 (PSX pivot): AnimationTree -> plain AnimationPlayer, SkeletonIK removed,
  ragdoll (Bullet) removed (canned KO fall), internal res 480x272 all profiles,
  30 Hz physics. Desktop bot: 900 frames DONE, boot ~1.0s, FPS 69–93 on llvmpipe,
  draws 35 (was 43), verts 44,547 (was 48,045).
  On-device result, mode D (FULL): stuck/slow at "LOADING: env", 1 FPS, 32 draws,
  17k verts — no crash, same env-stage choke. Mode A: BOOTED, got into the fight,
  2 FPS, 30 draws, 18k verts, then CRASHED C2-12828-1 again. New dump exists.
  Verdict: the PSX pivot did NOT fix the driver crash or the FPS.
- 2D v1 (Nov 13, SLZD00001, APP_VER 01.00, 29,854,698 bytes): built from the
  Nov 12 godot3 2D codebase, which already contained all six web phases — shipped
  whole (Fever, hub/shop, endless, 3 chapters, bosses, story exchange). 2D only:
  523 pre-rendered sprite frames, flat unshaded, manual position + reach checks,
  no physics bodies, no 3D. Music = 5 synth BGM loops (sleezetroit.mp3 NOT wired
  in — needs re-wiring for v1.1). Smoke: headless 40s chapter-1 fight WON,
  score 0→1012, zero script errors; editor run score 906, screenshots confirm
  PSX sprites + neon club + legible HUD. Desktop FPS is NOT Vita FPS — untested
  on real hardware at time of writing.
- 2D v1 INSTALL BLOCKER (Nov 13, VitaShell 2.02): installing sleeze-disco-2d-v1.vpk
  from ux0:data/ fails with "Error 0x8010113D". The VPK verifies clean on the
  build machine (param.sfo SLZD00001/01.00/gd, zip integrity OK, LiveArea images
  correct dimensions 840x500 / 280x158 / 128x128, file size on the Vita matches
  28.47 MB = 29,854,698 bytes). The 3D VPKs (same pipeline, same template eboot)
  installed fine. Suspected: corrupt transfer copy or a stale install state —
  fix attempted: re-copy the VPK, delete any existing SLEEZE DISCO 2D bubble,
  retry. If it persists, the VPK needs repacking/rebuilding.

## Crash dump #1 — parsed (Grarak parse_core.py)

- Faulting thread: main thread SLZD00002, STOPPED: data abort on write.
- PC 0x89a6b402 = libGLESv2 + 0x16b402; LR 0x89a6d2af also inside libGLESv2.
  The crash is INSIDE Sony's PowerVR GLES2 driver, during a draw call from
  Godot's GLES2 rasterizer — not in game code, not in ragdoll/IK/AnimationTree.
- Fault address 0x704950a4: the driver was writing to its own uncached heap.
  The OGLES2UNCHeap block at 0x70490000 is 0x5000 bytes (ends 0x70495000) —
  the write landed 0xa4 bytes PAST the end of the driver's own buffer.
  Registers r0/r5/r6/r7 all point into the 0x7049xxxx uncached region.
- Other threads (DCSwapChainThread, OGLES2UltRuntime, OGLES2AsyncTexOpCl)
  were all idle/waiting. The eboot is stripped ("vita_release_stripped"), so
  the exact GL call / Godot function can't be named from the dump.
- The eboot.bin is byte-identical across v0.1.1/v0.1.2/v0.2 and the 2D v1
  (md5 3333846b67ff62c18a9bb1349884e929) — every build ships the same prebuilt
  godot-vita release template (Jul 2022); only game.pck changes. So if the 2D
  build crashes the same way, it points at the shared engine/driver path.

## Asset licenses (credits must ship in-game)

Vex = PSX Graphics Low Poly Woman, murilo.kleine, CC BY 4.0; Sleeze =
PSXprop Male Character 02, WardsterSAW, Sketchfab Free Standard; thug =
bumstrum, CC BY 4.0; skeleton = Raised dead, Pjotr Heinkens, CC BY-NC —
NOT OK for a paid release, replace before selling; motion = Adobe Mixamo;
map = Night Dance Club Lowpoly by 00amza, CC BY 4.0.

## The questions

1. Why does the Vita run at 1–2 FPS with only ~30 draw calls and ~18k vertices,
   when the same build runs 69–93 FPS on desktop (llvmpipe)? What is the
   per-frame cost on the Vita if it isn't draws or verts?
2. Why does libGLESv2 fault writing past its own uncached heap (0x704950a4,
   0xa4 past the OGLES2UNCHeap block)? Is this a known godot-vita / PVR driver
   issue, and what call pattern triggers it?
3. What would you change — in the engine, the renderer, the driver work per
   frame, or the build flags — to get this game booting and running at 30 FPS
   on the Vita? If Godot's GLES2 path on Vita is the problem, what is the
   most practical alternative (2D Godot sprites, lpp-vita, native VitaSDK/GXM)?
4. Is there a way to get a symbolic (unstripped) godot-vita eboot without
   rebuilding the whole engine from source? (Checked: the 3.5-rc5-vita1 release
   ships only the one stripped template.)
5. What is VitaShell error 0x8010113D on VPK install, given the VPK verifies
   clean (SFO, zip integrity, LiveArea dimensions) and the same pipeline's
   VPKs installed fine? What is the most likely cause and fix?
