# SLEEZE DISCO — Beat Kune Do · Master Source (v7, Nov 12, 2026)

Owner: Shawn "Sleeze" Jackson (@sleezejason). Neon on-beat brawler. You fight and dance to the beat.
Run: open `index.html` from a local web server (`python3 -m http.server`), because the sprites load from `assets/`.
Canvas: 960x544, the PS Vita resolution. Touch pad plus keyboard. Final target is a PS Vita VPK (PCH-2000, HENkaku Ensō). The browser build can't run on the Vita, so the port has to be native (LÖVE Potion/Lua recommended, or C with vitaSDK).

## Story (owner's concept)
Sleeze meets his "girl" (Vex) at the club. It's a setup: the club is a lab, the bouncers are scientists, and the skeletons are earlier dates. He becomes a science project and has to fight and dance to the beat to get out. Tone: comedic.

## Files
- `index.html`: the whole game (HTML, CSS, JS, one file). Main sections: screens (title, how-to, end), beat clock (`bpm`, PERFECT window ±0.065 s), player moves (punch J, kick K, throw L, dodge Space, parry S, finisher E), enemy types (stan, charger, bruiser, vex), waves and endless mode with an 8-beat dance break.
- `assets/sheet_*.png` + `ANIM_SHEETS` in index.html: pre-rendered 3D sprite sheets. Meta per sheet: w, h, cols, clips {name:[start,count]}, groundY, anchorX, bodyH.
  Clips: idle, walk, punch, kick, throw, windup, hit, knock, getup, block, upper, taunt, hiphop, headspin, flair, spinback, sweep, armada, meialua, spinflip. (The thug and skeleton sheets only have a subset; see `CLIP_FALLBACK`.)
- `ANIM_CHAR` maps each fighter type to a sheet. Setting a type to null brings back its painted PNG (`assets/sprite_*.png`, the owner's original art).
- `tools/`: Python pipeline (numpy software renderer) that bakes rigged FBX/.blend + Mixamo FBX clips into those sheets. bake2.py = base clips, bake3.py = Mixamo clips, pack2.py = sheet packer, psx.py = the PSX models (.blend parser).
- `map/`: the club stage, "Night Dance Club Lowpoly" (source/Club.fbx + textures: DJSet, Interior, Spotlight, Tile, neon). It isn't in the game yet; the current stage is a drawn neon skyline and grid. Plan: render it as the backdrop (pre-rendered layers for the HTML build, real 3D for the Vita port). The DJ booth fits the lab twist.
- `playtest-notes.md`: every playtest round and fix so far.

## What the owner wants fixed NEXT (his words, Nov 12, 2026: "weak ass movement, enemies shaking when moving, feels corny")
DONE — shipped as v7.1, Nov 12, 2026. Full list + probe results (37/37 checks, zero errors) in playtest-notes.md, "Round 4 — v7.1".
1. Movement weight — DONE: velocity-based accel/decel, hit-stop 40/80ms on every hit, shake on heavy hits, knockback velocity arcs, dash with ghosts + i-frames, attack lunges.
2. Enemy jitter — DONE: walk cycle by distance, 24px facing deadzone, lerped AI velocity, single-point pixel snap, separation capped 2px/frame.
3. Less corny — DONE: beat-fitted clips + windup anticipation, impact rings on the beat, shadowBlur cut 18/22 → 8. Neon look kept. Club backdrop landed as pre-rendered layers (tools/render_club.py → assets/bg_club_far.png + bg_club_lights.png).
Rules: keep his original art and the PSX low-poly look. No generic AI-looking art.

## Asset licenses (credits must ship in-game; the line is on the How-to screen)
- PSX Graphics | Low Poly Woman (Vex): murilo.kleine, CC BY 4.0
- PSXprop - Male Character 02 (Sleeze): WardsterSAW, Sketchfab Free Standard
- Enemy1 (thug): bumstrum, CC BY 4.0
- Raised dead (skeleton): Pjotr Heinkens, CC BY-NC. NOT OK for a paid release; replace it before selling.
- Night Dance Club Lowpoly (map): 00amza, CC BY 4.0
- Motion: Adobe Mixamo (free to use in games)
- Soundtrack (P6): SleezeTeamJason — My Luva, DCeased, Shit Talkin, Big Screen, Fool Me Once. The owner's own tracks, rebuilt as synth patterns (no licensed recordings, no new credited assets). The How-to screen carries the credit line.

## Music system (P6, v7.6)
- `TRACKS` in index.html is the one pattern system (it replaced the P4 `GENRE_PAT`): five tracks, each a BPM preset + its own bass/lead pattern, played by the synth engine. Chapter map (in `BOSS_INFO[].track`): Ch.1 MY LUVA (funk 100), Ch.2 DCEASED (house 120), Ch.3 SHIT TALKIN (dark disco 140). Intro cards show the track; the beat bar shows `BPM · TRACK NAME` in fights.
- Endless: pick any of the five tracks on the mode screen, or import your own MP3/WAV. The file is decoded (`decodeAudioData`), the BPM is read by `detectBPM` (onset envelope + autocorrelation, 80–180 BPM, written from scratch, no libraries), the detected BPM shows with a confirm button, and the file then loops as the backing track (`AudioBufferSourceNode`, started on the beat grid, looped on a whole number of beats) while the synth tones stay muted and the beat clock runs untouched. No BPM ramp on wave clears for an imported run; retry re-runs it from the decoded buffer in memory. A bad file shows an on-screen error and falls back to the synth tracks — never a crash, never a wrong BPM. Latency slider + tap-along calibration apply exactly as on synth tracks.
- Detector accuracy (real generated audio through `decodeAudioData`): 120 BPM click track (MP3) → 120.1; 100 BPM click track (WAV) → 99.6.
- VITA: the import is web-only by design — no file picker, no decode on the Vita. The Vita build uses the preset BPM per track in `TRACKS`, exactly like the story chapters do here. The synth engine, the beat clock and the judge windows are the same code either way, so the port carries the music system over with the patterns as data.
