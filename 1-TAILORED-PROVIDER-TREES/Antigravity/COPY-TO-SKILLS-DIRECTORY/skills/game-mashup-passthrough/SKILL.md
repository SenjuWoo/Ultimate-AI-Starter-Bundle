---
name: game-mashup-passthrough
description: Use when making game A show game B's characters, models or effects inside A (a mashup, cross-engine character swap, or companion renderer drawn over a host game), or when a host-mod needs bone reads, a pre-UI draw hook or a ReShade add-on.
---

# Game mashup by passthrough

Start-up checklist for "make game A show game B's stuff", from a project that
reached a working in-game lab build. The settled technical results (offsets,
UE4SS fixes, retargeting, HUD split) live in
`project-intel/references/game-mashup-melty.md`: load that card next. Engine
routes and per-game recon come from `universal-modder` (`mashup-mods` guide).
This skill is the order of work and the guardrails; it does not select Melty or
any publishing platform (publishing is a separate, explicit request).

## Pick the route (a wrong pick costs days)

1. Passthrough first: the host keeps AI, physics, animation and hitboxes; a
   script mod names which body to draw; a companion renderer draws the other
   game's model skinned to the host's live skeleton. Assets come from the
   player's own installs into a local cache; nothing from either game ships.
2. Loading foreign cooked assets into the host is a dead end (engine-version
   mismatch, no runtime mesh API, Unity content can never load in Unreal).
3. Check anti-cheat and DRM before anything else. An injected passthrough is
   not a candidate for a protected online title. A purely client-side cosmetic
   route may be tolerated; verify the publisher's current policy and warn about
   the account risk. Never bypass or disable anti-cheat or DRM.
4. Exclude censored variants and any child-like or age-ambiguous character by
   name before extraction, not after.

## Order of work

1. Recon the companion tree with grep and counts; record them in the project.
2. One-page design with goals, non-goals and anti-goals; the owner signs off
   before code.
3. Spike the two unknowns first: the host's draw/UI split, and decoding the
   companion's animation clips (it decides how much animation you get).
   Both were proven or killed fast once attacked directly.
4. Oracle before renderer: export one asset and render it headless (Blender
   `-b --factory-startup`) so "extraction is wrong" and "renderer is wrong"
   stay separable.
5. Build the add-on command file (screenshot, dump, reload, test-pose) before
   the first feature. Prove one trivial native call and one screenshot first.
6. Every phase ends with an in-game shot plus a log line, committed locally.
   Never push or publish until the owner says they are satisfied.
7. Keep `STATE.md` and a mod log current; pack with `git archive` + `git bundle`.

## Rules that cost sessions when ignored

- Discover offsets and layouts at runtime, vote across actors, log the choice;
  a game patch should fail loudly. Never reuse another build's numbers.
- A live probe that freezes or teleports AI needs a paired unfreeze, always.
  Never leave AI frozen while the owner plays; aggro'd AI ignores teleports,
  so frame shots with a rest-pose command instead.
- Trace the host frame (render-target binds, copies) before designing HUD
  handling. Drawing as a present-time overlay covers the UI.
- Extraction is manifest-driven, one item at a time. A first pass that loaded
  everything peaked at 9.7 GB and crashed the host; the fix peaked near 0.4 GB.
- Check a dependency's advisories before adding it, and never run a text
  clean-up tool over a virtualenv.
- Keep agent subtasks small and commit at each sub-step; a rate-limit stop
  mid-task left half-written files once.
- Verify with evidence the owner can't argue with (screenshot plus log line, or
  a diff image) and say what was checked and what was not.

## Windows shell traps seen here

- Git Bash rewrites a bare `/` argument into a Windows path; pass a name such as
  `Content` instead. Piped CRLF output needs `tr -d '\r'` before grep.
- Run CMake/Ninja/MSVC builds from PowerShell; `cmd //c` from Git Bash failed on
  path escaping. `python` in Git Bash may be the Store stub: use the project's
  `.venv` interpreter or `py -3`.
- ReShade copies of a changed `.fx` do nothing until a reload command runs.
