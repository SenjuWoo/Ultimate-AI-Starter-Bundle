# Final release gate

```text
VERSION SNAPSHOT: PASS|FAIL
WORKSPACE LAYOUT: PASS|FAIL|N/A
SOURCE INVENTORY: PASS|FAIL
BUILD: PASS|FAIL|N/A
FRAMEWORK VALIDATION: PASS|FAIL|N/A
ASSET VALIDATION: PASS|FAIL|N/A
DEPENDENCY GRAPH: PASS|FAIL
PACKAGE ROOTS: PASS|FAIL
UPGRADE/UNINSTALL: PASS|FAIL
SAVE/MULTIPLAYER: PASS|FAIL|UNTESTED
RUNTIME STATUS: user-confirmed-runtime | runtime-evidenced | tool-validated | assistant-claimed | contradicted
PRESENTATION: PASS|FAIL|N/A
ENCYCLOPEDIA SYNC: PASS|PENDING|N/A
UNRESOLVED: none | exact risks
```

Never collapse `UNTESTED` into `PASS`.

`WORKSPACE LAYOUT` is PASS only when one current version source exists, the
current package root agrees with it, old snapshots are archived rather than
scattered, and caches are outside the package. Run
`TOOLS/workspace_doctor.py <root>` and resolve its stale-root warning. `N/A`
only for a project with no package or version state.

`PRESENTATION` is PASS only for a public release and only when
`TOOLS/presentation_check.py <root> --kind <kind>` passes: real cover, at least
three gallery stills, three local README images with alt text, and the
kind-specific shot (face, angles, wide/detail, motion, or menu). `N/A` is for a
private build that is not being published; never mark a text-only public page
PASS.

`ENCYCLOPEDIA SYNC` is PASS only when the version-pinned field note under
`%ENCYCLOPEDIA_ROOT%\games\<game>.md` and the error-registry entry are written.
`PENDING` with the reason is acceptable when the encyclopedia is absent, and
the same content must be carried in the project's `STATE.md`. Never invent a
build hash or a registry entry to make this line PASS.


## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
