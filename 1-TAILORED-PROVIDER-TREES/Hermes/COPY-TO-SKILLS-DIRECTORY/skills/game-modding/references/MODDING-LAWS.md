# Cross-game modding laws

These applied to every skill in the source mega-pack. They had already
drifted into two variants -- 20 of the 41 files had silently lost the
Evidence ladder. This is the superset, stated once.

## Mandatory ownership before the first write

Create/read WORKSPACE_OWNERSHIP.md via workspace-organization before substantive edits. Preserve Git source layouts and version them with commits/tags. The following copy workflow is for established snapshot-based projects only; it does not require moving or copying an existing Git project.

```text
<OwnerRoot>\<Mod Name>\
├── CHANGELOG.md
├── CURRENT.txt
├── WORKSPACE_OWNERSHIP.md
├── <Mod Name> 1.0.0\
│   └── VERSION.md
├── <Mod Name> 1.0.1\
│   └── VERSION.md
└── <Mod Name> 1.1.0\
    └── VERSION.md
```

Before editing:

1. Read `CURRENT.txt`, `CHANGELOG.md`, and ownership.
2. Choose patch, minor, or major.
3. Fully copy the current snapshot into the new version folder.
4. Update `CURRENT.txt`.
5. Create the new `VERSION.md`.
6. Start the changelog entry with AI application, model, reasoning mode, parent
   version, goal, and intended files.
7. Edit only the new snapshot.
8. Record changed files, commands, validation, failed approaches, runtime status,
   and unresolved risks.

The parent remains immutable for rollback and binary comparison.


## Evidence ladder

1. `user-confirmed-runtime`
2. `runtime-evidenced`
3. `tool-validated`
4. `assistant-claimed`
5. `contradicted`

Never promote a successful compile, data generation, package build, or loader
discovery beyond what it actually proves.


## Non-negotiable controls

- Resolve the exact game build, storefront, engine/runtime, mod loader, mappings,
  framework versions, dependencies, and package format before implementation.
- Never invent APIs, class names, hooks, signatures, offsets, IDs, XML keys,
  script effects, reflected properties, asset paths, or serialization fields.
- Prefer current official documentation, upstream source, exact installed files,
  generated SDKs, decompiled assemblies, and known-good local examples.
- Deployed game directories, active manager staging, profiles, saves, and
  framework installations are read-only.
- Build, parser, loader, semantic, save, multiplayer, and runtime validation are
  separate gates.
- One writer owns each tightly coupled DLL, mod JAR, plugin, package, generated
  output set, or release archive.

## Ownership and publication scope

Preserve existing Git source layouts and use Git tags; the snapshot-copy rules apply only to snapshot-based projects. Before edits, create/read WORKSPACE_OWNERSHIP.md via workspace-organization. New work stays local until publication is requested; explicit GitHub means public/MIT for original work, subject to rights/terms and existing licences. Publish mods to their appropriate distribution site without duplicate GitHub hosting for mods needing no compilation. Keep source ledgers/changelogs outside runtime ZIPs.

## Look up before you build

Before blind binary recon or a custom hook, shader or proxy:

1. Query Context7 for `/senjuwoo/reverse-this` (max 3 calls per turn) when the
   host has the library; if it returns "not found", read the local encyclopedia
   at `%ENCYCLOPEDIA_ROOT%` (default `<reverse-this kit>\encyclopedia`).
2. Read `ROUTING.md` and take the lowest route tier that can deliver the
   behavior. A higher tier is not more impressive; it is more expensive and
   harder to verify.
3. Read the engine card for axes, units, depth convention and proxy DLL before
   writing a conversion or a hook.

If neither the library nor the encyclopedia is present, say so and use the
target's own documentation. Never invent an offset, signature or route.

## Route ladder

| Tier | Route | Use when | Minimum proof |
|---|---|---|---|
| 1 | Data overrides (loose files, plugin records, INI/CVAR, pak patch) | The engine loads the value from a replaceable source | Changed value appears and survives a restart |
| 2 | Loader APIs (SKSE, BepInEx 5, MelonLoader, UE4SS, ScriptHookV, ASI, Fabric, SMAPI, tModLoader, REFramework) | A supported script/plugin surface exists | Loader log shows the plugin; a downstream sink fires |
| 3 | Managed patching (Harmony, MonoMod, Fabric Mixin, IL2CPP detour) | The behavior is managed or has a stable managed entry | Patched method runs; disabling restores the original behavior |
| 4 | Native proxy DLL / module-scoped IAT hook / inline detour | No supported surface, or the behavior is native | Hook fires under a debugger; unhook restores the bytes |
| 5 | Headless simulation or decompiler library (Ghidra headless, Unicorn, reimplementation) | You must understand or replay without the game | Reimplementation matches recorded input/output traces |
| 6 | Concurrent shared-memory passthrough | Two runtimes must coexist frame-by-frame and no in-engine route exists | Offline IPC harness passes; live frames align without torn reads |

Stop at the lowest tier that can deliver the feature. Tier 4-6 needs the
offline harness first; never test them in a protected online session. A
multiplayer title with anti-cheat is a risk decision, not an automatic no:
some publishers tolerate client-side cosmetic mods, but memory injection and
patched game files are what trigger detection, the policy changes by patch, and
the account risk is the user's. Verify the current official statement and
`%ENCYCLOPEDIA_ROOT%\anticheat-risk.md`, keep the change cosmetic and
client-side, and never bypass or disable the anti-cheat.
For Tier 6 use `game-mashup-passthrough`; the encyclopedia holds the seqlock and
D3D11 harness sources.

## Contract and first slice

No live game executable until the project has:

- `docs/CONTRACT.md` with the goal, non-goals, target build, loader version,
  route tier, downstream sink and rollback plan;
- an offline harness that passes: `ipc_link_test` for shared memory and a
  fake D3D11 host for depth/pixel math (the encyclopedia's `blueprints/`
  holds the harnesses it ships; use `fake_host_d3d11` when present);
- a save backup and a SHA256 recovery manifest for every file the mod replaces.

For Tier 6 the first slice is deliberately small: log one line from the host
plugin, then pass one `float` (`player.x`) plus a synchronized frame counter
across shared memory. Do not attempt framebuffer compositing until that slice
passes with aligned frames and no torn reads.

## Three-agent split

Complex mods use three roles; one agent may hold two roles only when the task
is small enough to keep the evidence in one place.

- `mod-orchestrator` owns `docs/CONTRACT.md`, the route choice and the audit.
  It checks worker claims against files on disk and log timestamps, never
  against a worker's summary.
- `mod-offline-worker` is air-gapped from the game: writes code, shaders and
  harnesses, and runs only synthetic offline tests.
- `mod-game-worker` backs up saves first, deploys the built artifacts, runs
  windowed probes, polls the file/socket command bridge (for example a Z-floor
  safety teleport) and captures the verification logs.

Only the game worker touches a live game. The orchestrator never accepts
"it works" without the sink log, frame numbers or a diff image.

## Post-mortem encyclopedia sync

At `game-mod-ship-gate.md`, before the release is called done:

1. Write or update the version-pinned field note under
   `%ENCYCLOPEDIA_ROOT%\games\<game>.md` (build hash, loader version, route
   tier, sink, evidence, unresolved risks).
2. Add the error signature to `%ENCYCLOPEDIA_ROOT%\ERROR-REGISTRY.json` when the
   file exists, or record it in the project and propose the upstream addition.
3. If the encyclopedia is not present, keep the same content in the project's
   `STATE.md` and say the sync is pending. Never invent a hash or a registry
   entry.
