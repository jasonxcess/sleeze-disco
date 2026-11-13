# Sleeze Disco — Beat Kune Do (Godot 3.5, PS Vita) — v7.6 port

2D rhythm-action beat 'em up. **Original game** — no Dead as Disco names,
art, music, or dialogue anywhere. This is a port of the web build v7.6
(`~/workspace/games/sleeze-disco-v7/sleeze-disco-master/`, all 6 phases:
feel, free-flow combat, Fever/takedowns, story lab bosses, hub/progression,
music) into a native Godot 3.5 project for the PS Vita.

Quality bar: **STYLE.md**. Short version: 960x544, neon gold/red/cyan/pink/
purple on near-black, unlit only, no dynamic shadows, real cutouts only.

Target: native PS Vita, 30–60 FPS at 960x544, GLES2. The game is **2D**
(Node2D, manual position integration — no physics bodies, matching the web
build). The v1 3D approach was dropped: its player speed scale was broken
(300 units/s on a 24-unit floor) and the web build is 2D 960x544, so a 2D
port maps 1:1 with every constant in `PORT_SPEC.md`.

## 1. Open it

1. Install **Godot 3.5.x** on PC for editing/testing (standard 3.5.3).
2. For the Vita export, use the **SonicMastr godot-vita** fork editor
   (Godot 3.5-rc5) — `~/workspace/tools/vita-templates/godot_v3.5-rc5-vita.x11.64`
   (runs under `xvfb-run -a`). Templates are installed at
   `~/.local/share/godot/templates/3.5.rc5/` (official release 3.5-rc5-vita1).
3. Open this folder as a Godot project. Main scene: `scenes/Main.tscn`.

## 2. Autoload — RhythmManager

Declared in `project.godot`:

```ini
[autoload]
RhythmManager="*res://scripts/managers/RhythmManager.gd"
```

The beat clock is the **audio clock**: beats are generated from the track
BPM against `AudioStreamPlayer.get_playback_position()`, loop-aware (60 s
loops). Judge windows: PERFECT ±65 ms (1.5x), GOOD ±130 ms (1.1x), plain
HIT 1.0x — **no MISS tier for player attacks** (inputs snap to the beat;
combo breaks only on getting hit). Parry-press MISS past 130 ms pays 0.6x.

## 3. Hardware & resolution config (already set in project.godot)

- **960x544**, Stretch Mode `2d`, Aspect `keep`
- Renderer **GLES2**
- Physics tick **60 Hz**
- Textures: POT, max 1024. Sprite sheets were split into 512x256 POT
  frames (`assets/sheets/`, 523 frames, 9.2 MB) because the source sheets
  (up to 6272x3210) can't be single textures.
- Audio: 5 pre-rendered 60 s OGG loops (`assets/audio/bgm_*.ogg`, 128k,
  kick 145 Hz sine→42 + bass sawtooth + lead square per `PORT_SPEC.md`
  §8.1) + 6 blip WAVs. **Rush audio densification (extra 16ths) is NOT in
  the loops** — visual Rush + faster attacks carry the feel.

## 4. Input mapping

Actions are registered at runtime by `Main._setup_input()` (joypad indices
follow the v1 project's comment for this fork: 0 Cross, 1 Circle, 2 Square,
3 Triangle, 4 L1, 5 R1, 6 Select, 7 Start; D-pad 12–15 standard).

| Action | Vita button | PC test key |
|---|---|---|
| `punch` | Square | J |
| `kick` | Triangle | K |
| `throw` | Circle | L |
| `dodge` | Cross | Space |
| `parry` | L1 | S |
| `finisher` | R1 | E |
| `dance` | Select | F |
| `move_*` | Left stick / D-pad | Arrows + WASD |
| `pause` | Start | P |

**No jump.** The web v7.6 build has no jump, and the STYLE.md jump-buffer/
coyote lines don't apply to this port.

## 5. How the scripts wire together

```
Main (Node2D, scripts/main/Main.gd)
 ├── World (Node2D: shake offset lives here)
 │    ├── bg_club_far / bg_club_lights (Sprites, 960x544 PNGs)
 │    ├── StageLayer (dancefloor grid + 16 EQ bars)
 │    ├── Fighters (YSort: Player + spawned Enemies)
 │    └── FXManager (ghosts, slashes, rings, particles, floats)
 ├── UI (CanvasLayer: title / mode / intro / story / end / hub / how-to / pause)
 └── HUD (CanvasLayer: HP, Fever, Style, Score, combo, beat bar, banner)

RhythmManager (autoload)
 ├── owns the music AudioStreamPlayer + the beat clock
 ├── load_track(key): beats generated from the TRACKS BPM, 60 s loop
 ├── _process(): fires beat_hit per beat boundary (catch-up loop covers hit-stop)
 └── judge_attack() / judge_parry(): judged at PRESS time, not fire time

Player (scripts/player/Player.gd) — snap-to-beat queue, gap-closer, parry
  with COUNTER, dodge/dash + ghosts + i-frames, dance, finisher, Fever +
  Rush (8 beats), tokens (1 per 12 combo), style rank D→SLEEZE.
Enemy (scripts/enemies/Enemy.gd) — chase/windup/telegraph/strike/recover,
  one-attacker-at-a-time hold, boss signatures: Rope Sweep (DR. CLIPBOARD),
  Triple Tap (SUBJECT SEVEN), Spotlight Blast (VEX, 66%/33% phases).
FXManager (scripts/fx/FXManager.gd) — Node2D _draw: particles, impact
  rings (46/70 px, beatDur), shockwave rings (parry/dodge/hit), ghosts,
  slashes, floats (Labels). Baked-circle shadows are Polygon2D children
  of each fighter.
SheetFrames (scripts/util/SheetFrames.gd) — builds SpriteFrames from the
  split PNGs at runtime; CLIP_FALLBACK for sheets that lack a clip.
```

**One frame of combat:** player presses Square → `Player._queue_attack()`
→ `RhythmManager.judge_attack()` at press time → queued swing fires on
the next `beat_hit` → `_apply_melee()` → enemy `take_hit()` → on any hit,
`_do_hitstop()` (40 ms, 80 ms PERFECT/heavy, 150 ms finisher) via
`Engine.time_scale = 0` restored by a SceneTreeTimer, while the music
keeps playing — the rhythm clock is the audio clock, so the freeze costs
nothing in timing.

**Combo:** +1 per landed hit; breaks **only** on getting hit. Score per
hit: `dmg * (1 + floor(combo/5))`, times the style-rank multiplier
(D 1.0x … SLEEZE 1.5x). KO +100, clean parry +200.

## 6. Files

```
project.godot                  960x544, stretch 2d/keep, GLES2, autoload
export_presets.cfg             PS Vita (platform "PlayStation Vita") + Linux/X11
scenes/Main.tscn               root Node2D + Main.gd (everything built in code)
scripts/managers/RhythmManager.gd   audio-clock beat manager, TRACKS table, blips
scripts/player/Player.gd            2D player: queue, gap-closer, parry, dash, Fever
scripts/enemies/Enemy.gd            2D enemies + 3 lab bosses + signatures
scripts/fx/FXManager.gd             2D FX: particles, rings, ghosts, slashes, floats
scripts/fx/StageLayer.gd            dancefloor grid + EQ bars
scripts/main/Main.gd                screens, waves, shop, saves, HUD, stage
scripts/util/SheetFrames.gd         runtime SpriteFrames from split sheets
PORT_SPEC.md                   the full v7.6 → Godot spec (source of truth)
assets/sheets/                 523 split POT frames (psxm/psxw/thug/dead)
assets/backgrounds/            bg_club_far.png, bg_club_lights.png
assets/sprites/                painted fallback sprites (not the live art)
assets/audio/                  5 x 60 s OGG loops + 6 blip WAVs
tools/render_tracks.py         renders the 5 loops from the TRACKS patterns
tools/split_sheets.py          splits the 4 sheets into POT frames
```

## 7. Saves

One JSON file, `user://sleeze_disco_save.json`: fans, shop upgrades
(hp/tokens/fever/combo/fits/fit), unlocks (dash/spinKick), high score,
calMs. No localStorage on Vita.

## 8. Export to Vita

1. Open the project in the fork editor (`xvfb-run -a
   ~/workspace/tools/vita-templates/godot_v3.5-rc5-vita.x11.64 --path .`).
2. Project > Export > PS Vita (preset name "PS Vita", platform
   "PlayStation Vita" — **not** "Vita"; the fork's platform name is
   "PlayStation Vita"). Title ID **SLEEZDSC1** (set in the export dialog).
3. Export to `~/workspace/your_files/sleeze-disco-v7.6-vita.vpk`, copy to
   the Vita, install via VitaShell.
4. Godot 3.5 CLI flag is `--export`, NOT `--export-release` (that's Godot 4;
   `--export-release` is silently ignored in 3.5).

## 9. Vita deviations from the web build (deliberate)

- **Endless keeps the track's native BPM all run** (no BPM ramp): the
  pre-rendered 60 s loops can't re-tempo without pitch artifacts. Waves
  still ramp enemy speed (speedMul, +0.05/wave to 1.5x) and wave size.
- **No MP3 import / auto-BPM** (web-only by design). Endless uses the
  preset BPM per track.
- **No Rush audio densification** in the loops (see §3).
- **Skeleton rig is CC BY-NC** ("Raised dead", Pjotr Heinkens) — the VPK
  is a free homebrew build only, never a paid release. All other CC-BY
  assets keep their credits in the in-game how-to screen.
- Joypad indices for Select (6) / Start (7) / D-pad (12–15) follow the v1
  project's fork comment and are **unverified on a real Vita** — if
  Start/Select don't respond, fix `Main._setup_input()` (standard Godot
  would be Select 10 / Start 11).

## 10. What is NOT done / not verified

- **Not tested on a real Vita.** Headless PC run + structural checks only.
  Shawn installs via VitaShell and playtests.
- BGM loops are synth rebuilds of his own tracks (no licensed recordings)
  — real stems swap is a later P6 step.
- Known carried gaps from the web build: VEX leg stretch on spin kicks;
  tap-along thumb vs label (not reproduced — cosmetic); club far wall is
  flat grey in the source PNG.
- Rush densification, MP3 import, and the endless BPM ramp are web-only
  (see §9).
