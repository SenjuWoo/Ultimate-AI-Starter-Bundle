# Systems, assets and playtests

## Game systems architecture

- **Modular by feature.** One owner per system (movement, combat, inventory, save). A shared
  god object is where saves and networking go to die.
- **Data-driven content.** Stats, items, spawn tables and dialogue in data files with a
  schema; code reads data, designers edit data. Validate on load and fail loudly.
- **State machines.** Explicit states and transitions for anything with modes: player,
  enemy, UI, game flow. Log the transition on error; no implicit flags.
- **Events.** Publish what happened, not what to do. Keep the payload small enough to
  serialize for saves and replays.
- **Determinism where it matters.** Fixed timestep for simulation, seeded randomness for
  replayable procgen, and recorded inputs for reproducible bugs.
- **Asset ownership.** Every prefab, material and table has one owner path. No duplicate
  copies per level; variants belong to the base asset.
- **Configuration.** Separate build, user and save config. Never let a user setting change
  gameplay balance silently.
- **Save compatibility.** Version the save, migrate forward, never overwrite an unreadable
  save without a backup. Test loading a save from the previous release.
- **Networking boundaries.** Server owns authoritative state; clients predict and reconcile.
  Keep the boundary in one place, not scattered through gameplay code.
- **Update scheduling.** Split frame-critical, periodic and idle work. A shared tick for
  everything is the usual cause of spikes.

## Asset production

- **Geometry.** Target silhouette and texel density, not polycount vanity. Clean normals,
  no hidden faces, consistent pivot and scale (1 unit = 1 metre unless the engine says otherwise).
- **UVs.** No overlapping UVs on baked assets; consistent lightmap UV channel; check seams
  at the actual camera distance.
- **Materials.** Reuse a small master set. Unique materials multiply draw calls and shader
  variants; instance parameters instead.
- **Textures.** Power-of-two where the engine prefers it, correct colour space (albedo sRGB,
  data linear), mipmaps on, compression chosen for the target platform.
- **Rigging and animation.** Consistent skeleton naming, root motion decided once, animation
  compression that preserves contact and weight. Check loops and transitions.
- **Source files and provenance.** Keep editable sources, record the licence and origin, and
  never ship an asset the operator cannot account for.
- **Validation.** A pass/fail check per asset class: scale, pivot, material count, texture
  size, collision, LOD chain. Fail the import, not the player.

## Playtesting and quality

- **Real gameplay verification.** A screenshot is not a playtest. Play the critical journey:
  start, first objective, first failure, recovery, save, reload, quit.
- **Automated scenarios.** Script the repeatable parts: spawn, move, fight, die, respawn,
  load save. Assert state, not pixels, where possible.
- **Performance benchmarks.** Same scene, same device, same settings, three runs; report the
  median and the worst frame, not the average alone.
- **Device profiles.** Lowest supported device is the real target. Test a mid device and the
  developer machine for comparison.
- **Stress tests.** Spawn caps, particle storms, network loss, full inventory, longest save.
- **Regression checks.** Keep a short smoke list that runs after every change: boot, load,
  move, interact, save, quit.
- **Evidence.** Record build, device, scene, before/after and the exact change. An
  unrecorded improvement will be re-litigated next month.
