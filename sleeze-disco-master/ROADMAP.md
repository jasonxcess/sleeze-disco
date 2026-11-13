# SLEEZE DISCO — Beat Kune Do · Roadmap (owner: Shawn "Sleeze" Jackson, Nov 12, 2026)

Source of truth: this file + HANDOFF.md + playtest-notes.md. Keep the original art,
the PSX low-poly look, the neon style, and the 960x544 canvas. Final target is a
PS Vita VPK — keep the systems simple enough to port.

## PHASE 1: FIX THE FEEL (do this before anything new) — SHIPPED as v7.1, Nov 12, 2026
- Movement has weight: acceleration and deceleration, attack lunges, knockback arcs,
  hit-stop of 40 to 80 ms on impact, screen shake on heavy hits
- Kill the enemy jitter: drive the walk cycle by distance, add a facing deadzone,
  smooth AI velocity
- Every attack reads as anticipation, contact, recovery. Less floaty glow

## PHASE 2: FREE-FLOW RHYTHM COMBAT — SHIPPED as v7.2, Nov 12, 2026
- Arkham/Sifu-style crowd fighting: tap toward an enemy and Sleeze closes the distance;
  counter prompts over enemies about to strike
- Everything lands on the beat: punch, kick, dodge, parry
- Forgiving timing: off-beat inputs snap to the nearest beat instead of failing.
  Hitting the PERFECT window gives bonus damage, more style score and extra VFX
- Style rank (D, C, B, A, S, SLEEZE) that rises with variety and timing and drops
  when you get hit
- NOTE (decided in v7.2, per the owner's rule): the round-1 MISS rule is RETIRED
  for player attacks — off-beat swings snap to the next beat and still land at
  full damage; the combo breaks when you get hit, not from off-beat inputs. MISS
  survives only as a parry-press judgement (off-beat parry pays +5 meter instead
  of +200). Parry and dodge fire instantly on press, never queued — a telegraph
  can end before the next beat.

## PHASE 3: FEVER AND TAKEDOWNS — SHIPPED as v7.3, Nov 12, 2026
- On-beat hits and pure dance moves (no damage) build a Fever Meter
- Fever Rush: a few seconds of rapid drumstick combos, faster BPM feel, crowd lights
  go wild
- Takedown tokens earned from combos trigger short cinematic finishers (headspin,
  flair and the other dance moves already in the sheets)
- Shipped shape: Fever gains PERFECT +12 / GOOD +7 / plain HIT +0 / dance +8 /
  counter +10 / clean parry +15 / off-beat parry +3 / KO +6; Rush auto-starts at
  100 Fever, lasts 8 beats, attacks 30% faster, denser drums, wild lights, Fever
  drains 100 → 0; tokens 1 per 12 combo, max 3, E spends one for a 65-damage
  finisher with ~0.15s slow-mo. 53/53 probes green, zero errors.

## PHASE 4: STORY (OURS, NOT ANYONE ELSE'S) — SHIPPED as v7.4, Nov 12, 2026
- Sleeze meets his girl Vex at the club. It's a setup: the club is a lab, the
  bouncers are scientists, the skeletons are her earlier dates. He's the next
  experiment and has to fight and dance on the beat to get out. Tone: comedic
- Bosses are the lab's lead scientists and test subjects, each with its own music
  genre. Beating one unlocks its signature move or power for Sleeze
- Vex is the final reveal
- Shipped shape: Ch.1 DR. CLIPBOARD (funk 100, Rope Sweep ring, unlocks DASH
  STRIKE), Ch.2 SUBJECT SEVEN (house 120, Triple Tap chain, unlocks SPINBACK
  KICK), Ch.3 VEX (dark disco 140, Spotlight Blast, story exchange before the
  fight). Intro card per chapter, unlocks persist in localStorage
  (sleezeDiscoUnlocksV1), genre bass/lead pattern per chapter. 59/59 probes
  green, zero errors.

## PHASE 5: HUB AND PROGRESSION — SHIPPED as v7.5, Nov 12, 2026
- Between stages: a back-room hub (the club's green room / lab break room)
- Spend fan currency earned in fights on skill unlocks, new combos, health upgrades
  and fits (cosmetics)
- Shipped shape: fans = floor(score/100) + 2 per KO (story and endless, win
  and loss), shown on the end screen, persisted in localStorage
  (sleezeDiscoSaveV1); hub reachable from the title (GREEN ROOM) and the end
  screen (HUB), CONTINUE returns to where it opened from; shop is +25 MAX HP
  (50 fans, repeatable), +1 token slot (80 fans, cap 5), Faster Fever Gain
  ×1.5 (60 fans, one-time), combo string punch-punch-kick (100 fans,
  one-time, 1.5× ender with spinback clip), gold/red/cyan jacket tints
  (40 fans each, buy then equip). 50/50 probes green, zero errors.

## PHASE 6: MUSIC — SHIPPED as v7.6, Nov 12, 2026
- Soundtrack built on the owner's own tracks (SleezeTeamJason, KeysByJason) so it's
  streamer-safe from day one — My Luva (100, funk), Big Screen (110, funk),
  DCeased (120, house), Fool Me Once (130, house), Shit Talkin (140, dark
  disco), each a BPM preset with its own bass/lead patterns on the synth
  engine. Chapters: Ch.1 MY LUVA, Ch.2 DCEASED, Ch.3 SHIT TALKIN
- Endless mode: pick any of the five tracks, or import your own MP3/WAV —
  BPM detected on the file (onset envelope + autocorrelation, 80–180 BPM),
  verified 120.1 on a 120 BPM click track and 99.6 on a 100 BPM one; the
  file loops as the backing track, synth muted, beat clock untouched.
  Web build only; on the Vita use preset BPM per track

## RULES
- Ship each phase as a playable build and list what changed
- Don't copy names, characters or story from Dead as Disco or any other game
- Keep the credits screen updated for every CC-BY asset
- Flag anything that won't run on the Vita

## STATUS LOG
- Nov 12, 2026: Phase 1 in progress (v7.1 build — movement weight, jitter kill,
  tighter timing, less bloom, plus a first pass at the club backdrop from map/).
  Phases 2–6 queued in order. Each ships as its own playable build.
- Nov 12, 2026: Phase 1 SHIPPED as v7.1 — 37/37 probes green, zero errors.
  Phases 2–6 queued in order. Each ships as its own playable build.
- Nov 12, 2026: Phase 2 SHIPPED as v7.2 — gap-closer, COUNTER prompts, snap-to-
  beat with the MISS rule retired for attacks (MISS survives only as a parry-press
  judgement), style rank D/C/B/A/S/SLEEZE with variety multiplier, Idol naming
  removed ("CH.3 VEX", "VEX — THE FINAL TEST"). 50/50 probes green, zero errors.
  Phases 3–6 queued in order. Each ships as its own playable build.
- Nov 12, 2026: Phase 3 SHIPPED as v7.3 — Takedown meter became Fever (PERFECT
  +12 / GOOD +7 / HIT +0 / dance +8 / counter +10 / clean parry +15 / off-beat
  parry +3 / KO +6), Fever Rush auto-starts at 100 for 8 beats (attacks 30%
  faster, denser drums, wild lights, drains 100 → 0), takedown tokens 1 per 12
  combo max 3, E spends one for a 65-damage finisher with ~0.15s slow-mo. 53/53
  probes green, zero errors. Phases 4–6 queued in order. Each ships as its own
  playable build.
- Nov 12, 2026: Phase 4 SHIPPED as v7.4 — lab bosses DR. CLIPBOARD (funk 100,
  Rope Sweep, unlocks DASH STRIKE) and SUBJECT SEVEN (house 120, Triple Tap,
  unlocks SPINBACK KICK), VEX final reveal (dark disco 140, 4-line story
  exchange), intro cards per chapter, unlocks persist in
  sleezeDiscoUnlocksV1, per-chapter genre patterns. 59/59 probes green, zero
  errors. Phases 5–6 queued in order. Each ships as its own playable build.
- Nov 12, 2026: Phase 5 SHIPPED as v7.5 — fan currency (floor(score/100) +
  2 per KO), Green Room hub with the five-item shop (HP, token slots, Fever
  ×1.5, combo string, jacket fits), everything persisted in
  sleezeDiscoSaveV1. 50/50 probes green, zero errors. Phase 6 queued.
  Each ships as its own playable build.
- Nov 12, 2026: Phase 6 SHIPPED as v7.6 — the owner's own tracks as the
  soundtrack (TRACKS table replaces GENRE_PAT: My Luva 100 funk, Big
  Screen 110 funk, DCeased 120 house, Fool Me Once 130 house, Shit Talkin
  140 dark disco; chapters run MY LUVA / DCEASED / SHIT TALKIN), endless
  track picker, MP3/WAV import with a from-scratch BPM detector (onset
  envelope + autocorrelation, 80–180 BPM; 120.1 detected on a 120 BPM
  click track, 99.6 on a 100 BPM one), imported file loops as the backing
  track with the beat clock untouched. 27/27 phase + 28/28 regression
  probes green, zero errors. All six phases SHIPPED.
