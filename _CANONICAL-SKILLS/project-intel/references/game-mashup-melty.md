# Game mashups by passthrough (and Melty) — settled results

> Scope: mashup and cross-engine fusion work only. An ordinary single-game mod
> belongs to its game card (`skyrim-modding.md`, `game-modding-other.md`);
> nothing here says to put mods in a Melty folder. The order of work and the
> guardrails are in the `game-mashup-passthrough` skill; this card holds the
> technical results behind it. Updated 2026-10-21 with the project's full
> lessons file (frame split, spikes, mistakes).

Case: the operator's first Melty mashup (2026-10): a UE 4.25-derived shipping
game as host, a UE 4.27 game and a Unity 2018.2 Mono game as companions, solo
only. Status when written (2026-10-14): working in game on one lab build, not
released. Evidence is "verified in game on one build" unless a line says more.
The project's own `STATE.md`, `MODLOG.md` and `docs/HOW-IT-WAS-MADE.txt` hold
the detail and stay private; the operator's profile lists where they live.

Lesson format used here and in every card: **workflow/build → tried → result →
cause → what worked → evidence → recheck when**. A bare "X does not work" is not
a lesson; it only holds for the workflow it was observed in.

## Pick the route first (a wrong pick costs days)

| Idea | Verdict | Why |
|---|---|---|
| Load the companion's cooked assets as real engine assets in the host | Rejected | Cooked assets are tied to the engine version (4.27 content into a 4.25 host); the host had no runtime mesh builder; Unity assets can never load in Unreal. |
| Run the games side by side and stream state | Rejected | Only the character models are needed, not the other games running. |
| **Passthrough renderer** | Chosen | The host keeps AI, animation, hitboxes and ragdoll. A script mod hides the host mesh and names the body to draw; a native overlay draws the companion body skinned to the host's live skeleton, depth-tested against the host's depth buffer; a one-time extractor builds a local cache from the **player's own installs** (nothing from any game ships). |

Guardrails that decided scope: check anti-cheat first (an injected overlay is
not a candidate for a protected online title; a purely client-side cosmetic
route still needs the publisher's current policy and the user's informed
acceptance); never touch or bypass DRM; solo only (other players would
not see the bodies); exclude censored variants and any child-like or
age-ambiguous character by name.

## The pieces

Script mod (UE4SS Lua): classifies actors by class path, hides meshes and attached
props, runs gameplay (meter, buffs, music choice), writes a bridge file.
Overlay (native D3D12 add-on): reads bone transforms from game memory, retargets,
GPU-skins, depth-tests, plays audio, simulates secondary motion. Extractor
(.NET): CUE4Parse for UE paks, vendored AssetStudio for Unity, writes its own
simple mesh/texture/audio cache. Data sheets compiled by a script; debug log and
a hang watchdog switchable from the ini.

## UE4SS on a modified UE 4.25 shipping build

- Stock UE4SS → crash at start in the object-array delete listener → the host's
  `FUObjectArray` layout differs → measure it live, override in
  `MemberVariableLayout.ini`.
- Every Lua call into a game function silently did nothing (`Add(2,3)` gave 0) →
  one vtable entry fewer before `ProcessEvent`; UE4SS called the neighbouring
  slot → `VTableLayout.ini` override. **Prove one trivial native call returns the
  right value before building anything on it.**
- After a reboot UE4SS died at init on a garbage FName-alignment value → one
  unchecked store read garbage on this build → binary-patch that one store so it
  falls back to the default; ship the patched DLL and record its hash. Melty adds
  its own UE4SS loader: check it does not overwrite the patched DLL in
  `test_release`.
- Hooks on LoadMap, EngineTick, ViewportTick and others stalled or quit the game
  → bisect hook by hook; keep only the ProcessEvent family. A game-thread pump
  ran from a hooked animation-blueprint update. `FindFirstOf`/`FindAllOf` in a
  loop → "Hang detected on GameThread" → one queued update at a time and
  `GetAllActorsOfClass`.
- Quirks seen here: TArray results need `:ForEach`, not `ipairs`; `TMap:ForEach`
  on a menu instance crashed the game; `K2_GetActorLocation` returned zeros inside
  the pump (read the root component's properties).
- Recheck on any game patch. Offsets were discovered at runtime and logged on
  purpose, so a patch fails loudly instead of silently. Do not reuse another
  build's numbers.

## Reading bones, retargeting, secondary motion

- Transform-offset discovery took the first slot that matched one actor, locked
  onto a slot that later read zeros, and every body drew at scale 0 (invisible). A
  blanket "skip zero-scale" patch hid every body too. → vote across all tracked
  actors (non-zero scale required, at least two agree, ties go to the known-good
  slot) and re-detect when most bodies read zero for ~1.5 s; log the chosen slot.
- Skeletons faced different axes → best-fit yaw per body from its bone segments.
- Scale by head height → crouched creatures came out double size → scale by the
  ratio of summed bone lengths.
- Placing every mapped bone at the host's position → long necks and caved
  shoulders, because the companion rigs have helper bones mid-chain → place only
  the root (pelvis) from the host and keep the companion's own proportions.
  Arm-twist shoulder cave → split twist 20% arm bone / 80% the rig's twist bone.
- Companion animations are not portable, so secondary bones (hair, tails, wings,
  soft tissue) need springs. Force springs lagged then gained energy ("balloon"
  thrash). Verlet was stable but dead. What worked: fixed 60 Hz Verlet that
  carries the steady movement and jiggles only the quick part. Skip bodies whose
  transform reads zero (the NaN source) and expose tuning from a data sheet with a
  live `reload`.

## Drawing under the UI (ReShade add-on)

Case: a D3D12 host with HDR10 (R10G10B10A2) output; add-on built on ReShade 6.8.
Verified in game on one build; recheck on a different host or an SDR output.

- Drawing bodies or effects as a present-time overlay covers the HUD. The fix is
  to find the host's own pre-UI copy and draw there.
- Frame structure found with one `frametrace` run of the add-on's bind/copy
  events: the finished scene sits in the runtime back buffer F; the UI is drawn
  into a separate 8-bit target U; the host then copies F to a pre-UI scene X and
  composites X+U back into F. A copy whose source is F, with U as the last
  non-F target bound before it, identifies X and U.
- Recomposite in linear light: `out = F + (E - X) * (1 - U.alpha)`, where E is
  the effects result on X. One ordered technique (a `pass` list) is simpler than
  several techniques that depend on order.
- Hook points that carried it: `bind_render_targets_and_depth_stencil`,
  `begin_render_pass`, `draw`, `clear_render_target_view`, `copy_resource`,
  `copy_texture_region`, `execute_command_list`, `present`
  (`reshade::register_event`). `begin_render_pass` and the bind event both fire:
  do not count both as separate targets.
- Copying a new `.fx` over the old one does nothing until the reload call runs
  (`reload_effect_next_frame("file.fx")`): send the add-on's reload command after
  every copy. Cost an hour once.
- In ReShade 6.8 `update_texture_bindings(semantic, srv, srv_srgb)` takes three
  arguments.
- SDR output has no separate UI target: plan HUD masks as the fallback.
- Open when the lessons were written: health bar and bottom icons vanished in
  one on/off comparison; the pair was captured before the reload, so the cause
  was not isolated. Re-test with reload + on/off shots + a diff image, and trace
  the frame before tuning masks (tuning masks first wasted turns).

## Extractor and cache

- CUE4Parse read the UE paks without an AES key on this title. Avoid
  CUE4Parse-Conversion (it pulls an ImageSharp version with a high-severity
  advisory); a small DDS/mesh writer was enough.
- Hair had no colour texture (built in the material from a strand atlas) → bake
  colour+alpha; the first try picked a depth map; brows rendered white until the
  DXT1 atlas decode was fixed; a transparent cornea needed alpha test. Pick
  textures by their role in the material graph, never by a `_d` file-name suffix.
- Some hair ships as a separate mesh on the same skeleton: merge parts by bone
  name. A lash/brow material that is opaque in the source stays opaque; check
  the source before "fixing" geometry with alpha tricks (spiky "cones" on one
  creature were its real thorn mesh).
- The animation-clip decode of the Unity companion was never finished (the spike
  stopped at an API rate limit), so how much animation a companion yields stayed
  unknown. Spike clip decode first next time; it sets the scope.
- First version peaked at 9.7 GB and crashed beside the running game →
  manifest-driven extraction peaked near 380 MB as a single-file exe.
- Unity FMOD banks store Vorbis with the setup headers stripped → rebuilt with the
  host's own libvorbis/libogg, so no third-party decoder was downloaded.
- Never run a text clean-up (mojibake fixer) over a virtualenv: it rewrote pip's
  vendored files.

## Test and approval loop

- The owner denied mouse/keyboard automation → a test mode in the add-on posts
  Enter to the game's own window, screenshots come from inside the add-on (HDR10
  converted to sRGB), lab commands dump bones and reload sheets, and an offline
  Blender preview of a cached body separates extraction bugs from renderer bugs.
- Freezing all AI for screenshots and leaving it frozen while the owner played
  cost them a session: every freeze probe needs its unfreeze. Teleporting to
  frame a shot does not stick on aggro'd AI; use the add-on's rest-pose command
  (`test <body> x y z yaw`) instead.
- A fix counts as done only with an in-game shot or a log line, and the owner
  plays every build. No GitHub push and no Melty create/upload/submit until the
  owner says they are satisfied; local commits are fine.
- Melty flow: search/game info → build and test → inspect the package → create →
  upload → real gameplay media → submit the release → `test_release` (two or more
  runs) → publish. The recipe's cache done-file must match the format the
  extractor writes ("format=N"): bump it when the cache format changes.
- On this PC Git Bash `python` is the Windows Store stub: use the project's
  `.venv` interpreter or `py -3`.

## Starting a similar project

1. Read the host's engine version and anti-cheat/DRM status before choosing a route.
2. Choose passthrough unless the host can load foreign assets natively.
3. Spike the two unknowns before features: the host's draw/UI split and the
   companion's animation decode. Get one verified native call and one verified
   screenshot, and build the add-on command file (screenshot, dump, reload,
   test-pose) first.
4. Discover offsets at runtime, vote across actors, log what was chosen.
5. Keep extraction manifest-driven and bounded in memory; never ship source-game assets.
6. Write `STATE.md` and `MODLOG.md` as you go (failures with their cause).
7. Respect the owner's gates: in-game proof first, publishing last.
