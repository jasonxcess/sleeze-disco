# SLEEZE DISCO — Beat Kune Do · Godot 3.5 Port Spec (from web build v7.6)

Source of truth: `~/workspace/games/sleeze-disco-v7/sleeze-disco-master/index.html`
(2,459 lines, the whole game), `HANDOFF.md`, `ROADMAP.md`, `playtest-notes.md`
(Rounds 4–9, v7.1–v7.6). All numbers below are copied verbatim from that code.
Nothing here is invented. Where a value is derived from code (not a literal),
it is marked `[derived]`. Where the code has no such value, it is listed in
§12 "Not found / no exact value in the web build".

Target: PS Vita VPK (PCH-2000, HENkaku Ensō). Godot 3.5. Canvas 960×544
(the Vita resolution). Keep the PSX low-poly look, the neon palette, and
Shawn's original art. Do not copy names/characters/story from Dead as Disco
or any other game.

Probe status of the source build: v7.1 37/37, v7.2 50/50, v7.3 53/53,
v7.4 59/59, v7.5 50/50, v7.6 27/27 phase + 28/28 regression — all green,
zero console/page/request errors. Never tested on a real Vita.

---

## 0. Palette & identity (literals from the CSS / `COL`)

| Name | Hex |
|---|---|
| gold | `#FFC83C` |
| red | `#E63232` |
| cyan | `#00F0FF` |
| pink | `#FF33CC` |
| purple | `#9D4EDD` |
| ink (background) | `#06030E` |
| panel | `#0E0A1C` |
| muted grey | `#8E94A5` |

Display font: `'Arial Black', Impact, sans-serif`. Mono font:
`'Courier New', Courier, monospace`. Title: `SLEEZE DISCO`, subtitle
`BEAT KUNE DO • NEON ARCADE PROTOTYPE (960×544)`.

---

## 1. Global constants

### 1.1 Canvas, playfield, frame loop

| Item | Value (source) |
|---|---|
| Canvas | `W = 960`, `H = 544` (`<canvas id="game" width="960" height="544">`) |
| Player spawn | `x: 240, y: 410` |
| Player clamp | `x: 60–900`, `y: 320–480` |
| Enemy clamp | `x: 40–920`, `y: 320–480` |
| Enemy spawn | `x: 920`, `y: 360 + Math.random() * 90` |
| Spawn interval | first spawn `G.spawnTimer = 0.5` (s), then `1.3` s between spawns |
| Frame dt clamp | `dt = min(0.05, (t - lastT) / 1000)` — sim never steps more than 50 ms |
| Beat-clock lookahead | scheduler schedules while `nextBeatTime < AC.currentTime + 0.15` |
| Music start offset | `nextBeatTime = AC.currentTime + 0.05` |
| Queue timer | `setInterval(..., 5)` ms — queued swings also fire off the audio clock |
| Tab-out resume re-anchor | `nextBeatTime = AC.currentTime + 0.1`, `lastBeatTime = nextBeatTime - beatDur` |

### 1.2 Beat clock & judge windows

| Item | Value |
|---|---|
| `beatDur` | `60 / bpm` seconds |
| PERFECT window | `off <= 0.065` s (±65 ms), damage mult `1.5`, colour gold |
| GOOD window | `off <= 0.13` s (±130 ms), damage mult `1.1`, colour cyan |
| Plain HIT (attacks only) | anything further off, mult `1.0`, colour white — **still lands** |
| Parry-press MISS | `judge()` only: anything past 0.13 s, mult `0.6`, colour `#8E94A5` |
| `beatOffset()` | `min(|nextBeatTime - now|, |now - lastBeatTime|)`, where `now = AC.currentTime - calMs/1000` |
| `timeToBeat(minAhead)` | next beat at least `minAhead` s out, minimum return `0.05` s |

Judge functions (verbatim logic):
- `judge()` (parry-press only): PERFECT ≤0.065 → `{name:'PERFECT!', mult:1.5}`; GOOD ≤0.13 → `{name:'GOOD', mult:1.1}`; else `{name:'MISS', mult:0.6}`.
- `judgeFromOffset(off)` (attacks): same PERFECT/GOOD thresholds; else `{name:'HIT', mult:1.0}`. **There is no MISS tier for player attacks.**

### 1.3 Latency calibration

| Item | Value |
|---|---|
| `calMs` range | `-150` to `+150`, slider step `5`, default `0` |
| First-run seed | `AC.outputLatency * 1000` (rounded, clamped ±150) — only when no saved value exists |
| Tap-along | 8 taps on a 120 BPM click; each tap records signed offset (ms) to the nearest beat on the raw audio clock (no `calMs` in the measurement); `calMs = round(average)`, clamped ±150 |

### 1.4 Movement (player)

| Item | Value |
|---|---|
| Walk speed | `280` px/s on X, `180` px/s on Y |
| Accel | `ACC = 280 / 0.12` px/s² [derived ≈ 2333.3] — reaches full speed in ~0.12 s |
| Decel | `DEC = 280 / 0.15` px/s² [derived ≈ 1866.7] — slides ~0.15 s to a stop |
| Core | `player.vx = approach(player.vx, mx * 280, (mx !== 0 ? ACC : DEC) * dt)`; same for `vy` with `my * 180` |
| `approach(v, target, step)` | move `v` toward `target` by at most `step`, never overshoot |
| Walk-cycle stride | `28` px — walk phase = `(walkDist / 28) % 1`; feet freeze when standing still |
| Facing deadzone (enemies) | `24` px — enemy facing flips only when `|dx| > 24` |
| Auto-face (player attacks) | nearest living enemy within `400` px, preferring held D-pad direction; face it if `|dx| > 12` |

### 1.5 Hit-stop, shake, knockback, separation

| Item | Value |
|---|---|
| Hit-stop, any landed hit | `0.04` s (40 ms) |
| Hit-stop, PERFECT / heavy (kick) / takedown / KO | `0.08` s (80 ms) |
| Hit-stop, finisher (E) | `0.15` s (slow-mo beat) |
| Mechanism | `G.hitStop` freezes `update()` (sim only; render clock `G.time` keeps ticking); `G.hitStop = max(G.hitStop, hs)` |
| Shake | PERFECT `7`; heavy (kick) `10`; KO `12`; takedown `15`; dash start `4`; player hurt `9`; blast-ring hit `12`; counter `10` |
| Shake decay | `G.shake = max(0, G.shake - dt * 28)` |
| Knockback | `e.kvx = (knock / 18) * 260` px/s; punch knock `18` → 260 px/s; kick knock `30` → ~433 px/s; counter knock `24` → ~347 px/s; Dash Strike knock `20` → ~289 px/s |
| Knockback decay | `e.kvx *= exp(-dt / 0.08)` (≈0.25 s arc, ~25 px for melee); zeroed when `|kvx| < 5` |
| Separation steering | pairs with `d < 70` px: `push = min((70 - d) / 2, 2)` px per frame along the pair axis (cap `2` px/frame — the uncapped push was the jitter source) |
| Impact rings | spawn on every hit; duration `beatDur`; `maxR` `46` normal / `70` heavy (kick / takedown / KO) |
| Floats | clamped `x` to `70–890`; simultaneous floats stack `+22` px in Y; lifetime `0.9` s, rise `45` px/s |
| Slashes | lifetime `0.18` s |
| Particles (burst) | `8` normal / `16` PERFECT / `15` parry / `22` finisher; life `0.4 + rand*0.25` s; gravity `550` px/s² |
| Corpses | play `knock` clip, fade after `1.6` s, removed at `2.2` s |
| `shadowBlur` | `8` (cut from 18/22 in v7.1) |

### 1.6 Dash (dodge)

| Item | Value |
|---|---|
| `dodgeT` (i-frame window) | `0.32` s — i-frames for the full window |
| `dodgeCd` | `1.5 * beatDur` (scales with BPM) |
| Dash velocity | `dashVx = 700 * dashDir`, decaying linearly: `700 * dashDir * (dodgeT / 0.32)` during the window |
| Total dash distance | ≈112 px by the formula [derived: 700 × 0.32 / 2]; probes measured **121–123 px** — see §12 |
| Afterimage ghosts | one every `0.08` s during the dash, `life: 0.28`, alpha `0.35` fading, cyan tint |
| Dash start FX | `G.shake = max(G.shake, 4)`, burst of `10` cyan particles, float `PHASE DASH` (cyan) |

---

## 2. Player moves

Input map — keyboard / touch pad (Vita: map to the same actions):

| Action | Keyboard | Touch pad | Vita suggestion (not in web code) |
|---|---|---|---|
| Punch | `J` | □ HIT | □ |
| Kick | `K` | △ KICK | △ |
| Throw | `L` | ○ THW | ○ |
| Dodge / dash | `Space` | ✕ DASH | ✕ |
| Parry | `S` | L1 PAR | L1 |
| Dance | `F` | ♪ DANCE | — (pick a free button) |
| Takedown / finisher | `E` | R1 FIN | R1 |
| Move | Arrow keys | D-pad (8-way, diagonals press both axes) | D-pad / left stick |

Shared rules:
- Offensive moves (punch/kick/throw) are **queued**: one pending action at a time, a newer press replaces it; fires on the next beat boundary (`fireAt` on the unshifted audio clock); judged by the **press** offset, not the fire time. If a swing is still in flight (`player.atkT > 0`) when the beat lands, the queue holds one more beat. No audio clock → fire at once with offset `999` (plain HIT).
- Parry and dodge fire **instantly on press, never queued**.
- Attack swing time: `player.atkT = 0.2 / rushSpd` s (`rushSpd = 1.3` during Fever Rush, else `1`).
- Attack lunge (velocity burst, decays `lungeVx *= exp(-5 * dt)`, zeroed below `2` px/s): punch `140 * facing`, kick `180 * facing` px/s.
- Every 3rd punch (`punchIx % 3 === 0`) plays the `upper` clip instead of `punch`.
- PERFECT kick cycles `DANCE_KICKS = ['spinback', 'armada', 'meialua', 'sweep', 'spinflip']`.
- Attack judgement tone: PERFECT `780` Hz, else `420` Hz, square, `0.08` s, vol `0.15`, slide to `220`.

### 2.1 Punch

| Item | Value |
|---|---|
| Base damage | `11` |
| Reach | `105` px (X), `|dy| < 55` px |
| Lunge | `140 * facing` px/s |
| Windup lead-in | `pre: 'windup', preDur: 0.08` s |
| Clip duration | `clipDur('punch', 0.6)` — see §2.7; measured `0.36 / 0.30 / 0.257` s at 100/120/140 BPM |

### 2.2 Kick

| Item | Value |
|---|---|
| Base damage | `16` (plain) / `22` (SPINBACK KICK unlock) |
| Reach | `135` px plain / `175` px with SPINBACK KICK (X), `|dy| < 55` px |
| Lunge | `180 * facing` px/s |
| Windup lead-in | `pre: 'windup', preDur: 0.1` s |
| Clip duration | `clipDur('kick', 0.8)`; spinback/string: `clipDur('spinback', 1.2)`; measured plain-kick `0.417 / 0.40 / 0.343` s at 100/120/140 BPM |
| Heavy | yes — `heavy: true` in `applyHit` (80 ms hit-stop, shake 10, 70 px impact ring) |

### 2.3 Throw (ranged)

| Item | Value |
|---|---|
| Base damage | `10` |
| Projectile | `vx: 680 * facing` px/s, spawn `x: player.x + 30 * facing`, `y: player.y - 65` |
| Hit box | `|e.x - p.x| < 35` and `|e.y - 60 - p.y| < 60`; first enemy hit only; removed on hit or when `p.x < 0` / `p.x > 960` |
| Pays | exactly like a melee hit (`applyHit(e, 10, p.j, {})`) — same score/combo/Fever |
| Cooldown | none of its own — shares the `0.2 / rushSpd` s swing time |
| Clip | `clipDur('throw', 0.7)` |

### 2.4 Dodge / dash

See §1.6. `dodgeT 0.32` s, `dodgeCd 1.5 * beatDur`, `dashVx 700` px/s decaying.
Strikes and rings check `player.dodgeT > 0` → no damage, no combo break.

### 2.5 Parry

| Item | Value |
|---|---|
| Window | `parryT = 0.38` s (block clip `0.38` s) |
| Cooldown | `parryCd = 2 * beatDur` (scales with BPM) |
| Judgement | judged **at press time** (`player.parryJudge = judge()`); payoff uses the stored press judgement, not the strike time |
| Strike-time parry (enemy strike lands while `parryT > 0`) | enemy `stunT = 1.6` s; clean (PERFECT/GOOD press): `gainScore(200)`, `+15` Fever, `+2` style, float `PARRIED! +<gain>` (cyan); off-beat (MISS press): `+3` Fever only, float `PARRIED (OFF-BEAT) +3` |
| Ring parry (blast/sweep ring contact while `parryT > 0`) | ring consumed, owner `stunT = 1.6` s, `state = 'chase'`; clean: `gainScore(200)`, `+15` Fever, `+2` style, float `BLAST PARRIED! +<gain>`; off-beat: `+3` Fever, float `BLAST PARRIED (OFF-BEAT) +3` |
| COUNTER (press while a telegraphing enemy is within `260` px) | nearest telegraphing enemy only: `stunT = 1.6` s, `state = 'recover'`, `stateT = 0.4`, `windup = 0`; `applyHit(counter, 20, {name:'COUNTER', mult:1, color:gold}, {knock: 24 * facing, heavy:true, floatText:'COUNTER! -20'})`; `+4` style; `+10` Fever (via `applyHit` COUNTER branch); shake `10`; gold `COUNTER` prompt + red `!` shown over telegraphing enemies |

### 2.6 Takedown / finisher (E)

| Item | Value |
|---|---|
| Cost | `1` token; `0` tokens → grey float `NO TOKENS` + `140` Hz tone, nothing else |
| Damage | `65` to **every** enemy with `|e.x - player.x| < 320` (no Y check) |
| Stun | hit enemies `stunT = 1.5` s, `flashT = 0.2` |
| Hit-stop | `0.15` s; shake `15` |
| Banner | `★ BEAT DROP FINISHER ★`, `1.5` s |
| Clip | cycles `['headspin', 'flair', 'spinflip']`, duration `beatDur * 3`, looping |
| Style | `+2`; adds `takedown` to style variety |
| Fever | finisher hits build **nothing** (`fever: false` in `applyHit`) |
| Float | `SMASH -65!` (gold) per enemy hit |

### 2.7 Dance (F)

| Item | Value |
|---|---|
| Damage | none |
| Fever | `+8` (`FEVER.DANCE`) |
| Clip | cycles `DANCE_CLIPS = ['hiphop', 'headspin', 'flair', 'taunt']`, duration exactly `1` beat (`beatDur`) |
| Move slot | holds it for its beat: `player.atkT = beatDur`, `atkKind = 'dance'` — swings wait; blocked while `player.atkT > 0` or a gap-closer `pendingHit` is active |
| Movement | never moves the player, never interrupts movement |
| Style | adds `dance` to style variety (the 8th move type); no style points |
| Float | `DANCE +8 FEVER` (pink); tone `660` Hz → `880`, square, `0.08` s, vol `0.1` |
| Not queued | fires immediately, like parry/dodge |

### 2.8 Gap-closer (auto, part of punch/kick)

- Triggers when target is out of reach but `dist <= 260` px, `gap = |dx| - (reach - 12) > 0`, and `sign(dx) === player.facing`.
- `player.lungeVx = facing * min(1500, gap * 9.5) * rushSpd` px/s; `pendingHit = {kind, j, target, t: 0.15 / rushSpd, spin, string}`.
- Hit resolves when the lunge carries Sleeze into reach (`|dx| < reach`, `|dy| < 55`) or after `0.15 / rushSpd` s at the latest; lunge stops dead on arrival (`lungeVx = 0`). Past 260 px there is no gap-close — walk.
- If the target dies first, `pendingHit` is cancelled and `lungeVx = 0`.

### 2.9 Combo string (shop upgrade, P5)

- Requires shop `combo` owned (100 fans, one-time).
- When the last 3 **executed** attacks (post-queue, `atkHist`, max length 3) are `punch, punch, kick` in order, the kick is a string ender: judgement mult `× 1.5` on top, `spinback` clip, float `STRING!` (gold), `+3` style.
- A throw between the punches breaks the string. No clash with the every-3rd-punch upper rule.
- Verified live: PERFECT string kick dealt `36` (16 × 1.5 judgement × 1.5 string).

### 2.10 Clip timing helper

- `ATK_DUR = 0.2` (s).
- `clipDur(clip, beats)`: `natural = clipFrames(clip) / 24`; return `max(0.25, min(natural, beats * beatDur))`. Never under 0.25 s, never longer than the clip needs at ~24 fps.
- `setMove(clip, dur, o)`: one-shot; `o.pre` plays a `windup` lead-in first (`t` starts at `-preDur`); `o.loop` loops; `o.hold` holds the last frame.

---

## 3. Enemies & bosses

### 3.1 Spawn stats table (verbatim from `spawnEnemy`)

| Type | Internal | Display name | HP | Speed (px/s) | Damage | Colour | w × h |
|---|---|---|---|---|---|---|---|
| stan | `stan` | BOUNCER | `35` | `65` | `8` | cyan `#00F0FF` | 44 × 185 |
| charger | `charger` | RUSHER | `45` | `95` | `14` | red `#E63232` | 46 × 190 |
| bruiser | `bruiser` | HEAVY | `95` | `42` | `18` | purple `#9D4EDD` | 60 × 225 |
| boss1 (Ch.1) | `boss1` | DR. CLIPBOARD | `140` | `55` | `14` | gold `#FFC83C` | 56 × 210 |
| boss2 (Ch.2) | `boss2` | SUBJECT SEVEN | `180` | `70` | `16` | pink `#FF33CC` | 58 × 215 |
| vex (Ch.3) | `vex` | VEX | `280` | `60` | `16` | pink `#FF33CC` | 54 × 250 |

- Effective speed at spawn: `spd * (G.speedMul || 1)` (endless ramp only; story `speedMul = 1`).
- Draw heights (`DRAW_H`): player `200`, stan `185`, charger `190`, bruiser `225`, boss1 `210`, boss2 `215`, vex `250`.
- Enemy fields at spawn: `windupMax = 0.7 + Math.random() * 0.3` s, `blastT = 8`, `blastPhase = 0`, `blastAnnounced = false`, `sigT = 7`, `sigAnnounced = false`, `chain = 0`, `chainArmed = false`, `facing = -1`, state `chase`, `stateT = 0`.
- Boss spawn banner (`2.5` s): `DR. CLIPBOARD: ROPE SWEEP` / `SUBJECT SEVEN: TRIPLE TAP`.
- Sheet/tint: boss1 reuses the `thug` sheet with gold tint `rgba(255,200,60,0.35)`; boss2 reuses the `dead` sheet with pink tint `rgba(255,80,180,0.30)`; bruiser tint `rgba(150,60,255,0.22)`. No new art for bosses.

### 3.2 Enemy AI state machine (all types)

States: `chase → windup → telegraph → strike → recover → chase`. Plus `blast` (VEX) and `sweep` (boss1). Stun/taunt override everything.

| State | Timing / behaviour |
|---|---|
| `chase` | Move toward player while `dist > 72` px: desired velocity `(dx/dist)*spd` on X, `(dy/dist)*spd*0.6` on Y; velocity lerps toward it with `k = min(1, 8*dt)`; walk cycle driven by distance (`walkDist / 28`). At `dist <= 72`: velocity `0`, state `windup`, `stateT = windupMax` (0.7–1.0 s, per-enemy random). |
| `windup` | Stand still (velocity lerps to 0, `k = min(1, 8*dt)`). `stateT` only ticks down when no other enemy within `120` px is in `telegraph`/`strike`/`sweep` (nobody swings together — nearby enemies hold). On expiry → `telegraph`: `teleDur = timeToBeat(0.25)`, `stateT = teleDur`, `windup = 0`. |
| `telegraph` | Duration `teleDur` — the strike snaps to the next beat, never sooner than ~0.25 s. Red flashing variant + gold `COUNTER` prompt + red `!` over the enemy. Step-in: moves toward the player at `0.6 * spd` (same lerped velocity as chase, `k = min(1, 8*dt)`), so a short gap closes but a player who walked away still outruns the strike. `windup` display value ramps `0 → 1`. On expiry → `strike`, `stateT = 0.12`, `resolveStrike(e)` runs. |
| `strike` | `0.12` s, velocity lerps to 0. On expiry: boss2 with `chain > 0` → `chain--`, back to `windup` with `stateT = 0.35`; otherwise `chainArmed = false`, state `recover`, `stateT = 0.4`, `windup = 0`. |
| `recover` | `0.4` s, velocity lerps to 0. On expiry → `chase`, `windup = 0`. |
| `stunT > 0` | Frozen entirely (no movement, no state progress). Set to `1.6` s by parry/counter/ring-parry. |
| `tauntT` | `1.2` s after the enemy lands a hit on the player; AI frozen; if state is `recover`, its `stateT` still ticks. Plays the `taunt` clip. |
| Knockback | `kvx` arc applies in every state (see §1.5). |
| Hit flash | `flashT = 0.12` s on any hit taken. |

`resolveStrike(e)` — runs at the telegraph→strike transition:
1. Range check first: `dist = hypot(player - e)`; if `dist > 90` → float `WHIFF` (grey), no damage.
2. Else if `player.parryT > 0` → parry payoff (§2.5), enemy `stunT = 1.6`.
3. Else if `player.dodgeT > 0` → nothing (dodged).
4. Else: `player.hp -= e.dmg`; `player.hurtT = 0.25`; `G.combo = 0`; `G.style *= 0.75`; `G.shake = 9`; `setMove('hit', 0.35)`; `e.tauntT = 1.2`; floats `-<dmg>` (red) and `STYLE -25%` (grey). If `player.hp <= 0` → `endFight(false)`.

Enemy clips by state (`enemyAnim`): taunt → `taunt`; stun → `hit`; flash → `hit`; windup → `windup` (progress `0.85 * (1 - stateT/windupMax)`); telegraph/blast/sweep → `windup` at `0.99`; strike (bruiser) → `upper`; recover (bruiser) → `upper`; strike → `punch`; recover → `punch`; chase → `walk` by distance.

### 3.3 Boss signatures

**DR. CLIPBOARD — ROPE SWEEP (Ch.1)**
- Timer `sigT`, starts `7` s, ticks only in `chase` or `recover` (never windup/telegraph/strike — a COUNTER prompt is never cut across). On expiry: `sigT = 7`, `startSweep(e)`.
- `startSweep`: state `sweep`, `stateT = timeToBeat(0.25)`; first time only (`sigAnnounced`): banner `DR. CLIPBOARD: ROPE SWEEP — DODGE OR PARRY`, `2` s.
- `fireSweep`: ring `{cx: e.x, cy: e.y - 60, r: 0, maxR: 300, t: 0, dur: 0.6, dmg: 14, done: false, owner: e}`; state `recover`, `stateT = 0.4`, `windup = 0`.
- Ring payoff (shared with Blast, §3.4).

**SUBJECT SEVEN — TRIPLE TAP (Ch.2)**
- On the first windup→telegraph transition of a fresh sequence (`!chainArmed`): `chainArmed = true`, `chain = 2`; first time only: banner `SUBJECT SEVEN: TRIPLE TAP`, `2` s.
- After each strike, if `chain > 0`: `chain--`, state `windup`, `stateT = 0.35` s, then a fresh telegraph (snapped to its own beat) and strike. Total: 3 strikes per sequence. COUNTER prompt is live on every telegraph.

**VEX — SPOTLIGHT BLAST (Ch.3)**
- Timer `blastT`, starts `8` s, ticks whenever VEX is not already in `blast` state.
- Phase thresholds: at `hp/maxHp <= 0.66` (`blastPhase` 0→1) and `<= 0.33` (1→2), a Blast starts immediately regardless of the timer.
- `startBlast`: state `blast`, `stateT = timeToBeat(0.25)`, `blastT = 8` (reset); first time only (`blastAnnounced`): banner `VEX: SPOTLIGHT BLAST — DODGE OR PARRY`, `2` s.
- `fireBlast`: ring `{cx: e.x, cy: e.y - 60, r: 0, maxR: 420, t: 0, dur: 0.7, dmg: 20, done: false, owner: e}`; state `recover`, `stateT = 0.4`, `windup = 0`.
- During `blast` state the enemy stands still (`windup` display `0.6`).

### 3.4 Shockwave rings (shared system)

- Ring expands linearly: `r = (t / dur) * maxR`.
- Player contact when `|dist(player centre, ring centre) - r| < 30` px, where the player centre is `(player.x, player.y - 60)`.
- If `player.parryT > 0` → ring parry (§2.5), ring `done = true`, owner stunned `1.6` s.
- Else if `player.dodgeT > 0` → nothing (ring passes through; `done` stays false, so it can still be parried later in its travel — it is only consumed by a parry or a hit).
- Else → ring `done = true`: `player.hp -= r.dmg`; `hurtT = 0.25`; `combo = 0`; `style *= 0.75`; `shake = 12`; `setMove('hit', 0.35)`; floats `-<dmg>` and `STYLE -25%`; death → `endFight(false)`.
- Rings are removed when `t >= dur`.

### 3.5 Boss unlocks (persisted)

- Beating Ch.1 → **DASH STRIKE**: during any later dash, the first enemy within `80` px takes `14` damage, once per dash (`dashHitDone` flag, reset per dash). Float `DASH STRIKE -14` (cyan), knock `20 * dashDir`. Live in every later fight, endless included.
- Beating Ch.2 → **SPINBACK KICK**: every kick becomes the spinback clip, `175` px reach, `22` base damage (see §2.2).
- Ch.3 grants no move (`unlock: null`).
- Unlock banner on the end screen: `★ UNLOCKED: <MOVE> ★`.
- Persistence key: `sleezeDiscoUnlocksV1` (JSON `{dash: bool, spinKick: bool}`).
- How-to screen lists owned moves: `BOSS MOVES OWNED: DASH STRIKE — dash through an enemy to hit them (Ch.1 boss) · SPINBACK KICK — kicks hit wider and harder (Ch.2 boss)`, or `NO BOSS MOVES YET — BEAT A CHAPTER BOSS TO TAKE ITS MOVE.`

---

## 4. Waves / endless

### 4.1 Story chapters (spawn queues, in order; one spawn per 1.3 s)

| Chapter | Queue |
|---|---|
| Ch.1 | `['stan', 'stan', 'charger', 'stan', 'stan', 'boss1']` |
| Ch.2 | `['charger', 'stan', 'bruiser', 'charger', 'bruiser', 'boss2']` |
| Ch.3 | `['stan', 'charger', 'vex']` |

- Story fight ends the frame the queue is empty **and** `enemies.length === 0` → `endFight(true)`.
- Story BPM is fixed per chapter (no ramp): Ch.1 `100`, Ch.2 `120`, Ch.3 `140`.

### 4.2 Endless

- First wave queue: `['stan', 'stan', 'charger', 'bruiser']`. Default endless track is `dceased` (120 BPM).
- Wave clear (queue empty and no enemies left):
  1. Dance break first: `G.danceT = beatDur * 8`; Sleeze plays `hiphop` looping for exactly 8 beats; banner `WAVE CLEAR — DANCE BREAK` (`1.6` s); pending action and pendingHit cleared; sim returns early during the break.
  2. Then: `G.wave++`; heal `player.hp = min(player.maxHp, player.hp + 15)`.
  3. Synth track: `G.endlessBpm = min(160, track.bpm + (G.wave - 1) * 5)`; `G.speedMul = min(1.5, 1 + (G.wave - 1) * 0.05)`; `startMusic(G.endlessBpm)`; banner `WAVE <n> — <bpm> BPM` (`2` s). Examples: MY LUVA climbs 100, 105, 110…; DCEASED climbs 120, 125, 130….
  4. Imported track: no BPM ramp, no music restart; banner `WAVE <n> — <bpm> BPM · YOUR TRACK` (`2` s).
  5. Next queue: `qn = min(8, 3 + G.wave)` enemies drawn cyclically from pool `['stan', 'charger', 'bruiser', 'stan', 'charger', 'bruiser', 'stan', 'charger']` (`pool[i % pool.length]`).
- Endless never ends on wave clear; it ends only when the player dies (`endFight(false)`).

---

## 5. Combo / style rank / score

### 5.1 Combo

- `G.combo++` on every landed hit (melee, throw, counter, Dash Strike, finisher — all through `applyHit`). One hit can strike multiple enemies at once (melee loops all in reach); each enemy hit increments the combo separately.
- Combo breaks **only when the player gets hit** (enemy strike or ring): `G.combo = 0`. Off-beat inputs never break it (MISS retired for attacks, §1.2).
- `G.maxCombo` tracks the peak. Score per hit: `gainScore(dmg * (1 + floor(G.combo / 5)))`.
- KO bonus: `gainScore(100)` per KO (plus `+6` Fever).
- Parry payoff: `gainScore(200)` (clean parry only; off-beat parry pays no score).
- `gainScore(n) = round(n * rankMult())`; every point of score goes through it.

### 5.2 Style points

| Event | Style points |
|---|---|
| PERFECT hit | `+3` |
| GOOD hit | `+1` |
| Plain HIT | `+0` |
| Counter | `+4` |
| Clean parry | `+2` |
| Takedown (E) | `+2` |
| Combo-string ender | `+3` |
| Dance | `+0` points (variety only) |
| Getting hit | `G.style *= 0.75` (−25%, float `STYLE -25%`) |

### 5.3 Style variety & rank

- Variety: distinct move types used in the fight, from `{punch, kick, throw, dodge, parry, counter, takedown, dance}` — **8 max** (code, v7.6; the v7.2 note said 7 because dance did not exist yet).
- Effective style: `styleEff() = G.style * (1 + 0.1 * styleMoves.size)`.
- Rank thresholds (on effective style): `D < 20`, `C ≥ 20`, `B ≥ 40`, `A ≥ 70`, `S ≥ 110`, `SLEEZE ≥ 160`.
- Score multipliers: `D 1.0×`, `C 1.1×`, `B 1.2×`, `A 1.3×`, `S 1.4×`, `SLEEZE 1.5×`.
- Rank colours: D `#8E94A5`, C cyan, B purple, A pink, S gold, SLEEZE gold.
- HUD style meter fills to the `160` SLEEZE line; minimum visible fill `6` px once any style is banked.

---

## 6. Fever system

### 6.1 Gain table (`FEVER`, verbatim)

| Source | Gain |
|---|---|
| PERFECT hit | `+12` |
| GOOD hit | `+7` |
| Plain HIT (snapped off-beat) | `+0` |
| Dance move | `+8` |
| Counter hit | `+10` |
| Clean parry (PERFECT/GOOD press) | `+15` |
| Off-beat parry (MISS press) | `+3` |
| KO bonus | `+6` |
| Finisher hits | `+0` (they spend, not build) |

- All gains funnel through `addFever(n)`: `player.fever = min(100, player.fever + n)`.
- With the shop Faster Fever Gain upgrade: every gain `× 1.5`, rounded — PERFECT `+18`, GOOD `+11`, dance `+12`, counter `+15`, clean parry `+23`, off-beat parry `+5`, KO `+9`. (GOOD: 7 × 1.5 = 10.5 → 11.)
- No Fever gains land during a Rush (`addFever` returns early while `G.rushT > 0`).

### 6.2 Fever Rush

- Auto-starts at `100` Fever (never a manual trigger; the old meter-100 finisher path is deleted).
- Duration: `G.rushT = 8` — **8 beats, not 8 seconds**; it rides the music.
- During Rush: attacks `30%` faster (`rushSpd = 1.3`: `atkT 0.2 → 0.2/1.3 ≈ 0.154` s; gap-closer `0.15 → 0.115` s; lunge speed `× 1.3`); synth gets denser (extra 16th hits at `+0.25 / +0.5 / +0.75` beat inside the same grid — `beatDur` never moves); lights/EQ go wild (lights-layer alpha up to `1.0`, EQ bars `× 1.6` amplitude).
- Drain: `player.fever = 100 * G.rushT / 8`, falling `100 → 0` across the 8 beats; at the end `G.rushT = 0`, `player.fever = 0`, then refills normally. No re-trigger while a Rush runs.
- Banner: `FEVER RUSH!` (`2` s) + `880` Hz square tone sliding to `1320`, `0.15` s, vol `0.18`.
- HUD: `FEVER <floor(fever)>% ` + token stars `★`×tokens + `☆`×(cap − tokens).

### 6.3 Takedown tokens

- Earn: every `12` combo earns `1` token (`G.combo % 12 === 0`, checked in `applyHit`; combo climbs 1 per hit so it fires exactly at 12 / 24 / 36…), up to the cap.
- Base cap `3`; `tokenCap() = min(5, 3 + shop.tokens)` (shop upgrade, §7).
- Tokens reset to `0` in `beginFight`; never persist across fights.
- Float on earn: `★ TOKEN +1` (gold).
- Spend: E, see §2.6.

---

## 7. Hub / shop / saves

### 7.1 Fans

- Formula: `fansEarned = floor(G.score / 100) + 2 * G.kos` — story AND endless, win AND loss. Paid once per fight (`endFight` guards with `if (G.state === 'end') return`).
- `G.kos` increments in the `applyHit` KO branch. Balance persists immediately (`saveShop()`).
- End screen shows: `FANS EARNED: +<n> | FAN BALANCE: <total>`.

### 7.2 Shop items (verbatim from `SHOP_ITEMS` / `FIT_ITEMS`)

| # | Item | Cost | Effect | Repeatable |
|---|---|---|---|---|
| 1 | `+25 MAX HP` | `50` fans | Max HP `100 + 25 × bought`; fights start at full HP; buying never heals mid-fight | Yes, no cap |
| 2 | `+1 TAKEDOWN TOKEN SLOT` | `80` fans | Token cap `3 → 4 → 5`; earn rule unchanged (1 per 12 combo) | Yes, hard cap `5` |
| 3 | `FASTER FEVER GAIN` | `60` fans | All Fever gains `× 1.5`, rounded (see §6.1) | One-time |
| 4 | `NEW COMBO STRING` | `100` fans | Punch, punch, kick — kick is a finisher-grade ender, `1.5×` on top of judgement mult, spinback clip, `STRING!` float, `+3` style | One-time |
| 5a | `FIT — GOLD JACKET` | `40` fans | Gold jacket tint `rgba(255,200,60,0.35)` | One-time per fit |
| 5b | `FIT — RED JACKET` | `40` fans | Red jacket tint `rgba(230,50,50,0.35)` | One-time per fit |
| 5c | `FIT — CYAN JACKET` | `40` fans | Cyan jacket tint `rgba(0,240,255,0.35)` | One-time per fit |

- Fits: buying never auto-equips; equip is free, one fit at a time; applied via `ANIM_TINT.player` (same tint path bosses use); `shop.fit = 'none' | 'gold' | 'red' | 'cyan'`.
- Buying with too few fans does nothing (buttons render disabled; `buyShop` has a backstop guard — no deduction on a failed buy).
- Hub balance line: `FANS: <n> · MAX HP <maxHpFor()> · TOKEN SLOTS <tokenCap()>`.
- Hub flow: opened from title (`GREEN ROOM` button) or end screen (`HUB` button); `openHub` remembers the origin; `CONTINUE` returns there (`end` → end screen, `title` → title screen); `TITLE` always goes to the title screen.

### 7.3 Save keys (localStorage in the web build — all must become file saves on Vita, see §11)

| Key | Contents |
|---|---|
| `sleezeDiscoTouchHighV1` | High score (plain integer string) |
| `sleezeDiscoUnlocksV1` | JSON `{dash: bool, spinKick: bool}` |
| `sleezeDiscoSaveV1` | JSON `{fans, hp, tokens, fever: bool, combo: bool, fits: {gold, red, cyan}, fit: 'none'/'gold'/'red'/'cyan'}` |
| `sleezeDiscoTouchCalV1` | Calibration `calMs` (plain integer string, clamped ±150) |

---

## 8. Music — TRACKS table (verbatim)

`TRACKS` in `index.html` is the one pattern system (it replaced the P4 `GENRE_PAT`, which is gone from the code). Each track: BPM preset + bass/lead pattern arrays, 8 steps each, indexed `beatIndex % 8`. Patterns are frequencies in Hz.

| Key | Name | BPM | Genre | Bass (8) | Lead (8) |
|---|---|---|---|---|---|
| `myluva` | MY LUVA | 100 | FUNK | `[55, 55, 65.41, 49, 55, 55, 82.41, 73.42]` | `[220, 261.63, 329.63, 392, 329.63, 261.63, 220, 196]` |
| `bigscreen` | BIG SCREEN | 110 | FUNK | `[55, 49, 55, 65.41, 55, 73.42, 55, 49]` | `[246.94, 220, 261.63, 293.66, 261.63, 220, 196, 220]` |
| `dceased` | DCEASED | 120 | HOUSE | `[55, 55, 55, 55, 65.41, 55, 49, 55]` | `[220, 220, 261.63, 220, 196, 220, 246.94, 220]` |
| `foolmeonce` | FOOL ME ONCE | 130 | HOUSE | `[58.27, 58.27, 51.91, 58.27, 65.41, 58.27, 49, 58.27]` | `[233.08, 220, 261.63, 233.08, 196, 220, 246.94, 233.08]` |
| `shittalkin` | SHIT TALKIN | 140 | DARK DISCO | `[55, 49, 55, 65.41, 55, 49, 82.41, 73.42]` | `[220, 196, 220, 261.63, 220, 196, 174.61, 196]` |

All 5 bass patterns are pairwise distinct; all 5 leads are pairwise distinct (probe-verified). Location in source: `const TRACKS = {...}` in the WebAudio Synth Engine section of `index.html` (right after the tap-along calibration code, before `initAudio()`).

Chapter mapping (in `BOSS_INFO[].track` — intro card and scheduler read the same map):

| Chapter | Track | BPM | Genre |
|---|---|---|---|
| Ch.1 | MY LUVA (`myluva`) | 100 | FUNK |
| Ch.2 | DCEASED (`dceased`) | 120 | HOUSE |
| Ch.3 | SHIT TALKIN (`shittalkin`) | 140 | DARK DISCO |

### 8.1 Synth engine (what the patterns drive)

- Master gain `0.45`.
- Per beat (step `i = beatIndex`): kick `tone(145 Hz, 0.16 s, sine, vol 0.6, slide to 42)`; bass `tone(pat.bass[i % 8], beatDur * 0.85, sawtooth, vol 0.16)`; lead `tone(pat.lead[i % 8], beatDur * 0.4, square, vol 0.06)`.
- During Fever Rush, extra 16ths inside the same beat grid (beatDur never moves): `190 Hz` square `0.06` s vol `0.07` slide to `120` at `+0.25` and `+0.75` beat; bass `pat.bass[(i+4) % 8]` sawtooth `beatDur * 0.3` vol `0.10` at `+0.5` beat.
- Each `tone(freq, t, dur, type, vol, slide)`: oscillator + gain envelope `vol → 0.001` (exponential) over `dur`; optional exponential frequency ramp to `slide`.
- The beat clock (`nextBeatTime` / `beatIndex` / `lastBeatTime`) is independent of the tones — it is what judgement, Rush, and the latency slider read.
- Imported-track runs (web only): synth tones muted, the file loops instead; beat clock identical. See §11.

### 8.2 BPM detector (web only, for reference)

`detectBPM(buf)`: onset envelope (frame-energy jumps, hop `512`), autocorrelated over lags for **80–180 BPM**, parabolic-refined around the peak; half-period octave guard (a half lag scoring within `90%` of the peak means the peak was the double period — take the faster tempo). Returns `{bpm, conf}` or `null` when the file is too short (fewer than `200` frames, ~2.3 s at 44.1 kHz) or has no readable pulse. Verified accuracy: 120 BPM click track (MP3) → `120.1`; 100 BPM click track (WAV) → `99.6`.

---

## 9. VEX story exchange (verbatim, 4 lines)

Shown on `scr-story` between the Ch.3 intro card and the fight. Speaker colours: VEX pink `#FF33CC`, JAY gold `#FFC83C`.

> **VEX:** "Jay. You actually came. Cute."
>
> **JAY:** "Vex. Whole club got clipboards and lab coats. What is this?"
>
> **VEX:** "It's a lab, baby. You the next experiment. Them other dudes? They didn't make it past the door."
>
> **JAY:** "So all them dates was test runs. Aight. Bet."

Screen header: tag `CH.3 — VEX`, title `LAST DANCE`, button `▶ FIGHT`.

---

## 10. Screens / flow & on-screen text

Flow: `title → mode → intro → [story, Ch.3 only] → fight → end → (hub | next chapter | retry | title)`. Hub is also reachable from the title. How-to is reachable from the title. Pause overlay appears on tab-out during a fight.

| Screen | Key text (verbatim) |
|---|---|
| Title tag | `Harmony Corp Took The Stage` |
| Title | `SLEEZE DISCO` |
| Title desc | `Strike, dodge, and parry on the beat. PERFECT (±65ms) deals +50% damage and builds FEVER — fill it for FEVER RUSH. Off-beat swings snap to the next beat and still land — only getting hit breaks your combo. Dance [F] builds Fever too; every 12 combo earns a ★, and [E] spends one on a finisher.` |
| Title buttons | `▶ ENTER THE CLUB` / `GREEN ROOM` / `CONTROLS` |
| Title calibration | `AUDIO DELAY (ms)`; hint `PHONE AUDIO RUNS LATE — NUDGE IT UNTIL PERFECT LANDS ON THE BEAT`; tap button `♪ TAP ALONG`; status `TAP 8 TIMES ON THE CLICK TO TUNE THE DELAY` |
| Rotate bar (portrait phones) | `↻ ROTATE FOR FULL SCREEN` |
| Mode screen | tag `Select Track`, title `PICK YOUR NIGHT`, desc `STORY CHAPTERS RUN ON SLEEZE'S OWN TRACKS — SYNTH REBUILDS, STREAMER-SAFE.` |
| Mode story buttons | `CH.1 DR. CLIPBOARD — MY LUVA · FUNK 100 BPM` / `CH.2 SUBJECT SEVEN — DCEASED · HOUSE 120 BPM` / `CH.3 VEX — SHIT TALKIN · DARK DISCO 140 BPM` |
| Mode endless buttons | `∞ MY LUVA — FUNK 100 BPM` / `∞ BIG SCREEN — FUNK 110 BPM` / `∞ DCEASED — HOUSE 120 BPM` / `∞ FOOL ME ONCE — HOUSE 130 BPM` / `∞ SHIT TALKIN — DARK DISCO 140 BPM` |
| Mode import row | `♪ IMPORT MP3 / WAV` / `▶ PLAY ENDLESS`; status `PICK AN MP3 OR WAV — THE BEAT GETS READ OFF THE FILE (80–180 BPM), THEN IT LOOPS UNDER ENDLESS. ON THE VITA, ENDLESS USES THE PRESET TRACK BPMS ABOVE.`; error `COULD NOT READ THAT FILE — TRY AN MP3 OR WAV. THE SYNTH TRACKS STILL WORK.`; detected `DETECTED: <bpm> BPM — <NAME> (READ <conf>%)` |
| How-to | tag `Combat Manual`, title `BEAT KUNE DO` |
| How-to manual | `ARROWS / D-PAD: Move across the dancefloor` · `[J] / □ PUNCH: Fast beat jab | [K] / △ KICK: Heavy knockback` · `[L] / ○ THROW: Ranged neon drumstick` · `[SPACE] / ✕ DODGE: Dash through red attacks` · `[S] / L1 PARRY: Deflect & stun attackers` · `[F] / ♪ DANCE: Pure dance move — no damage, builds Fever + style variety` · `[E] / R1 TAKEDOWN: Spend 1 ★ token (earned every 12 combo — buy more slots in the Green Room) for a cinematic finisher` · `BOSS MOVES: beat a chapter boss to take its move — Ch.1 unlocks DASH STRIKE (the dash itself hits), Ch.2 unlocks SPINBACK KICK (wider, harder kicks)` · `FEVER: on-beat hits + dance fill it — at 100% FEVER RUSH starts on its own: faster attacks, denser drums, wild lights` · `GOLD COUNTER: parry while the gold COUNTER prompt is up to stun & smash` · `OFF-BEAT: swings snap to the next beat and still land — only getting hit breaks your combo` · `MUSIC: story chapters run on Sleeze's own tracks — My Luva (Ch.1), DCeased (Ch.2), Shit Talkin (Ch.3). Endless lets you pick any of the five, or import your own MP3/WAV — the beat gets read off the file and it loops under the fight (web only; the Vita uses the preset track BPMs)` |
| How-to credits | `Soundtrack: SleezeTeamJason — My Luva, DCeased, Shit Talkin, Big Screen, Fool Me Once (synth rebuilds of his own tracks, no licensed recordings). 3D credits (CC BY 4.0, via Sketchfab): "PSX Graphics \| Low Poly Woman" by murilo.kleine • "Enemy1" by bumstrum • "Raised dead" by Pjotr Heinkens (CC BY-NC) • "PSXprop - Male Character 02" by WardsterSAW (Free Standard) • Motion: Adobe Mixamo • "Night Dance Club Lowpoly" by 00amza (CC BY 4.0)` |
| How-to button | `GOT IT` |
| Intro card | tag `CHAPTER <n> — <GENRE> · <BPM> BPM`; name = boss name; title = lab title; track line `TRACK: <NAME> · <BPM> BPM · <GENRE>`; flavour + `SIGNATURE: <SIG>.`; buttons `▶ FIGHT` / `BACK` |
| Intro flavours | Ch.1 `Clipboards at the door. Lab coats under the jackets. He checks names. He checks vitals.` · Ch.2 `He got out of the tank. He did not get out of the club.` · Ch.3 `She set the whole night up. Now she wants the last dance.` |
| Intro titles | Ch.1 `HEAD OF DOOR SCIENCE` · Ch.2 `ESCAPED TEST SUBJECT` · Ch.3 `RUNS THE LAB` |
| Fight banners | fight title e.g. `CHAPTER 1` / `VEX — THE FINAL TEST` / `ENDLESS DISCO — <TRACK> · <BPM> BPM` (`2.2` s); `FEVER RUSH!` (`2` s); `★ BEAT DROP FINISHER ★` (`1.5` s); `WAVE CLEAR — DANCE BREAK` (`1.6` s); `WAVE <n> — <bpm> BPM` (`2` s); boss banners (§3.1, §3.3, `2–2.5` s) |
| End screen (win) | tag `STAGE CLEARED`, title `CROWD CONQUERED` |
| End screen (loss) | tag `BEAT DROPPED`, title `KNOCKED OUT` |
| End results (win) | `SCORE: <n> | MAX COMBO: <n>x | PERFECT HITS: <n>` + `STYLE: <rank> (<eff> PTS · <m>/8 MOVES)` + `FANS EARNED: +<n> | FAN BALANCE: <n>` |
| End results (loss) | `FINAL SCORE: <n> | MAX COMBO: <n>x` + `STYLE: …` + `FANS EARNED: …` |
| End buttons | `NEXT CHAPTER →` (story only, chapter < 3) / `↻ PLAY AGAIN` / `HUB` / `TITLE` |
| Hub | tag `Green Room — Lab Break Room`, title `THE HUB`; buttons `CONTINUE →` / `TITLE` |
| Pause | tag `PAUSED`, title `TAKE A BREATH`, desc `THE BEAT IS WAITING. TAP TO JUMP BACK IN.`, button `▶ RESUME` |
| HUD (in fight) | `JAY SLEEZE HP` + HP bar; `FEVER <n>% ★★☆`; `STYLE <rank>` + `<m>/8 MOVES` + style meter; `SCORE <n>`; `<n>x COMBO` (only when combo > 1); beat bar `<bpm> BPM · <TRACK>` + `PARRY OK` / `PARRY <n.n>s` + `DASH OK` / `DASH <n.n>s` + `★ PERFECT WINDOW ★` (in window) or `BEAT SYNC`; bottom bar `HIGH <n>` (high score, outside canvas) |
| Common floats | `PERFECT! -<dmg>` / `GOOD -<dmg>` / `HIT -<dmg>` / `WHIFF` / `KO +<gain>` / `PARRIED! +<gain>` / `PARRIED (OFF-BEAT) +3` / `BLAST PARRIED! +<gain>` / `BLAST PARRIED (OFF-BEAT) +3` / `COUNTER! -20` / `PHASE DASH` / `PARRY STANCE` / `DANCE +8 FEVER` / `★ TOKEN +1` / `SMASH -65!` / `NO TOKENS` / `STRING!` / `DASH STRIKE -14` / `-<dmg>` / `STYLE -25%` |

### 10.1 Fight start / end details

- `beginFight`: player reset to `(240, 410)`, `hp = maxHp = maxHpFor()`, `fever = 0`, `tokens = 0`, all timers `0`, `vx = vy = lungeVx = dashVx = 0`, `dashHitDone = false`; `G.score/combo/maxCombo/perfects/kos/style = 0`, `styleMoves` cleared, `rushT = 0`, `G.speedMul = 1`; `setMove('getup', 1.4)`; banner = fight title, `2.2` s; `spawnTimer = 0.5`.
- Win pose: `setMove('hiphop', beatDur * 8, {loop: true})`. Loss pose: `setMove('knock', 1.2, {hold: true})`.
- `retryFight`: story → back through the intro card (`startStory(ch)`); imported endless → re-run from the decoded buffer in memory at the detected BPM; catalogue endless → `startInfiniteTrack(lastFight.track || 'dceased')`.
- `nextChapter`: story and `chapter < 3` → `startStory(chapter + 1)`.
- Losing the window (`blur`) clears all held keys/pad directions; `visibilitychange` to hidden also pauses.

---

## 11. What CANNOT run on the PS Vita (web-only — must be replaced, not ported)

| Web thing | Why it can't run on Vita | Port replacement |
|---|---|---|
| `localStorage` (4 keys, §7.3) | No browser storage on Vita | File-based save (Godot `user://`, e.g. one JSON per key or a single save file with the same fields) |
| WebAudio `AudioContext` / `OscillatorNode` / `GainNode` synth engine | No WebAudio on Vita | Re-implement the synth in Godot: `AudioStreamGenerator` playing the same per-beat tones (kick 145 Hz sine→42, bass sawtooth, lead square, same vols/durations), or pre-render the 5 tracks' loops as audio files from the same patterns |
| MP3/WAV import (`<input type="file">`, `decodeAudioData`, `AudioBufferSourceNode` loop) + `detectBPM` | No file picker, no decode on Vita — **web-only by design** (stated in code + HANDOFF) | Cut it. Vita endless uses the preset BPM per track in `TRACKS` only. Keep the mode-screen note that import is web-only |
| `pointer` events touch pad + DOM/CSS screens (`scr-title`, `scr-mode`, etc.) | No DOM/CSS on Vita | Godot UI scenes + Vita buttons/touch for the same screens and the same 7-action pad layout |
| `requestAnimationFrame` + `setInterval(5ms)` queue timer | No browser event loop | Godot `_process(delta)` + a timer; the 5 ms audio-clock queue check becomes a per-frame check against the audio clock |
| `document.visibilitychange` / `window blur` tab-out pause | No browser tabs | Vita suspend/focus handling; pause on home-button/suspend |
| `AC.outputLatency` first-run calibration seed | WebAudio-only property | Vita: keep the manual slider + tap-along (both portable); seed from the audio driver's reported latency if Godot exposes one, else default `0` |
| Loading sprites via `new Image()` from `assets/` over HTTP (build needs `python3 -m http.server` to run) | No HTTP server on Vita | Ship the PNGs as Godot-imported textures from the same `assets/` files |
| `performance.now()` loop clock | Browser API | Godot time (`OS.get_ticks_msec()` / `_process` delta) |
| ES6 / CSS `dvh` / `pointer: coarse` media queries | Web-only | N/A — Godot layout instead |
| Skeleton rig ("Raised dead", Pjotr Heinkens, **CC BY-NC**) | Licence: NOT OK for a paid release | **Replace the skeleton art before selling** (also noted in HANDOFF + playtest-notes). All other CC-BY assets must keep their credits in-game (see §10 how-to credits) |
| Pre-rendered club backdrop PNGs (`assets/bg_club_far.png`, `assets/bg_club_lights.png`, baked by `tools/render_club.py` from `map/source/Club.fbx`) | The PNGs themselves are portable files — but the bake pipeline is Python/numpy, and the long-term plan is real 3D for the Vita port | Either ship the two PNG layers as-is, or render the club in 3D on Vita (per HANDOFF plan). Known gap in the source PNGs: far wall is flat grey with no texture; lights layer had a 3 px bright vertical seam at x=469–471, painted black in the PNG |

Portable as-is (data, not web tech): the `TRACKS` patterns, all numeric constants above, the sprite sheets (`assets/sheet_*.png` + `ANIM_SHEETS` meta, §13), the painted fallback sprites (`assets/sprite_*.png`), the two club backdrop PNGs, and the story text.

---

## 12. Not found / no exact value in the web build

These were looked for and are **not** specified as literals in the v7.6 code. Do not invent them — decide them in the Godot build and record the choice here.

1. **Dash total distance**: code gives `700` px/s decaying linearly over `0.32` s → `112` px by integration, but Playwright probes measured **121–123 px** (v7.1 note: "Dash x trace 400,423,453,477,484,502,514,520 (total 121-123px)"). The gap is unexplained in the source; use `700` px/s + the decay formula and re-measure on Vita.
2. **Throw range**: no max range in code — the projectile flies until it hits or leaves `x < 0` / `x > 960`. There is no separate throw cooldown beyond the shared `0.2 / rushSpd` s swing time.
3. **Player post-hit invulnerability**: none. `hurtT = 0.25` s only picks the `hit` clip; it does **not** grant i-frames. Only the dodge window gives i-frames. Successive enemy strikes can hit back-to-back (mitigated only by the one-attacker-at-a-time rule, §3.2).
4. **Enemy contact damage**: none. Enemies only damage via strikes (`resolveStrike`) and rings. Walking into an enemy costs nothing.
5. **Fever Rush "tempo feel +15%"**: the code never changes BPM; the denser drums are extra 16th hits (§8.1). The `+15%` figure appears only in the v7.3 playtest note, not in code.
6. **Per-clip durations**: only the formula `clipDur` (§2.10) exists in code, not a per-clip table. Measured values exist only for punch (`0.36/0.30/0.257` s) and kick (`0.417/0.40/0.343` s) at 100/120/140 BPM (v7.1 note).
7. **VEX `blastT` after a phase-triggered Blast**: `startBlast` resets `blastT = 8`, so the timer restarts after every Blast, phase-triggered or not. (Confirmed in code — listed here only because it is easy to misread.)
8. **No explicit "enemy attack cooldown"** beyond the state machine (windup 0.7–1.0 s + telegraph + strike 0.12 s + recover 0.4 s).
9. **No HP regen** except the endless wave-clear `+15` (capped at max HP). No healing items, no heal on level-up.
10. **Tap-along thumb vs label**: known carried bug — slider thumb shows `45` while the label shows `+47` (playtest-notes, still open). Cosmetic; do not reproduce it.
11. **VEX leg stretch on spin kicks; gangster coat flap in floor moves** — known visual gaps in the source rigs, still open. Not mechanics.
12. **Story/end overlays ghost the previous fight scene faintly behind them** — pre-existing screen-system behaviour, still open.

---

## 13. Animation data (for the port's sprite system)

### 13.1 Sheets (`ANIM_SHEETS`, verbatim meta)

All five sheets share the same clip layout `[startFrame, frameCount]` (16 columns):

| Clip | Frames |
|---|---|
| idle | `[0, 9]` |
| walk | `[9, 14]` |
| punch | `[23, 11]` |
| kick | `[34, 10]` |
| throw | `[44, 11]` |
| windup | `[55, 7]` |
| hit | `[62, 8]` |
| knock | `[70, 12]` |
| getup | `[82, 16]` |
| block | `[98, 6]` |
| upper | `[104, 10]` |
| taunt | `[114, 10]` |
| hiphop | `[124, 24]` |
| headspin | `[148, 8]` |
| flair | `[156, 10]` |
| spinback | `[166, 14]` |
| sweep | `[180, 12]` |
| armada | `[192, 12]` |
| meialua | `[204, 12]` |
| spinflip | `[216, 12]` |

Thug (`thug`) and skeleton (`dead`) sheets only have a subset: idle, walk, punch, kick, throw, windup, hit, knock, upper `[82, 10]`, taunt `[92, 10]` — no getup/block/hiphop/headspin/flair/spinback/sweep/armada/meialua/spinflip.

| Sheet key | Frame w × h | Cols | groundY | anchorX | bodyH | Source file |
|---|---|---|---|---|---|---|
| `psxm` (player) | 243 × 225 | 16 | 216.1 | 108 | 199.9 | `assets/sheet_psxm_player.png` |
| `psxw` (VEX) | 392 × 214 | 16 | 205.1 | 220 | 199.9 | `assets/sheet_psxw_vex.png` |
| `gang` (unused spare) | 233 × 217 | 16 | 208.1 | 106 | 199.9 | `assets/sheet_gang.png` |
| `thug` (stan/bruiser/boss1) | 195 × 209 | 16 | 200.1 | 82 | 199.9 | `assets/sheet_thug.png` |
| `dead` (charger/boss2) | 236 × 232 | 16 | 223.1 | 87 | 199.9 | `assets/sheet_dead_skeleton.png` |

Character→sheet map (`ANIM_CHAR`): player `psxm`, stan `thug`, charger `dead`, bruiser `thug`, boss1 `thug`, boss2 `dead`, vex `psxw`. Setting a type to `null` brings back its painted PNG (`assets/sprite_<type>.png`).

`CLIP_FALLBACK` (for sheets missing a clip): hiphop→idle, headspin→kick, flair→kick, spinback→kick, sweep→kick, armada→kick, meialua→kick, spinflip→kick, getup→idle, block→windup.

- Frame rate for clip timing: ~24 fps (`natural = frames / 24`).
- Idle: ping-pong through the guard frames once per 2 beats, on the beat clock.
- Draw: pixel-snapped position (`Math.round`), scale `h / bodyH`, `shadowBlur 8`, glow colour per type (`GLOW`: player gold, stan `#C9CCD4`, charger red, bruiser purple, boss1 gold, boss2 pink, vex pink). Hit-flash = white silhouette `0.85` alpha; telegraph = red silhouette `0.55` flashing at 10 Hz; stun stars circle the head.
- Player anim priority: `pMove` one-shot > parry (`block`) > hurt (`hit`) > attack (`kick`/`throw`/`punch` by `atkKind`) > dodge (`walk` at `0.35`) > walk-by-distance > idle.

### 13.2 Stage rendering (draw order)

1. Vertical gradient `#090318 → #170836 → #06020D`.
2. Club backdrop PNGs: `bg_club_far.png`, then `bg_club_lights.png` at alpha `0.75 + pulse * 0.25` (Rush: `min(1, 0.85 + pulse * 0.35)`), where `pulse = max(0, 1 - beatOffset()/beatDur)`.
3. 16 EQ bars (beat-reactive, Rush `× 1.6` amplitude).
4. Dancefloor: fill `#0B061A` from y=310; perspective grid, pink `rgba(255,51,204, 0.22 + pulse*0.25)`, horizontal lines every 36 px from y=310 to 490, converging verticals.
5. Entities sorted by Y; corpses (knock clip, fading) → dash ghosts → fighters → slashes → projectiles → rings → impact rings → particles → floats.
6. HUD: HP box `(14,14,270×56)`, style box `(14,78,270×36)`, score top-right, beat bar `y 496–544`, banner pill `y 120–162` (width grows to fit text, font shrinks 20→12 as backstop), telegraph markers last (never covered by the banner).

---

## Sources

- `~/workspace/games/sleeze-disco-v7/sleeze-disco-master/index.html` — read in full (2,459 lines)
- `~/workspace/games/sleeze-disco-v7/sleeze-disco-master/HANDOFF.md`
- `~/workspace/games/sleeze-disco-v7/sleeze-disco-master/ROADMAP.md`
- `~/workspace/games/sleeze-disco-v7/sleeze-disco-master/playtest-notes.md` — Rounds 4–9 (v7.1–v7.6)

Spec written Nov 12, 2026, from web build v7.6. No files under `sleeze-disco-master/` were modified.
