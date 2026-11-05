# Fidelity and performance

## Perceptual fidelity

Detail is a budget spent where the player looks.

- **Screen-space importance.** Cost should track pixels covered, not object count. A hero
  weapon fills a third of the screen; a crate behind the camera costs nothing.
- **Importance tiers.** Give every asset a tier (hero, gameplay, background, set dressing).
  Tier sets resolution, LOD count, shadow casting, update rate and cull distance.
- **LOD and HLOD.** Author LOD transitions around the distance where the silhouette stops
  changing. Check the transition at gameplay speed, not on a still. HLOD or merged proxies
  for distant clusters; never let a visible pop read as a bug.
- **Culling.** Frustum first, then occlusion. Occlusion is worth it only when large opaque
  blockers exist; verify with the camera moving, not a static view.
- **Streaming.** Separate render distance from simulation distance from network interest.
  Preload what the next 30 seconds needs; a hitch at a doorway is a streaming plan failure.
- **Impostors and billboards.** Use for distance and crowds; keep lighting response coherent
  or the swap reads as a style break.
- **Mipmaps and aliasing.** Mipmaps are not optional. Check texture detail at distance and
  at grazing angles; shimmer means the mip chain or the sampler is wrong.
- **Adaptive quality.** Scale the cheapest visible knobs first (shadow distance, particle
  count, resolution scale) and keep gameplay feedback constant. Show the player nothing
  about the downgrade unless they ask.

## Performance engineering

Frame budget first, then profile, then change one thing.

- **Budget.** Pick the target device and frame rate, divide the frame: e.g. 16.6 ms total
  split across game logic, physics, animation, render thread and GPU. Write it down
  (template: technical performance budget).
- **Measure.** Use the engine profiler and GPU capture; record scene, device, build and
  settings with every number. A change without a matching before/after is unverified.
- **Draw calls and batching.** Merge static geometry, instance repeats, atlas materials,
  and cut unique shader variants before touching polycount.
- **Overdraw.** Transparent layers, particles and full-screen effects stack. Check with the
  engine's overdraw view; a full-screen blur behind an opaque HUD is pure waste.
- **Instancing.** Crowds, foliage, props: one material + per-instance transform beats many
  unique meshes with the same look.
- **Memory.** Track texture, mesh, audio and animation budgets separately. Streaming
  reduces resident memory but shifts cost to IO; test the slowest supported storage.
- **Physics.** Fixed timestep, sleep bodies, layer filtering, and simplified collision for
  props. Never simulate what the player cannot touch.
- **AI and updates.** Stagger decisions across frames; distance-based tick rates; keep
  critical behaviour (combat, navigation) at full rate.
- **Network.** Replicate state, not every frame; interest management per player; predict
  locally and reconcile. Never let a network optimization desync gameplay.
- **Loading and pooling.** Pool bullets, effects and crowds; watch GC or allocation spikes
  in the profiler, not in theory.

## Choosing what to cut

Cut in this order unless measurement says otherwise: invisible simulation, overdraw,
unique materials, shadow casters, particle counts, distant LODs, then resolution scale.
Never cut: hit feedback, danger telegraphs, input responsiveness, or the readability of
the critical path.
