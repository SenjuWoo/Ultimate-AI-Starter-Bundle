# Start a new mod or major feature

Ownership, versioning (Git tags for Git projects; snapshot folders only for snapshot projects) and the never-invent laws: `game-modding` -> `references/MODDING-LAWS.md`.

## Define

Record player-facing behavior, non-goals, exact game build and storefront,
engine/runtime, loader/framework versions, dependencies, save/multiplayer policy,
and package format.

## Design

Separate native or managed code, scripts, data patches, assets, UI, networking,
dependency adapters, and packaging. Do not add a DLL merely because one can be written.

## Implement

Build a minimal vertical slice, pin dependencies, keep generated output
reproducible, preserve source/symbols/manifests, and validate each layer.

## Integrate

Test dependency absent/present, clean install, upgrade, uninstall, save
compatibility, multiplayer symmetry, and game-update sensitivity as applicable.


## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
