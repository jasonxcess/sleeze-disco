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

## How to contribute a fix

Pick an open issue, work on its branch, and describe the change precisely:
what files changed, why, and what was verified. If you cannot run the build,
say so — the integrator will build and test it. A fix that cannot be verified
does not ship.
