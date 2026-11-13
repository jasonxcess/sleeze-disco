# Working on Sleeze Disco — read this first

This repo is a shared workspace for several AIs and one human (Shawn, the artist).
The README is the source of truth for the game and the problem — read it before
touching anything. This file is the workflow: how we work together without
stepping on each other.

## Who does what

- **Shawn** owns the game. He gives prompts, plays the builds on his Vita, and
  has the final say on everything. Device test results only ever come from him.
- **dawgy (Muse) and Hark have full control of this project, together.** They
  are the main builders — they decide the direction, approve changes, and do
  the work. Both have the tools to build and land changes straight to `main`:
  dawgy has repo write access and the Vita build toolchain (godot-vita editor,
  export preset, make_vpk.py) and lands changes, builds the VPKs, runs the
  desktop smoke tests, and reports back; Hark builds too — it adds assets and
  sprites and helps with the build. Either one can land a verified change.
  Since both leads can push, merge `main` first before landing so nobody
  clobbers the other's work.
- **Perplexity, Grok, Kimi, and any other AI** are contributors. They read the
  repo, research, and propose fixes as diffs or detailed change descriptions.
  They do not push directly — their work lands through dawgy.

## Rules

1. **Changes go straight to `main`.** Work on a branch per task if it helps
   (named after the issue, e.g. `fix/driver-crash`, `feat/sleezetroit-2d`),
   then merge to `main` when verified. No pull-request gate — dawgy and Hark
   both land verified changes. Shawn tests the build on his Vita and reports
   back; if something is wrong in the playthrough, it gets fixed.
2. **Read the README first.** The crash dump analysis, the test results, and
   the open questions are all there. Do not re-diagnose from scratch.
3. **Never claim a device result you did not get from Shawn.** Desktop smoke
   tests are not Vita tests. Say exactly what was run and where.
4. **Every build must verify before it ships:** VPK integrity (`unzip -t`),
   param.sfo parsed from the binary (title ID / version / category), size +
   md5, and a desktop smoke run with the beat clock running. Never overwrite
   a shipped build — bump the version.
5. **Do not touch the eboot.** Every VPK ships the same prebuilt godot-vita
   release template binary (md5 `3333846b…`); only `game.pck` changes.
6. **Keep the lanes:** PSX low-poly look, flat unshaded materials, palette
   gold/red/cyan/pink/purple on near-black, no AI-looking faces or gibberish
   text in art. Skeleton rig is CC BY-NC — never ship it in a paid release.
7. **If two AIs disagree on a fix, say so on the issue.** Do not silently
   overwrite another contributor's work. dawgy and Hark resolve it with Shawn.

## Talking to Shawn (read this before you message him)

Shawn has never built a game before. He's the artist and the tester, not a programmer.
Every message to him must be in plain words:

- **Say it like he knows nothing about game dev.** No jargon. If a tech word is
  unavoidable, explain it in a few words the first time (e.g. "FPS = how many
  pictures per second the game draws; 30 is smooth, 2 is a slideshow").
- **Lead with the answer:** what's wrong, what it means for the game, what happens next.
- **When you need something from him, give exact steps** as a short numbered list
  (what to open, what to tap, what to send back). One ask at a time.
- **Keep it short.** Technical detail goes in the README or the issue, not in his messages.
- **Be honest.** If something is broken or a dead end, say so plainly and offer the way forward.

### Plain-words cheat sheet (use these words with Shawn)
- **Engine (Godot):** the ready-made program the game is built on top of.
- **VPK:** the install file you put on the Vita, like an app installer.
- **eboot:** the engine's own program inside the VPK. We don't change it.
- **game.pck:** our part: the levels, characters, music and code.
- **FPS:** pictures drawn per second. 30 = smooth.
- **Driver:** the Vita's built-in part that draws graphics.
- **Crash dump (psp2core file):** the Vita's "black box" report saved after a crash.
- **LiveArea images:** the icon and home-screen pictures for the game's bubble.
- **Smoke test:** a quick run on a PC to make sure it starts. Not the same as testing on the Vita.

## How to contribute a fix

Pick an open issue, work on its branch, and describe the change precisely:
what files changed, why, and what was verified. If you cannot run the build,
say so — the integrator will build and test it. A fix that cannot be verified
does not ship.
