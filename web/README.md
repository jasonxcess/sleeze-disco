# SLEEZE DISCO — Beat Kune Do (PS Vita web prototype)

Original rhythm brawler inspired by the *Dead as Disco* formula. No Dead as Disco
assets, music, or character names are used. All audio is WebAudio-synthesized
(oscillators only, no audio files). Stage backgrounds are the art in `assets/`
(see below); fighters are the real sprite cutouts from `../data/` (copied into
`assets/`), drawn with a neon backlight glow. The title screen uses a
hand-written inline SVG vector silhouette of Jay — no photographic hero art.

## Open it

Double-click `index.html` — it references `./assets/` files relatively, so keep
`index.html` and the `assets/` folder together. No external dependencies, no
server needed, no network calls.

## Art (v2 reskin, Nov 12)

| File | Size | Used for |
|---|---|---|
| `assets/bg_alley.jpg` | 151 KB, 960×544 | Story Ch.1 Neon Alley, title screen, Infinite (wave 1, 4, 7…) |
| `assets/bg_bar.jpg` | 105 KB, 960×544 | Story Ch.2 Dive Bar, My Music, mode/BPM screens |
| `assets/bg_boss.jpg` | 144 KB, 960×544 | Story Ch.3 Idol VEX boss, Infinite (wave 3, 6, 9…) |
| `assets/player_sprite.png` | 256×517 | Jay Sleeze, gold glow |
| `assets/stan_sprite.png` | 256×517 | Stan, grey glow |
| `assets/charger_sprite.png` | 256×517 | Charger, red glow |
| `assets/bruiser_sprite.png` | 320×505 | Bruiser, purple glow |
| `assets/vex_sprite.png` | 320×562 | Idol VEX, pink glow + crown |

Sources: `../assets_raw/` (originals ~2.3–3.4 MB, center-cropped to 16:9,
resized to 960×544 with PIL LANCZOS). The page loads the JPEG q85 versions
(`bg_*.jpg`, 105–151 KB); the photographic PNGs ship alongside as alternates
(553–696 KB). Sprite cutouts come from `../data/*_sprite.png` (the same files
the Godot build uses). The old `hero.png` / `hero.jpg` portrait was removed
Nov 12 — the title art is now an inline SVG silhouette in `index.html`.

Fighters (real sprite PNGs + neon backlight): Jay in the black leather jacket
with red lining, white tee, gold chain + drumsticks; Stan grey hoodie; Charger
red jacket + mohawk; Bruiser big purple; VEX gold/purple with crown + mic.
Idle bob is synced to the beat; punch / kick lunge, dodge lean + ghost,
hurt shake + red flash, white hit flash, stun stars, damage numbers, spark
particles, beat-pulse ring on the floor, screen shake. Bunched enemies get
staggered HP-bar lanes (front one keeps its name); Jay's name rides under
his feet so it never shares a line with enemy names.

## Layout (Nov 12 redesign)

Page flow: masthead → 960×544 stage → controls bar → instructions. The stage
locks to the 960×544 aspect ratio and scales to the screen width. In-canvas
HUD safe zones: top HUD (HP/meter/score) y 0–80, stage label + boss bar
y 84–139, banner pill y 146–182, playfield y 180–470, beat strip y 492–544.
On narrow screens (≤640px) menu screens scroll inside the stage, the vector
title art hides, and the title's story blurb hides (it is in the instructions
below) so tag + title + both buttons fit the stage with no scroll. No external
URLs, no web fonts.

## How to play

| Key | Vita button | Action |
|-----|-------------|--------|
| ← → ↑ ↓ | D-pad | Move |
| J | Square | Punch |
| K | Triangle | Kick |
| L | Circle | Drumstick throw (ranged) |
| Space | X | Dodge (i-frames) |
| S | L-trigger | Counter / Parry |
| E | R + Square | Takedown finisher (meter full) |
| P / Esc | — | Pause |

**Timing:** PERFECT ±60ms = +50% damage · GOOD ±120ms = +10% · off-beat hits are
NOT penalized. Watch the beat pulse bar at the bottom — it flashes gold in the
Perfect window.

## Modes

- **Story** — Ch.1 Neon Alley (100 BPM), Ch.2 Dive Bar (120 BPM), Ch.3 Idol VEX boss (140 BPM, 3 phases)
- **Infinite Disco** — endless waves, score attack
- **My Music** — pick 90 / 110 / 130 / 150 BPM and fight to a synthesized metronome track

On the real Vita build, custom songs load from `ux0:data/sleeze-disco/music/`.

## Enemies

- **Stan** — basic, walks in
- **Charger** — flashes red, then charges; dodge it
- **Bruiser** — tank; 4 Perfect hits stun him
- **Idol VEX (boss)** — 3 phases, telegraphed Beat Wave projectiles + Spotlight Spin AoE (dodge out)

## Progression

Takedown meter builds on hits — press E at 100% for a finisher. Beat VEX to unlock
the **Perfect Strikes** skill. High score + Fans save in the browser (localStorage).

## Known gaps (web prototype only — NOT Vita-tested)

- Web prototype only; no Vita build, install, or on-device test has been done.
- No real songs in My Music — synthesized metronome track only (Vita build loads files from `ux0:data`).
- No skill tree beyond the VEX unlock message; no controller (gamepad) input yet — keyboard only.
- Boss Beat Wave projectiles are simple orbs; no touch-screen Vita controls.
