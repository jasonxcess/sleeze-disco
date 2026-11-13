# SLEEZE DISCO 3D — Arena v0.1 · Handoff for Meta Muse (Nov 13, 2026)

Owner: Shawn "Sleeze" Jackson (@sleezejason). A neon on-beat 3D brawler for the PS Vita, rebuilt in 3D from the 2D HTML game (master-v7.7) because sprites looked flat and glided. Same story and tone: Sleeze meets his "girl" Vex at the club, but it's a setup and he becomes a lab science project. He fights and dances to the beat to get out. Comedic, no slurs.

Target hardware: PS Vita PCH-2000, firmware 3.65 HENkaku Ensō, VitaShell installed.
Engine: Godot 3.5 Vita port (SonicMastr/godot-vita 3.5-rc5 export templates, PVR_PSP2 GLES2 driver bundled in the VPK's module/ folder). Renderer: GLES2.
Title ID: SLZD00002 (installs alongside the 2D lpp-vita build SLZD00001).

## BLOCKER #1 (fix this first): stuck on the boot splash on real hardware
What Shawn saw on his Vita: after installing sleeze-disco-3d-arena-v0.1.vpk and launching it, the Godot boot splash stays on screen for 1+ minute while the SLEEZETROIT music plays. The game never shows.

What that tells us:
- The music only starts from `Beat.start()`, called at the END of `Arena._ready()` (scripts/Arena.gd). That `_ready` first yields on two `physics_frame`s. So the main loop is running, the scene and scripts loaded, and frames are iterating, but nothing new is ever presented to the screen (or each frame is so slow it looks frozen).
- Suspects, most likely first:
  1. `display/window/stretch/mode="viewport"` with a 720x408 base, upscaled to 960x544. This renders into an offscreen FBO and blits it, which may fail on PVR_PSP2 GLES2.
  2. Environment post-FX: glow (levels 2–3, additive), far DOF (low quality), depth fog. These need extra FBOs or a depth texture.
  3. A huge first-frame cost: shader compiles, ~130k vertices, uncompressed textures (several .material files are ~788 KB), 6 AnimationTrees, Bullet ragdoll.
- It ran clean on desktop (headless bot tests, 4,000 frames, zero errors), so the problem is specific to the device.

Plan Shawn wants (diagnostic v0.1.1, same Title ID, APP_VER 01.01):
- A new light 2D Boot scene as main_scene that draws immediately, with a D-pad + ✕ mode menu:
  A) SAFE: native 960x544, no viewport stretch, no glow/DOF/fog, no crowd, 2 thugs (default)
  B) SAFE + fog
  C) SAFE + glow/DOF
  D) FULL (the original v0.1 settings)
- Start the music only after the arena has presented several frames (`VisualServer` `frame_post_draw`).
- Load the arena in visible stages (club, nav, fx, crowd, fighters, env) with the stage name on screen, so a hang shows where it stopped.
- An always-on FPS + stage overlay, and a line-flushed boot log (try `ux0:data/SLZD00002/boot.log`, fall back to `user://`).
- Optional: a shader warm-up behind the loading screen.
- godot-vita releases mention a logging plugin for reading errors on device. Worth using.

## v0.1.1 DIAGNOSTIC RESULT (Shawn's real Vita, Nov 13 01:17) — all 4 modes 1 FPS at "fighters", never boots
Mode A (no FX, no crowd, 2 thugs) fails identically to D, so the bottleneck is the FIGHTERS, not FX or crowd. FPS 1 (not 0) = main loop runs, ~1 s/frame.

## v0.1.2 — fighter/perf fix (Nov 13, APP_VER 01.02, same Title ID SLZD00002)
### The real boot.log (Shawn photographed it, VitaShell 2.02 — fell back to user://boot.log, `ux0:data/godot/app_userdata/SLEEZE DISCO 3D/boot.log`; the primary `ux0:data/SLZD00002/boot.log` path did not work). Profile A stage timings:
- start→club 72 ms · club→nav 1,731 ms · nav→fx 2,870 ms · fx→fighters 1,008 ms · **fighters→env 20,071 ms** · **env→present 1/5 166,656 ms** · present 1/5 is the LAST line (no 2/5–5/5, no music). Total ~197.7 s, never booted.
- REFINED diagnosis: fighters stage is slow (20 s) BUT env is ~8x slower (167 s), and the present loop stalls after the first presented frame. The "env" yield is the first frame WITH a camera (no camera existed before fighters stage), so NOTHING 3D had ever been drawn — every shader variant in the whole scene compiled at once on that one frame, on the PVR driver. The present 1/5 frame then had to compile the LIT variants (the lights were added just before it). The fighters stage (20 s) is the player .scn load + setup (24,768 animation keys to deserialize on a 444 MHz CPU).
### Measured before the fix (desktop bot, fork editor + Xvfb; desktop does NOT reproduce Vita FPS — correctness + relative timings only)
- Tris: player 645, thug 3,199, vex 894, crowd 898, club 15,165 (imported .scn; raw GLB said 20,578 — importer welds). Whole scene ~28k tris. Geometry is NOT the problem; no decimation needed (already ~2k or less per fighter).
- Animation keys in imported .scn: player 24,768 / thug 17,639 / vex 17,689 / crowd 3,667. Load on desktop: player 9 ms, thug 18 ms, vex 7 ms, club 23 ms.
- Per-frame logic on desktop: player _physics_process 255 µs, enemy 94 µs, Anim.update 6 µs, update_loco 20 µs, foot-IK 73 µs, Arena._process 64 µs — ~700 µs/frame total. Even at 20x Vita slowdown that's ~14 ms (70 FPS). Logic / AnimationTree / IK are NOT the 1 FPS cause. Ragdoll already only on KO, one at a time. SkeletonIK already gated off on flat floor.
- Runtime textures are already small (.stex 1–45 KB); the ~788 KB .material files are editor-side only and don't ship at that size.
- Source .material files have NO emission (all emiss=False) — the character glow was added at runtime by prep_character_materials + _tick_tint, plus Environment glow post-FX bloom.
### What changed in v0.1.2
1. **All materials unshaded + no scene lights** (the root fix for the 167 s frame): fighters, crowd and the riser "dark" material were vertex-lit; now `flags_unshaded = true`. The DirectionalLight + OmniLight (key_light) are removed from _build_environment — with everything unshaded they lit nothing visible, but their presence forced the lit shader variant to compile on the present 1/5 frame. Beat pulse now comes only from pulse_mats / floor_mat albedo (same look, no light cost). Spotlight distance fade removed (its own shader variant; LOD near-hide already covers it).
2. **Shader warm-up is now real**: a plain warm-up Camera is created right after _build_club, so the club's shaders compile on the nav stage's frame instead of piling up on the first 3D frame. Fighters use the same unshaded variants the club already compiled, so env / present frames compile nothing new. (Warm-up alone would only move the cost — the variant cut is what shrinks it.)
3. **Glow around the characters — GONE**: glow post-FX OFF in all profiles (C and D had it on; A/B already off) and emission zeroed on all character materials (prep_character_materials + _build_crowd: emission_enabled=false, energy 0). Telegraph red pulse and hit white flash moved from emission to albedo_color in Enemy._tick_tint (unshaded shows albedo directly, so the cue reads the same with no halo). Identity tint is a mild albedo tint now. Note: mode A already ran with no FX and still failed, so this is a look + perf win, NOT the root fix — the unshaded/lights/warm-up work above is the root fix.
4. **Simplified club (same asset, no replacement)**: Night Dance Club Lowpoly (00amza, CC BY 4.0) stays — the search found the ideal replacement (Sketchfab "Nightclub" by MozillaHubs, 2.5k tris, CC-BY) but Sketchfab downloads need a login, so it can't be fetched from here; flagged for a later round if Shawn wants it. Instead the existing club is stripped at load in _build_club: props_* + small_* meshes freed → 15,165 → ~6,161 tris, 39 → ~14 meshes, 75 → ~30 prims (shell + disco ball + spotlights kept — the whole look). Collision hull (club-colonly) and navmesh untouched, so old prop spots still read as blocked at the room edges; the dance floor was always clear. No new asset, no CREDITS change needed.
5. **Fewer animation keys** (fighters-stage load): optimizer loosened in the 4 fighter .glb.import files (max_linear_error 0.05→0.1, max_angular_error 0.005→0.02) and re-imported. Keys: player 24,768→21,264 (−14%), thug 17,639→15,092 (−14%), vex 17,689→15,024 (−15%), crowd 3,667→3,340 (−9%). Modest win; the load is dominated by fixed costs, so this is not the main fix.
6. NOT changed: gameplay, controls, story, diagnostic menu / staging / logging, physics (stays 60 Hz — logic is fast enough), AnimationTree structure, IK gating, ragdoll-on-KO-only. Decimation skipped (measured: already ~2k tris or less per fighter). 30 Hz physics stays a fallback.
### v0.1.2 desktop verification (fork editor + Xvfb, --profile=A --bot --frames=900 --shots)
- Import: zero new errors (one benign ERR_CANT_OPEN that appears in every run). Bot DONE: 900 frames, score 393, max_combo 8, 3 KOs, 4 counters, 2 ragdolls, hp 100.
- Stage timings (desktop): start→club 3 ms, club→nav 104 ms, nav→fx 212 ms, fx→fighters 87 ms, fighters→env 63 ms, env→present 1/5 187 ms, present frames 20/14/61/14 ms, music→ready 25 ms, total boot ~1.5 s. The nav/fx stages are SLOWER than v0.1.1 (32/24 ms) — that is the warm-up working: the warm-up camera renders the club from the nav stage, so the club shaders compile there (during loading) instead of on the first presented frame. Present loop completes all 5 frames, music starts, "Arena ready".
- Draws/verts (desktop, llvmpipe): max_draws 43 (was 76, −43%), max_verts 48,045 (was 96,921, −50%), mem 34.5 MB (was 35.5). Desktop FPS 38–40 (was 23–28) — llvmpipe only, NOT Vita FPS.
- Screenshots (user://shots/shot_00401.png, shot_00701.png): club renders (checkered dance floor, stage + neon steps, DJ screens, disco ball, spotlight beams). Fighters have NO halo/bloom — flat unshaded, albedo tints read (red charger, gold player). Telegraph red + hit white still read via albedo.
- DELIVERABLE: `~/workspace/your_files/sleeze-disco-3d-arena-v0.1.2.vpk` — 33,096,959 bytes, md5 2d942cb4c6145b29c019288130e12040. Parsed param.sfo: TITLE "SLEEZE DISCO 3D", TITLE_ID SLZD00002, APP_VER 01.02, CATEGORY gd. unzip -t clean. game.pck 13,316,640 B (was 13,750,240 — the 434 KB drop matches the re-imported .scn key cut exactly). pck contains the new code (string "glow removed v0.1.2" present 2x, old "SAFE + GLOW" label gone). v0.1.1 VPK and the uploaded source .vpk untouched (md5s verified).
- Honest caveat: desktop cannot prove the Vita boots. What changed measurably is the shader-variant set (lit + distance-fade variants gone), the warm-up spread, the club draw/tri cut and the key cut. The Vita test decides.
### What Shawn should test
- Install sleeze-disco-3d-arena-v0.1.2.vpk (SLZD00002, APP_VER 01.02) in VitaShell. Mode A first, then B / C / D.
- Report: which mode, whether it boots, the FPS once in the fight, and if it still hangs, the last stage on screen + the last line of `ux0:data/godot/app_userdata/SLEEZE DISCO 3D/boot.log`.
- Honest caveat: desktop bot FPS is NOT Vita FPS. What was measured is the shader-variant count cut (lit variant gone, distance-fade variant gone), the warm-up spread, the club tri/draw cut and the key cut. Whether the Vita boots is decided on the device.

## v0.2 PSX pivot (Nov 13, APP_VER 02.00, same Title ID SLZD00002)
### v0.1.2 device test (Shawn, Nov 13 08:51, mode A)
IT BOOTED — the v0.1.1 boot hang is fixed (shader warm-up worked). Fight running (HUD: SLEEZE, FEVER, RANK D, SLEEZETROIT 100 BPM, arena visible) but at **1–5 FPS**, overlay reads **26 draws · 18k verts** — the GPU is doing almost nothing, so the bottleneck is per-frame CPU/driver cost, not draws or verts. Then **CRASHED: C2-12828-1**, core dump at `ux0:data/psp2core-1794588481-0x0000629ad-eboot.bin.psp2dmp` (Shawn sent the dump).
### Crash dump analysis (parsed with Grarak parse_core.py) — the crash is NOT in the game code
- Faulting thread: the **main thread** (SLZD00002), STOPPED: data abort on write. PC 0x89a6b402 = **libGLESv2 + 0x16b402**; LR also inside libGLESv2. The crash happened **inside Sony's PowerVR GLES2 driver**, during a draw call from Godot's GLES2 rasterizer (stack shows eboot return addresses calling into libGLESv2). The eboot is stripped ("vita_release_stripped"), so the exact GL call / Godot function can't be named — honest limit.
- Fault address **0x704950a4**: the driver was writing to its own uncached heap. The OGLES2UNCHeap block at 0x70490000 is 0x5000 bytes, so it ends at 0x70495000 — the write landed **0xa4 bytes past the end of the driver's own buffer**. Registers r0/r5/r6/r7 all point into the 0x7049xxxx uncached region. Driver-side buffer overrun / use of a freed or undersized uncached buffer, inside the GPU driver, while drawing. The other threads (DCSwapChainThread, OGLES2UltRuntime, OGLES2AsyncTexOpCl) were all idle/waiting — the GPU pipeline wasn't stuck; the main thread died in the driver.
- What this means: the AnimationTree / IK / ragdoll removal does **NOT** directly fix this crash — it is a driver fault, not a game-code crash. The old leading candidate (runtime PhysicalBone bind on KO) is superseded by the dump: the fault is in libGLESv2's heap, not in Bullet. The pivot still helps, but for a different reason: it cuts the driver's per-frame workload (fewer draws, fewer state changes, lower res, less buffer churn), which is what trips this fault.
### What changed in v0.2 (PSX pipeline — the pipeline, not the models)
1. **AnimationTree dropped** → plain AnimationPlayer per fighter (scripts/Anim.gd rewritten, same public API: setup / clip_len / update_loco / play / stop / playing / update, phase / act_time / act_name kept). One baked clip at a time; locomotion is a single ladder clip with playback speed = ground speed / natural speed (stride matching without a tree); stride phase kept across clip switches via seek. Actions play on the same player with a small blend, locomotion resumes on end.
2. **SkeletonIK removed entirely** (Player.gd `_make_ik` / `_foot_ik` / `_ik` / `_ik_targets` / `_hip_drop` gone; Bot.gd `_iktest` gone with it). Feet plant via the baked walk/run cycle. The stage ramps stay — they're collision, the capsule walks up them; a foot may clip a step slightly, PSX-style.
3. **Ragdoll (Bullet) removed** (scripts/Ragdoll.gd deleted; Enemy.gd RAG_DEFS / `ragdolled` / `claim_ragdoll` / `physical_bones_start_simulation` gone; Arena.gd ragdoll slot gone; `L_RAGDOLL` const + physics layer 6 name removed). KO = canned knockdown clip for every KO (finisher gets a bigger push, 4.0 vs 2.5). Hurtbox stays attached — no more BoneAttachment removal dance.
4. **v0.1.2 wins kept**: all materials unshaded, no scene lights, no glow post-FX, no emission on characters, shader warm-up camera, stripped club (15,165→~6,161 tris).
5. **Internal resolution 480x272** (was 720x408 only in profile D; now ALL profiles: `set_screen_stretch(STRETCH_MODE_VIEWPORT, KEEP, Vector2(480, 272))` in G.apply_profile — integer 2x up to the 960x544 screen). Screenshots confirm 480x272 viewport.
6. **30 Hz physics** (`physics/common/physics_ticks_per_second=30` in project.godot).
7. **Models unchanged** — same PSX cast (PSXprop Male 02, PSX Low Poly Woman, thug, crowd, club). No new art.
8. **Sprite-billboard fighters evaluated, NOT built**: desktop timings after the pivot (bot FPS 69–93 on llvmpipe vs 38–40 in v0.1.2; max_draws 35 vs 43; max_verts 44,547 vs 48,045) show skeletal animation is not the measured bottleneck on desktop, and per-frame script cost was already ~700 µs in v0.1.2. Billboarding stays a fallback lever if the Vita still crawls (it would remove ~11 skeleton evaluations/frame) — it was not forced by the measurements. Note the honest limit: desktop cannot reproduce the Vita driver fault, so the device decides.
- Driver-work audit (against the dump): warm-up camera + staged load + boot.log + diagnostic menu all kept; **zero per-frame texture uploads** in scripts (no set_data/ImageTexture); per-frame dynamic buffers are only the HUD canvas redraw (one batched vertex buffer per frame, live by design — at Vita's 1–5 FPS that's 1–5 rebuilds/s) and CPUParticle rebuilds on hit sparks/dust (small, transient). Nothing else avoidable was found to cut without breaking the game. pck grep: "PSX v0.2" 4×, "480x272" 4×, Ragdoll / SkeletonIK / AnimationTree / physical_bones all 0.
### v0.2 desktop verification (fork editor + Xvfb, --profile=A --bot --frames=900 --shots)
- Import: zero new errors (one benign ALSA ERR_CANT_OPEN, same as every run). Bot **DONE**: 900 frames, score 409, max_combo 8, perfects 1, kos 3, counters 6, hits 8, ragdolls 0, hp 100. Boot ~1.0 s (env→present 1/5: 28 ms, was 187 ms in v0.1.2), all 5 present stages logged, music started, "Arena ready".
- **FPS 69–93 on llvmpipe (was 38–40)** — llvmpipe only, NOT Vita FPS. max_draws 35 (was 43), max_verts 44,547 (was 48,045), mem 34.4 MB. Screenshots (480x272): club renders, fighters have no halo, K.O. COUNTER popup + 8 COMBO read.
- DELIVERABLE: `~/workspace/your_files/sleeze-disco-3d-arena-v0.2.vpk` — 33,085,534 bytes, md5 c2b6afe6aa1b8ab6f5f42f015af99a92. Parsed param.sfo: TITLE "SLEEZE DISCO 3D", TITLE_ID SLZD00002, APP_VER 02.00, CATEGORY gd. unzip -t clean. game.pck 13,305,216 B. v0.1.1 / v0.1.2 VPKs and the uploaded source .vpk untouched (md5s re-verified).
- Honest caveat: desktop FPS is NOT Vita FPS. v0.2 attacks the driver fault by reducing driver work (fewer draws, fewer state changes, 480x272, 30 Hz physics, no tree/IK/ragdoll, unshaded + warm-up). Whether that's enough is decided on the device. If it still crashes identically, the next dump tells us whether the fault address moved — and the next lever is deeper driver-work cuts (the Sketchfab MozillaHubs "Nightclub" 2.5k-tris swap is still open).
### What Shawn should test
- Install sleeze-disco-3d-arena-v0.2.vpk (SLZD00002, APP_VER 02.00) in VitaShell. **Mode A first**, then B / C / D.
- Report: which mode, whether it boots, the FPS once in the fight, and if it crashes, the last stage + the last line of `ux0:data/godot/app_userdata/SLEEZE DISCO 3D/boot.log` + the new .psp2dmp if there is one.

## Files
- `project.godot`: GLES2, fallback on, ETC/ETC2 import, vertex shading forced, 30 Hz physics (v0.2), autoloads `G` (scripts/G.gd) and `Beat` (scripts/Beat.gd).
- `scenes/Main.tscn` → `scripts/Arena.gd`: builds everything in code: environment, club (assets/models/club.glb, unshaded light-baked), stage riser/steps (invisible ramps + IK feet), navmesh (data/arena_nav.tres, baked offline by tools/bake_nav.gd), fx, crowd, player, camera, HUD, waves.
- `scripts/`: Player.gd (KinematicBody: idle/walk/run/sprint, dash burst, SkeletonIK feet, bone-attached hitboxes), Enemy.gd (Bouncer, Rusher, Heavy, Vex; telegraph ring + counter window, directional flinch, ragdoll on KO only), Anim.gd, CameraRig.gd (SpringArm chase cam, L lock-on), HUD.gd, Ragdoll.gd, Beat.gd (beat clock on audio playback position, wall-clock fallback, pause calibration), Bot.gd (headless test bot, `--bot`), G.gd.
- `assets/models/`: player.glb (Sleeze, PSXprop Male 02), thug.glb, vex.glb (PSX Low Poly Woman), crowd.glb, club.glb (Night Dance Club Lowpoly), plus extracted .material files.
- `assets/music/sleezetroit.mp3`: Shawn's own song (100 BPM, first beat 0.296 s). His other 25 songs live in master-v7.7/music (not included here).
- `data/clipmeta.json`: Mixamo clip metadata. The tools/*.py scripts built the GLBs from FBX/.blend in a sandbox without Blender.
- `tools/make_vpk.py`: IMPORTANT. The godot-vita exporter writes wrong SFO fields (TITLE_ID came out as the title). This script repacks Godot's eboot, modules, pck and LiveArea and writes a correct param.sfo. If you export from the Godot editor on a normal PC, check param.sfo or run this.
- `sce_sys/`: icon0 + LiveArea (bg, startup, template.xml).
- `CREDITS.md`, `licenses/`: asset credits (must ship in-game). `README.md`: install + controls.
- `sleeze-disco-3d-arena-v0.1.vpk`: the build that hangs on the splash (reference only).

## Controls
Left stick move · right stick camera · □ punch (every 3rd = uppercut) · △ kick · ○ counter/parry in the telegraph window · ✕ dash (hold = sprint) · L lock-on · R finisher (costs a star) · START pause (D-pad = latency, SELECT = restart). Judging: PERFECT ±65 ms, GOOD ±130 ms.

## What Shawn wants from the 3D version (his v0.1 2D-port playtest)
Keep: the hit reactions (he likes them).
Fix: no gliding (real foot-planted locomotion), a dash that reads as a sprint, punches that visibly connect, no warped Vex, no jitter, a fully rendered club background, and no paper-flat look. Feel reference: Dead as Disco (a wide camera, free-flow snap targeting, beat telegraphs, the club pulsing to the beat). Systems only. Copy no names, characters or story.

## Cut or faked for Vita (v0.1)
Blob shadows instead of real ones, emission tint instead of rim light or outlines, unshaded club, 720x408 internal resolution, enemy strikes use reach checks, steps are ramps, approximate stride matching. The parry path has never been exercised. The song loop seam is untested.

## After the boot fix
1. Device performance pass (targets: 30 fps or better; fallbacks: fewer thugs, 30 Hz physics, decimated thugs ~2k tris, compressed textures).
2. Port chapters, the Green Room hub/shop, bosses (Dr. Clipboard, Subject Seven, Vex) and the 26-song SONGS table (BPM + first-beat offset) from master-v7.7.
3. Release blockers: the Raised Dead skeleton (CC BY-NC) must never ship in a paid release (it isn't in the 3D build's model list, so double-check). Confirm the Sketchfab Free Standard license for the Sleeze model. Keep CREDITS in-game.

## Rules
Keep Shawn's original art and the PSX low-poly look; no generic AI-looking art. Honest, short feedback ranked by impact. Never overwrite a shipped build; bump versions (v0.1.1, v0.2...).
