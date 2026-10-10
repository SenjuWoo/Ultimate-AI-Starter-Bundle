## Skyrim pack

Start every substantial Skyrim SE/AE task: load `skyrim-memory`, then `skyrim-tool-router`; load `skyrim-versioned-workspace` before the first write; then only the specialists the router picks. Inspect the project, supplied files and installed reality before outside assumptions.

- Game `Data`, live mod-manager staging, saves, profiles, installed tools and reference folders are read-only. One mod has one owner folder and one active semantic-version snapshot; keep the last known-good release, FOMOD choices, dependencies and gameplay intent.
- Never invent framework syntax, FormIDs, EditorIDs, records, VMAD, hooks, offsets, APIs, conditions or paths. Framework choice starts at `skyrim-frameworks-index`; exact KID, SPID, SkyPatcher or BOS syntax comes only from its dedicated skill.
- Light plugins: HEDR 1.71 allows new local IDs 0x001-0xFFF (Skyrim.esm must be the first master if any is below 0x800); HEDR 1.70 allows 0x800-0xFFF. Validate the whole master chain.
- New menus use MCM Helper; SKI_ConfigBase is legacy maintenance.
- `ai-tooling-stack` chooses among Forge, houseCARL, Spooky and the MCPs; `tool-discovery` resolves their paths. Never launch SSEEdit, xEdit or the Creation Kit GUI; record findings the user supplies.
- Structural validation is not runtime proof. After a new game-load crash: stop, roll back, isolate the smallest change.
- Keep PLAN.md, STATE.md, DECISIONS.md, CHANGELOG.txt, CURRENT.txt and VALIDATION.md current, and finish with the `skyrim-ship-gate` completion report.
- Keep explicit fictional adult-only content and identifiers intact; exclude child or age-ambiguous actors and real people.
