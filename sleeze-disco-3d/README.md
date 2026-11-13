# Sleeze Disco 3D: Arena v0.1.1 diagnostic (PS Vita)
Install: copy sleeze-disco-3d-arena-v0.1.vpk to ux0:data, install it with VitaShell (✕), and launch the SLZD00002 bubble. It installs alongside the 2D build (SLZD00001).
Controls: left stick moves, right stick moves the camera, □ punch, △ kick, ○ counter/parry, ✕ dash (hold to sprint), L lock-on, R finisher (uses a star), START pause. In pause, the D-pad adjusts latency and SELECT restarts.
Build: box64 + Xvfb run the godot-vita 3.5-rc5 x86_64 editor headless (/workspace/work/sd3d/setup.sh, gd.sh). tools/make_vpk.py rewrites param.sfo, because the exporter's SFO fields are wrong.
Cut for Vita: real shadows (blob shadows instead), rim light, club lighting (unshaded, baked), full render resolution (720x408 upscaled). Enemy hits use reach checks. Steps are ramps, with IK for the foot visuals.
Risks: launch black screen (GLES2/rc5), frame rate (~130k verts, ragdoll, 6 AnimationTrees), MP3 beat drift (fix with pause calibration), memory, SFO install.
Untested: song loop seam, parry path, real hardware.

## v0.1.1 diagnostic (boot-hang investigation)
Launches into a light 2D menu (D-pad + ✕): A SAFE (default), B SAFE+fog, C SAFE+glow/DOF, D FULL (= v0.1).
The arena then loads in visible stages (club, nav, fx, crowd, fighters, env, present 1-5, music); the stage name and FPS stay on screen.
Music starts only after 5 presented frames. Log: ux0:data/SLZD00002/boot.log (falls back to user://boot.log).
Desktop test: `godot --path . -- --profile=A` skips the menu (add `--bot` for the headless bot).
Build: bump with `python3 tools/make_vpk.py in.zip out.vpk --app-ver 01.01`.
Report back: which mode works, and the last stage/log line of any mode that hangs.

## v0.2 PSX pivot (APP_VER 02.00)
The v0.1.2 test booted but ran 1–5 FPS and crashed C2-12828-1. The core dump (parsed with Grarak parse_core.py) shows the crash is **inside Sony's PowerVR GLES2 driver** (libGLESv2 +0x16b402, data abort on write 0xa4 bytes past the driver's own 0x5000-byte uncached heap) — NOT in the game code. v0.2 attacks it by cutting the driver's per-frame workload: plain AnimationPlayer (no AnimationTree), no SkeletonIK, no ragdoll (KO = canned knockdown clip), 480x272 internal viewport in every profile, 30 Hz physics. Same cast, story, controls, diagnostic menu/staging/logging/boot.log/shader warm-up. Desktop bot: 900 frames DONE, 69–93 FPS llvmpipe (was 38–40), max_draws 35. Install sleeze-disco-3d-arena-v0.2.vpk (SLZD00002, 02.00), mode A first. If it crashes again, report the last stage + boot.log line + the new .psp2dmp — the fault address tells whether it moved.
