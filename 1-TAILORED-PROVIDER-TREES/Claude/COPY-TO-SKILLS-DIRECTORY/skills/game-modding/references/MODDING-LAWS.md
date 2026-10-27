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
