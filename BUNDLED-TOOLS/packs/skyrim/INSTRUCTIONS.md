## Skyrim pack

Start every substantial Skyrim SE/AE task: load `skyrim-memory`, then `skyrim-tool-router`; load `skyrim-versioned-workspace` before the first write; then only the specialists the router picks. Inspect the project, supplied files and installed reality before outside assumptions.

- Game `Data`, live mod-manager staging, saves, profiles, installed tools and reference folders are read-only. One mod has one owner folder and one active semantic-version snapshot; keep the last known-good release, FOMOD choices, dependencies and gameplay intent.
- Verify before you write: read the record, FormID, VMAD, hook, offset or path from the plugin, the tool's own docs or the live MCP schema, then use it; never present a guessed one as real. Framework choice starts at `skyrim-frameworks-index`; exact KID, SPID, SkyPatcher or BOS syntax comes only from its dedicated skill.
- Light plugins: HEDR 1.71 allows new local IDs 0x001-0xFFF (Skyrim.esm must be the first master if any is below 0x800); HEDR 1.70 allows 0x800-0xFFF. Validate the whole master chain.
- New menus use MCM Helper; SKI_ConfigBase is legacy maintenance.
- `ai-tooling-stack` chooses among Forge, houseCARL and the MCPs; `tool-discovery` resolves their paths. Prefer the CLI/MCP route for SSEEdit, xEdit and the Creation Kit; open a GUI only when the user asks or the CLI genuinely cannot do the job, and record what it shows.
- Structural validation is not runtime proof. After a new game-load crash: stop, roll back, isolate the smallest change.
- Keep PLAN.md, STATE.md, DECISIONS.md, CHANGELOG.txt, CURRENT.txt and VALIDATION.md current, and finish with the `skyrim-ship-gate` completion report.
- Keep explicit fictional adult-only content and identifiers intact; exclude child or age-ambiguous actors and real people.

## Ownership of Skyrim tooling

Everything Skyrim-specific lives here and in the Skyrim Forge repository, not in the general bundle:

- Tools: Skyrim Forge, houseCARL, xEdit/SSEEdit, LOOT, the Creation Kit, and anything under the
  user's own tool root (on this machine `S:\Apps\Skyrim Tools`).
- Installer behaviour: the bundle installs or refreshes these only as part of *this* pack. When a tool
  already exists outside the bundle, the installer compares versions - it updates an older copy in place
  with a backup, keeps a newer one untouched, and never silently downgrades.
- Documentation and changelogs for the toolchain belong to Skyrim Forge; the bundle only records which
  version it ships and where it was installed.
- The general bundle is provider-agnostic: AI boost, coding, and modding across engines. If you are not
  doing Skyrim work, you can leave this pack switched off entirely.
