# Sleeze Disco — quality bar (standing rules, Nov 12 2026)

These are Shawn's rules for everything built on this game. If a line of
code, a spec, or a piece of text breaks one of these, it doesn't ship.
Check new work against this file before calling it done.

## 1. No AI tells

Banned words, everywhere — code comments, docs, dialogue, UI text:
`delve`, `tapestry`, `beacon of hope`, `testament`, `unbeknownst`,
`embark`, `in the realm of`, `landscape of`, `nestled`, `elevate`.

Nobody in this game announces how they feel. Jay doesn't say "I am
angry." He shows up late, jaw tight, and swings first. Dialogue is
short, specific, and sounds like Hawthorne — slang, half-sentences,
interruptions, people talking past each other. No wiki voice, no
corporate voice, no narrator explaining the theme. Flaws stay in.
Nobody is noble for free.

## 2. Game feel is not optional

Nothing floaty, nothing generic. Every system has weight:

- **Hit-stop:** 40 ms freeze on every landed hit (`Engine.time_scale = 0`).
  The music keeps playing — the rhythm clock is the audio clock.
- **Input buffering:** jump buffer 120 ms, coyote time 100 ms. A press
  a hair early still lands.
- **Variable jump:** release early, jump short. Hold it, jump full.
- **Attack easing:** lunge is a sine curve — out fast, back slow.
  No linear slides.
- **Dodge:** 220 ms of i-frames, fixed distance, 550 ms cooldown.
  It commits. You can't cancel out of it.
- **Beat bob:** idle breathes on the beat (`beat_phase01()`), so the
  whole screen is on the music even when nobody is swinging.
- **Snap-to feedback:** hits flash the enemy red for 120 ms, sparks
  fly, the HUD pops the judgement big. A PERFECT looks and sounds
  different from a GOOD. A MISS still lands — it just doesn't build
  the combo.
- **Combo:** 1x–4x, built on rhythm success only. Four clean hits per
  tier. One MISS or one hit taken and it's gone.

Vita limits are the frame, not an excuse: no per-frame allocation,
fixed pools, 60 Hz physics, preallocated everything. If a feature
needs the hardware to try harder, the feature gets cut, not the
frame rate.

## 3. One look, no whiplash

- **Palette (flat, unlit, exact):** gold `#FFC83C`, red `#E63232`,
  cyan `#3CDCFF`, pink `#FF50B4`, purple `#9650FF`, white, near-black
  `#05010D`. Nothing else on screen unless a background earns it.
- **Unlit only.** No lights, no PBR, no shaders, no dynamic shadows.
  Ever.
- **Shadows are baked circles** under each fighter. They shrink and
  fade as the fighter jumps. That's the whole lighting model.
- **Sprites:** power-of-two, max 1024x1024. Fighters 256x512. FX
  textures 64x64. Backgrounds 960x544 JPG.
- **Particles:** max 50 per effect, hard cap. One pool, recycled.
- **People look like people.** Real cutouts of Jay, palette-swapped
  for enemies, or clean vector shapes. No AI-looking faces, no
  extra fingers, no gibberish text baked into art. If a sprite
  looks wrong on a real screen, it gets redrawn, not explained away.
- **Text:** DejaVuSans-Bold only, white or palette colour, no
  drop-shadow soup. If the HUD isn't readable over the background
  at a glance, the background gets dimmed, not the text enlarged.

## 4. Before anything ships

1. Run it in real Godot 3.5.3 headless — zero errors, not "only
   warnings."
2. Play the 30-second song start to finish. Beat pulse and music
   stay together the whole way.
3. Read every new line of text out loud. If it sounds like a
   press release, rewrite it.
4. Check the VPK size and the VRAM budget (under 80 MB active).
   If it grew, say what grew and why.
