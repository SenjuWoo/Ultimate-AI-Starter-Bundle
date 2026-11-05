# Bundle audit state

## Prepared 8.31.0 — decisions, audit, hygiene — 2026-11-05

- `docs/decisions/` ADR-0001..0005; `TOOLS/audit_maintainability.py` (duplicates,
  skill ceiling, orphan tools, TODO markers) with `--strict` in the pack gate and
  `TESTS/test_maintainability_audit.py`. Removed 1.1 GB of local build output.
- Release metadata skill extended with the ADR and audit workflow.
- Unrestrained/preamble source untouched this release; 80 canonical skills.

## Prepared 8.30.5 — planner/worker defaults for Hermes — 2026-11-04

- Hermes starter (both canonical configs): Particle-1 main; one on-demand MoA
  preset `deepseek_particle` (DeepSeek V4.1 Flash 1017 high reference, Particle-1
  high aggregator, `fanout: user_turn`); delegation `model_map` with `execute`
  (Particle medium, default) and `research` (DeepSeek high), concurrency 2;
  auxiliary on `provider: auto`; title generation and background review off;
  Gemini removed from shipped MoA defaults.
- Migration: `Get-DelegationMigrationPlan` fills only an untouched delegation
  block; `Get-MoaMigrationPlan` now materializes the on-demand preset instead of
  disabling MoA; the shared prefs applier writes both without touching any
  profile's main model. `TESTS/Test-HermesProfiles.ps1` covers 44 cases.
  Release contract `test_hermes_starter_uses_planner_worker_pair`: 160/0.
- Unrestrained preamble, refusal protocol and Claude addendum reinforced (no content rule
  removed); provider instruction files and the unrestraint-packs skill carry the new
  no-self-refusal route. No companion-pin changes; 80 canonical skills.

## Prepared 8.30.2 — Skyrim knowledge moved to Skyrim Forge — 2026-11-04

- SkyrimForge was free (clean, in sync after its 6.9.0 release). Moved: `project-intel` Skyrim cards ->
  `skyrim-memory/references/SETTLED-RESULTS.md` and `RELEASE-RESULTS.md`; `PROMPTS/SKYRIM-*` and the v3 prompt
  library -> Forge `docs/prompts/`; `WHICH-AI-SHOULD-I-USE-FOR-SKYRIM.md` -> Forge `docs/WHICH-AI-SHOULD-I-USE.md`.
  Forge 6.9.1: native helpers rebuilt, validator twice with reports and once without, all PASS. The bundle is
  pushed only after Forge 6.9.1 publishes, so no install sees neither copy.

## Prepared 8.30.1 — public text stays general — 2026-11-04

- 8.30.0 published at `ed2fa21` (CI 12/12, Release success, Core 45,222,894 B sha256 2307258f..., Full-Offline
  141,830,240 B sha256 9d912991..., both equal GitHub digests and SHA256SUMS; alerts 0/0/0). The released Core zip
  was scanned for maintainer identifiers: only the old `tool-discovery` drive example matched; fixed here, and the
  privacy gate now fails on that drive root. The forge registry names public repositories only.
- Live (private, not in the repo): the codebase-memory store now holds the bundle and seven tool repositories
  (reverse-this, Skyrim-Forge, houseCARL, Risk-Of-Rain-2-Forge, RobloxForge, Minecraft-Forge, RimWorldForge);
  each root got a `.cbmignore` listed in its `.git/info/exclude`. `UABS_TOOL_ROOTS` gained the `Ai apps` folder.
  The profile registry and map under `%USERPROFILE%` were updated.
- RobloxForge v0.3.1 (`39f51ef`, CI 6/6, Release success, zip sha256 0b2a5d68... equals digest and .sha256):
  `Install.ps1`/`Update.ps1`/`Uninstall.ps1` passed no arguments (param named `$Args`). Local copy updated
  (backup `.backup-0.3.0-*`), keeping its unpublished `src/rbforge/plugins.py` change; its skills are now
  installed in Claude, Codex, Grok and Hermes (stamped 0.3.1).
- Folded discipline skills are not lost: each body is `references/<old-name>.md` under its router, the router
  table keeps the old trigger line, and `coding-discipline` now points at the routers.

## Prepared 8.30.0 — general foundation, forge registry, smaller index — 2026-11-04

- Owner direction (2026-11-04): the bundle is the general foundation and guide; specialist game content lives in
  the owner's forges; free procedural/creative tooling; no false guidance; unrestrained/NSFW untouched.
- Done: retired `roblox-game-development`, `saints-row-modding`, `minecraft-modding` and the RoR2/RimWorld
  references (forges ship them); forge registry in `ai-tooling-stack`; 52 one-page discipline skills folded into
  `reliability-engineering`, `verification-discipline`, `reasoning-discipline`, `token-efficiency` (127 -> 78
  skills); `free-creative-tools.md` with licenses checked on GitHub/Hugging Face; fact fixes listed in the
  8.30.0 changelog. Link check over 443 canonical URLs: no dead primary source left in kept skills (403s are bot
  blocks; vendored img2threejs carries some dead three.js manual links, left as upstream).
- Gemini research (shared report) used as leads only: its package versions were stale (R2API_Core 5.1.5 vs live
  5.3.0) and several claims (a hardcoded personal drive path in unrestraint-packs, ShugokiFable strings) did not match the
  tree. Confirmed and fixed: thin/overfit RoR2 guidance, Grok helper "edit paths first", V5 labels.
- Not done, by decision: Skyrim knowledge files (`PROMPTS/SKYRIM-*`, `WHICH-AI-SHOULD-I-USE-FOR-SKYRIM.md`,
  `project-intel` Skyrim cards) still live here because another session was editing SkyrimForge's working tree;
  move them into the Forge (e.g. `skyrim-memory/references`) in a Forge release, then delete here. The installer's
  Skyrim bridge (Forge + houseCARL install, `game-skyrim` profiles) stays: it installs the forge, it does not
  duplicate it. Vendored upstream skills (superpowers, skill-creator, img2threejs) left unedited.

## Prepared 8.29.16 — Risk of Rain 2 survivor preflight — 2026-11-03

- Lessons from the Ultron 1.1.2/1.2.0 audit and the Gnar 1.3.1 fixes are in the bundle: preflight and definition of
  done in `unity-mod-frameworks/references/risk-of-rain2.md`, a `project-intel` card (`ror2-modding.md`), the Forge
  and `ROR2_FORGE_ROOT` in `tool-discovery`. The Forge side shipped as Risk-Of-Rain-2-Forge v1.10.0 and v1.10.1.
- Published: v8.29.16 at `10658f9f7c952b8418cafe643d6678641e491046`. Pack gate PASS, release contracts 160/0, CI 12/12 and CodeQL green on that SHA, Release run success, Core zip sha256 matches SHA256SUMS, preflight present in the Claude tree of the zip, alerts 0/0/0.
- Not done: no `game-ror2` MCP profile (the Forge is a CLI); the routing is advice a model must follow, the only
  mechanical guard is `forge audit` when the model runs it.

## Prepared 8.29.15 — hardened-account installer fix — 2026-11-03

- 8.29.14 is published and verified (CI 12/12 on dfe40ec, release run success, Core and
  Full-Offline sha256 match GitHub digests and SHA256SUMS; alerts 0). Its live install
  failed on this account: `NoDefaultCurrentDirectoryInExePath=1` is set at user level, so
  the compiler self-test's `cmd /c compile.cmd` was not found. Fixed with `.\compile.cmd`
  plus a contract test.
- Live proof (working tree of 8.29.14 + this fix): install exit 0, doctor PASS 0 errors /
  0 warnings, Codex skill index 193 entries with `duplicates: []`; `~/.agents/skills` has no
  pack `roblox-game-development`, RobloxForge's copy in `~/.codex/skills` is untouched.
- Next: nothing pending; re-run the installer after 8.29.15 publishes only to stamp the
  installed version.

## Prepared 8.29.14 — finished the 8.29.13 audit's two open items — 2026-11-03

- Roblox duplicate: `~/.codex/skills/roblox-game-development` is RobloxForge's
  richer copy (`.rbforge-version` stamp); the pack copy sat in `~/.agents/skills`,
  so Codex indexed both. `Get-UabsCodexBuiltinSkillNames` now also returns
  top-level skills stamped `.<owner>-version`; the installer then backs up and
  removes the pack copy, the doctor accepts it, and legacy migration skips it.
  Fixture test added to `TESTS/Test-CodexPluginDedupe.ps1`; contract assertion added.
  Claude's copy of the skill is untouched (no duplicate there).
- Pins: GitHub MCP 2.0.3 -> 2.1.0 (asset sha256 ddce2749... equals GitHub's digest;
  47 tools, same schema bytes under the registered toolsets), Context7 4.4.4 -> 4.5.0
  (capability record regenerated; same 2 tools, same keyless split), Super MCP Router
  2.8.5 -> 2.9.2 (same 12 tools). `npm audit`: one moderate `@hono/node-server`
  finding is present in both Context7 4.4.4 and 4.5.0 (HTTP `serveStatic`, not
  used by stdio); the router tree has none. The three versions were published
  hours to ~1.5 days before adoption; pins are exact and the digest/surface checks
  above are the gate.
- Not exercised: authenticated GitHub tool calls, a live Context7 doc query (needs a key).

## Verified audit of 8.29.13 — 2026-11-03

- Audited release/source commit `63bb3c0989c5a8f20ac219ce44116f92b0ab1825`;
  checkout was clean. Its CI and release jobs completed successfully.
- Full Windows PowerShell 5.1 pack gate PASS; release contracts 159/159 PASS;
  source manifest 7,998/7,998; all declared versions agree. Evidence is in
  local `artifacts/audit-20261103-*.log` (not product payload).
- Local doctor initially reported five stale Forge skill receipts. Compared
  installed skills against their source before using Forge's owner installer:
  zero skill replacements; custom SPID content preserved; receipts backed up.
  Final doctor PASS. The existing two different Roblox skill copies remain;
  no personal expansion was deleted to silence a duplicate-index warning.
- Startup warning reproduced offline in a separate Discord watcher: its legacy
  `ready` listener emits Discord.js's deprecation warning. Backed up the script,
  retained `clientReady` only, and tested the actual registrations: one callback,
  zero warnings; syntax PASS. No login, messages or bot restart performed.
  Next normal launch loads the fix; the user's original unseen warning cannot
  be conclusively identified as this warning.
- Live registry audit: 10 current, 14 existing compatibility holds, 3 newer
  unheld versions, 1 internal source component skipped; zero lookup errors.
  New candidates: Context7 4.5.0, GitHub MCP 2.1.0, Super MCP Router 2.9.2.
  Isolated initialize/tools-list passed (2/47/12 tools). Not adopted: full
  behavioral/credential/config-migration proof is incomplete; the combined npm
  candidate dependency audit also reports Hono advisories. This is a dependency
  finding, not proof the stdio configurations expose the affected HTTP paths.
- Security query: Dependabot/code-scanning/secret-scanning all zero open;
  code quality unavailable. Corrected stale pinned-companion CI commentary and
  historical checkout-name guidance. No bundle runtime change or new release.
- Next: independently evaluate candidate dependency updates, including their
  transitive resolutions, and reconcile RobloxForge's separate skill ownership
  before removing either indexed copy. Do not overwrite custom settings/skills.

## Prepared 8.29.13 — non-disruptive install — 2026-11-02

- Live Hermes desktop/gateway is no longer stopped or relaunched. Native plugin
  refresh and profile migration defer with `deferred-live-gateway`; copied
  skills and existing plugins stay usable.
- `install_live_skills.py` is comparison-only; writes go through
  `INSTALL-AIO.ps1 -SkillsOnly` so junctions and preserved skills are safe.
- Release flow drops one duplicate docs check and avoids receipt-only commits;
  publication evidence stays in CI/job records and release assets.
- Local install proof: `install-state.json` 8.29.13, status complete; doctor
  PASS; personal model/provider choices unchanged; no apps closed.
- 130 canonical skills total. Unrestrained/preamble source untouched.
- Exact-SHA CI, release tag and asset hashes are recorded in the publication
  job/asset records; this file is updated before the release commit so the
  release does not trigger a second full matrix.

## Completed 8.29.12 tool horizon — 2026-11-01

- Second-opinion pass. Agents may use a better tool than the catalog names.
  A download that is not installed and not shipped by the pack is checked
  once and recorded in `%USERPROFILE%\.uabs\profile\SAFE-TOOLS.md`. Vendoring
  stays in `docs/TOOL-EVALUATIONS.md`.
- Bug fixed in `TOOLS/free_game_tools.py`: the Windows folder search was one
  shared list, so a missing tool was marked installed at the first other
  program found. The probe tests now run from the release contract.
- Four previously unarchived AIO texts are in `3-PREAMBLES/history`, so an
  older installed contract can be stripped instead of stacked.
- Live `tool-discovery` and preambles were refreshed. Full
  `install_live_skills.py --apply` was not run: it would also rewrite the
  `build-mcpb` newline and non-Claude `provider:` tags. Hermes `sillytavern`
  was left unwired on purpose (persona profile). `install-state.json` is 8.29.12.
- Codex dedupe, same path the installer uses: 21 unmodified pack copies that
  enabled native plugins already serve were backed up and removed (6 ponytail
  under `dedupe-Codex-20261101-195139`, 15 superpowers under
  `dedupe-Codex-20261101-195149`, both in
  `%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\backups`). Plugins stay enabled.
  `skill-creator` remains Codex-owned (`.codex\skills\.system`); the pack copy
  is absent, which is the builtin dedupe.
- Doctor this session, exit 0: PASS. One warning: Codex indexes
  `roblox-game-development` twice. Index 194 entries (159 from the pack, 35
  elsewhere), 148 visible description chars, measured. Re-running the
  installer does not clear it. Dedupe only removes a pack copy that a native
  plugin or `.codex\skills\.system` owns.
- The two roblox copies differ. `.agents\skills\roblox-game-development`
  matches `_CANONICAL-SKILLS` (3316 bytes, MD5
  `C5825595F5E536A015BE4E36650B3872`). `.codex\skills\roblox-game-development`
  is a local RobloxForge expansion (SKILL.md 5940 bytes, MD5
  `C049C9A4C24830448E22FA88B822940F`, plus `.rbforge-version`,
  `beginner-guide.md`, `free-stack.md`, `worldbuilding-lighting.md`, and
  longer shared references). `skill-overrides.json` does not exist. Neither
  copy was deleted or merged. Held for a decision.
- Personal-preservation notes, not doctor failures: Claude `spid-authoring`,
  and several Kimi Skyrim skills. Kimi is outside the recorded install, so
  the skill-accounting section skips it.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.12
  at `d7b361731fe2a33318f06aa2692124d9f2fbda31`. CI 41365949141, CodeQL
  41365948870, Release 41366718426. All 12 checks passed.
- Core 45,569,682 B sha256
  `b07fdb82de8da5d7c0fa68a149bc408eda6160301a1c4ca39a57408bbbf33b96`;
  Full-Offline 142,141,699 B sha256
  `63cb6f8287bc5215e8a0c63da99cb669c2cd3cf1d77bbe308a7c51be5aeb7584`.
  The eight hashed assets matched `SHA256SUMS.txt`; `SHA256SUMS.txt` itself
  is the ninth asset (802 bytes). The published Core zip matches the local
  build byte for byte.
- Open alerts: Dependabot 0, code-scanning 0, secret-scanning 0.
  Code quality scanning is unavailable on this repository and stays off.

## Completed 8.29.11 free game/app starter — 2026-11-01

- Added `game-dev-starter` (130 canonical skills): free-first stack choice,
  procedural asset generators, CC0 libraries, asset pipeline and real
  headless/build harnesses. Added `TOOLS/free_game_tools.py` (no network) and
  its contract tests; README/START-HERE point new projects at it.
- Fanout to all six provider trees; live skills installed in Claude, Codex,
  Grok, Kimi, Hermes and Antigravity.
- Local state 8.29.11: doctor **0 errors / 0 warnings**, after refreshing two
  provider-tailored skills and parking the RobloxForge server machine-wide
  entries (parked, not uninstalled; restore with `Set-McpProfile.ps1 -Unpark`).
- Hermes profiles: `particle-ai/particle-1` with `agent.reasoning_effort: high`;
  CBM 17 tools and Serena 3 tools connect in `code`.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.11
  at `15702181a300ae1ac707316a00b64a70234e9ca1`; CI 41337774860, CodeQL
  41337773240. Core 45,541,156 B sha256
  `91ebaed9d48336a209502401c3453c88cea03bc45f0294d9e6ed9455b2691930`;
  Full-Offline 142,113,170 B sha256
  `f35f3cfa0838fa00bdec80814663d411ffed130856bd2b207b08476c9a4adbf1`.
  All nine assets verified.
- Open alerts: Dependabot 0, code-scanning 0, secret-scanning 0.

## Completed 8.29.10 live-gateway install deferral — 2026-11-01

- `Migrate-HermesProfiles.ps1` now accepts `-DeferLiveGateway`: a running Hermes
  desktop or gateway produces a warning and exit 0 instead of a failed native-profile
  step. `INSTALL-AIO.ps1` passes it; CBM/Serena fallbacks still run.
- A full local install completed at 8.29.10: doctor **0 errors / 0 warnings**;
  Hermes profiles report `particle-ai/particle-1` / high; CBM 17 tools and
  Serena 3 tools connect in the `code` profile.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.10
  at `8899d7d1bb6eb511a82f73cf0444c4e4a9e543ba`; CI 41323973486, CodeQL
  41323973377. Core 45,504,935 B sha256
  `bd54b8fc49ce8b2444a1824379fd4c0854f92b7bc597d458fe82c18404bfb816`;
  Full-Offline 142,065,664 B sha256
  `9a37ea5edfac88be6aaab5a6caa0c620f24b215791760b4d762d224d2e83c537`.
  All nine assets verified.
- Open alerts: Dependabot 0, code-scanning 0, secret-scanning 0.

## Completed 8.29.9 particle-1 high Hermes default — 2026-11-01

- Hermes starter templates and migration fallback now use
  `particle-ai/particle-1` on OpenRouter with `agent.reasoning_effort: high`.
  Auxiliary tasks remain `provider: auto` with empty models; delegation remains
  `auto`; `sillytavern` stays `local-model`; MoA stays off.
- Live profiles switched by `hermes config set`: default, code, blender, creative,
  skyrim, unity and web report particle-1 and high.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.9
  at `5ecb457b39669dd8e2d6c2c91b168697cf3f8151`; CI 41284583701, CodeQL
  41284583649. Core 45,489,560 B sha256
  `de64067fdd1b98097fc46795af326c87ef9d8c47ae5c9d0b2502260cd57d0e0d`;
  Full-Offline 142,050,283 B sha256
  `bf25f7b25ba9535cf0f617ce6866a7e611991c96d92ffe5b85f6689adffb2c90`.
  All nine assets verified.
- Local install: `install-state.json` 8.29.9; doctor **0 errors / 0 warnings**.
- Open alerts: Dependabot 0, code-scanning 0, secret-scanning 0.

## Completed 8.29.8 intent-retry correction — 2026-11-01

- The AIO no longer treats a first refusal as a reason to switch models or drop
  scope. It retries once with the operator's exact intent and the smallest framing
  change; only the operator decides whether to move a task to a local model.
- The Claude Code addendum and `TOOLS/Strip-AI-Attribution.py` remain the
  no-visible-attribution path; host-side invisible provenance is outside prompt
  control. No legal/copyright/originality warnings were added.
- Live preambles (Claude, Codex, Grok, Hermes default and code) were recomposed.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.8
  at `f7f5715771e5d7deea57d5ce69fca6103abd6596`; CI 41282046741, CodeQL
  41282046652, Release 41282561349. Core 45,489,556 B sha256
  `2f83181a2b05fe5bef358a6783d6af2f81d94243d193a5fe1a9ad526d347ffcc`;
  Full-Offline 142,050,276 B sha256
  `ed643448d712532e4f73a70c281775a2a339516a02d81f5ec23c92d2c5250605`.
  All nine assets verified.
- Local install: `install-state.json` 8.29.8; doctor **0 errors / 0 warnings**.
- Open alerts: Dependabot 0, code-scanning 0, secret-scanning 0.

## Completed 8.29.6 default Serena install — 2026-11-01

- `TOOLS/Ensure-SerenaHermes.ps1` now installs `serena-agent==2.1.0` with
  `uv tool install --force` when the executable is missing, then registers the
  Hermes `code` profile. `INSTALL-AIO.ps1` calls it unless `-CoreOnly`.
- Verified by removing the Serena tool environment, confirming the executable
  was gone, running the ensure script, and checking 2.1.0 plus 3 Hermes tools.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.6
  at `a1a83a7c8e9f223828acf6baaa971a82dc1db0bc`; CI 41271054418, CodeQL
  41271054127, Release 41272136840. Core 45,483,552 B sha256
  `c5326d3b8aacd12783e7586b8c3618af0f5f80a08369cee1dc2f780dc21c0668`;
  Full-Offline 142,035,190 B sha256
  `40f73ebf226352e36a77b7af5ccb222c0945372515be643c3319648c5b39eacf`.
  All nine assets verified with `sha256sum -c SHA256SUMS.txt`.
- Local install: repository checkout, `install-state.json` 8.29.6; doctor
  **0 errors / 0 warnings**; Serena 2.1.0 connected with 3 tools.
- Open alerts: Dependabot 0, code-scanning 0, secret-scanning 0.

## Completed 8.29.5 Serena default and waiter hardening — 2026-11-01

- Serena 2.1.0 is now part of the default `code-intel` profile and the Hermes
  `code` profile when installed. It advertises **3 tools / 4,225 bytes /
  ~1,056 tokens**; with CBM the fixed surface is **~6,260**, under the 10k
  budget. The REPL exposes the rest dynamically; it is not registered globally.
- Added `TOOLS/Ensure-SerenaHermes.ps1` for live-gateway installs. Hermes
  `code` now has CBM + Serena; Claude and Grok show both connected for this
  project; Codex has the project config and requires trusting the project.
  Antigravity/Gemini is not wired; Kimi needs explicit `-Global`.
- `TOOLS/Wait-External.ps1` treats a denied `Process.Kill()` as best-effort and
  still returns the timeout verdict; `Test-GitHubVerdict.ps1` passes 20/20.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.5
  at `1cb96a96f6739768af5231b27dca7518e2b6b68b`; CI 41265265704, CodeQL
  41265265364, Release 41265813623. Core 45,483,375 B sha256
  `efe1d628f60bb0526d166d4d97d4b2e1b2a0af9e1da442d692dd9020346e27e2`;
  Full-Offline 142,033,098 B sha256
  `24f5c0c1b8f55bee920f45baade4ba0bd3829e028f49de6ededb45e45946886e`.
  All nine assets verified with `sha256sum -c SHA256SUMS.txt`.
- Local install: repository checkout, `install-state.json` 8.29.5; doctor
  **0 errors / 0 warnings**; CBM test 17 tools; Serena test 3 tools; default
  profile has neither.
- Open alerts: Dependabot 0, code-scanning 0, secret-scanning 0.

## Completed 8.29.4 codebase-memory registration and project map — 2026-11-01

- Root cause of "codebase memory never worked": the binary was installed and a
  graph existed, but `hermes mcp list` had no entry. The installer aborted the
  whole Hermes profile migration when a live gateway could not be stopped, so
  the native `code` profile never received `codebase-memory-mcp`.
- `INSTALL-AIO.ps1` now warns and continues migration instead of throwing, and
  `TOOLS/Ensure-CodebaseMemoryHermes.ps1` registers the server through
  `hermes mcp add` as an idempotent fallback. The fallback was proven by
  removing the entry and re-adding it; `hermes -p code mcp test` connected with
  all 17 tools, and a fresh `hermes -p code chat` used `list_projects` and
  returned the current root.
- codebase-memory stays in the default extras (5,204 code-profile schema
  tokens, under the 10k budget); `-CoreOnly` skips it and
  `-Components codebase-memory` forces it back. It remains absent from default
  chats.
- The stale graph pointed at the deleted `-v8.21.0` checkout. Deleted that
  project and indexed the current root: **21,379 nodes, 50,022 edges**,
  `status=ready`. `auto_watch=false`, `watcher_enabled=false`; indexing is
  manual and deliberate.
- `TOOLS/Start-CodebaseMemory-UI.ps1` starts one keepalive dashboard host;
  `http://127.0.0.1:9749/` returned HTTP 200 and the CBM Lens Beta title. It is
  optional; MCP works without it. A Startup shortcut was created locally.
- Re-measured 0.12.1: **17 tools, 20,814 schema bytes, ~5,204 tokens** (bytes/4).
  Updated the skill, catalog scope note, capability record, evaluation doc and
  release contract.
- Added the local-only project map: `PROFILE.md`, `MACHINE-MAP.md` roots and a
  workspace `WORKSPACE.md`; `project-intel` now sends agents there before
  scanning drives. Other projects are indexed on demand after `.cbmignore`
  review, not bulk-indexed into asset noise.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.4
  at `ff5e4c9541eb6d8d0baafd343a5094495a58fb0d`; CI 41260592574, CodeQL
  41260592435, Release 41261157323; `Wait-External` verdict **pass, 12/12**.
  Core 45,481,355 B sha256
  `714887b120758849ac19968999e74ccfc0a5d1dc1619bfd6558b8440b9726d65`;
  Full-Offline 142,031,075 B sha256
  `fb2fcf4cfb60c745b9403692784004012c55f26a83154712503ea04db5f3cb12`.
  All nine assets verified with `sha256sum -c SHA256SUMS.txt`.
- Local install: repository checkout, `install-state.json` 8.29.4,
  `MACHINE-MAP.md` points here; doctor 8.29.4 **0 errors / 0 warnings**.
- Open alerts: Dependabot 0, code-scanning 0, secret-scanning 0.

## Completed 8.29.3 auto-check and CI-wait correction — 2026-10-31

- `TOOLS/discover_tools.ps1` now reports `skyrim-forge` beside `reverse-this`,
  resolving `SKYRIM_FORGE_ROOT` or the default root and recording the Forge
  Python. Live check: Forge **6.7.0**, 50 tools, 0 doctor warnings; Reverse
  THIS! **1.9.5** from its kit; 48/48 Skyrim pack skills present. The bundle
  detects both owner installs and does not duplicate them.
- The fixed-`sleep` CI habit is corrected in `token-efficiency`: use
  `TOOLS/Wait-External.ps1` (2 s, backing off to 30 s), which reports pass as
  well as fail. It is the same waiter used by the release workflow, so a green
  run is no longer mistaken for "no alert"; the wait on this release returned
  `verdict=pass`, 12/12 checks.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.3
  at `b916410b20a59b22dd6deabc1ab8a4902843f8f0`; CI 41255310432, CodeQL
  41255310396, Release 41255887720. Core 45,472,458 B sha256
  `f7e3b47fe9e2098db028942d4a1e262b7d86cc827ffdd05935245e4cd73ed6d0`;
  Full-Offline 142,022,180 B sha256
  `c5dcbdfe25f6242a3424b574cb29fb8aed21d55fdcb5a55b409012d70e3eb905`.
  All nine assets verified by `sha256sum -c SHA256SUMS.txt`.
- Local install is the repository checkout itself; `install-state.json` and
  `MACHINE-MAP.md` point at it. The temporary `%USERPROFILE%\Apps\...` copies
  and Temp extracts were removed. Doctor 8.29.3 is 0 errors / 0 warnings. No
  application was stopped.
- Open alerts: Dependabot 0, code-scanning 0, secret-scanning 0.

## Completed 8.29.2 stale-pin closure and cleanup — 2026-10-31

- Closed the catalog audit without blind upgrades: the 10 newer optional or
  owner-controlled tools now carry explicit `compatibility_hold` reasons
  (Forge ownership, unmeasured upstream, a local security patch, or a pinned
  source rebuild). Audit: **current=13, held=14, stale=0, skipped=1, error=0**.
- Removed the test-only workspace audit reports and genericized the workspace
  fixture name; no user project is part of bundle work.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.2
  at `37f60eac048c27f8472e9094df85e61df8733298`; CI 41252528004 and CodeQL
  41252528135 succeeded, Release 41253091954 published. Core 45,471,262 B
  sha256 `241cf132c15d7c03f069e910e1806224cdf0730b36c236fd2b993bb9dfeea916`;
  Full-Offline 142,020,653 B sha256
  `180f42cd0aaa2d9c4ed6f6f6010ce58c50b96d81ad19f9c3114f73cbf32c0ff2`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local install: 8.29.2 tree at
  `%USERPROFILE%\Apps\Ultimate-AI-Starter-Bundle\8.29.2`; `install-state.json`
  and `MACHINE-MAP.md` point there; doctor 8.29.2 with 0 errors and 0 warnings.
  No application was stopped or restarted.
- No bundle work is pending. Context7 indexing of `/senjuwoo/reverse-this`
  remains external; the local encyclopedia fallback is documented.

## Completed 8.29.1 final audit and stable local install — 2026-10-31

- Reaudit found one real safety bug: `workspace_doctor.py` scanned only the
  first 400 text files for references, so a large project could move a
  referenced file outside that window. It now reports the cap and disables
  automatic moves when the scan is incomplete. `TESTS/test_workspace_tools.py`
  covers it.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.1
  at `9588b8b7b570c89350a30fcdc475420ab922fb9c`; CI 41249241579 and CodeQL
  41249241857 succeeded, Release 41249801690 published. Core 45,470,933 B
  sha256 `4a107b3634fe89b4a6145fe85821ebdebe267c17405f5cb355f9b1c4ddedf4c4`;
  Full-Offline 142,020,326 B sha256
  `5ea30e90e22cd3701b6132e687a58a5aab1077b24a59f892d44e6d853fa1e935`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local install without closing any app: the 8.29.1 Full-Offline tree is at
  `%USERPROFILE%\Apps\Ultimate-AI-Starter-Bundle\8.29.1`; `install-state.json`
  and `MACHINE-MAP.md` point there instead of the old Temp extraction.
  `Test-Installed-State.ps1 -PackRoot .` PASS with 0 errors and 0 warnings;
  doctor 8.29.1; `code` has 143 skills (129 general plus extras), `skyrim` 193;
  both new skills and both tools are present. No application was stopped or
  restarted.
- `workspace_doctor.py` from the stable tree on a large read-only mod workspace:
  stale root FOMOD, two snapshots, five nested caches, reference scan cap
  reached, **0 automatic moves**. The project was not modified.
- Maintenance: the catalog audit is now **0 stale / 14 held**. Each hold records
  why the evaluated version remains (owner, unmeasured upstream, or a local
  security patch); no dependency is silently behind. Context7 indexing of
  `/senjuwoo/reverse-this` is external and the local encyclopedia fallback
  remains. No bundle work is pending.

## Completed 8.29.0 mod workspace repair and presentation — 2026-10-31

- New `mod-workspace-organization` skill and `TOOLS/workspace_doctor.py`:
  source/package/release/state separation, one version source, stale root FOMOD
  detection, version-snapshot and nested-cache counts, and a narrow `--apply`
  that moves only high-confidence unreferenced clutter with a backup manifest.
  FOMOD roots, snapshots, nested Git repositories and game/binary assets are
  never moved automatically.
- New `mod-presentation` skill, `TOOLS/presentation_check.py` and
  README/Nexus/plan templates: a public page needs a real 16:9 cover, three
  gallery stills, three local README images with alt text, and a kind-specific
  shot (face, angles, wide/detail, motion, installer/menu). A text-only public
  page fails. Wired into `game-modding`, `MODDING-LAWS`, the ship gate,
  `workspace-organization` and `public-copy-durability`; 129 canonical skills.
- A large read-only mod workspace exercised the doctor: stale root FOMOD, two
  version snapshots, five nested caches, and no high-confidence automatic
  moves because the FOMOD root and snapshots are path-dependent.
- The presentation checker also fails a text-only page by design; that is the
  gap the gate exposes, not a fabricated result.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.0
  at `2c574e7a9aaf522bd4117943b51afdb4b8c83d26`; CI 41246082727 and CodeQL
  41246082537 succeeded, Release 41246730300 published. Core 45,470,840 B
  sha256 `1d4d171002e7fc0dca24ebd48fd075ebe53fc067c56f29e0c12c8bd848331629`;
  Full-Offline 142,020,227 B sha256
  `6d4cb17f34cc2c08dc695a73500be6dc16c888e6a9294508cad001d622790ea9`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local install: 8.29.0 Full-Offline installed with no `-Packs`; packs
  auto-detected Skyrim and Reverse; exit 0; doctor 8.29.0 with 0 errors and 0
  warnings; 129 general skills plus the two new ones in the `code` profile;
  models stay `deepseek/deepseek-v4.1-flash-1017`.
- Remaining: the example still needs a decision on the stale 2.0.4 root package
  and real captures; Ponytail stays 5.3.2 pending a bundled re-stage; 10
  third-party catalog pins remain stale; Context7 does not index
  `/senjuwoo/reverse-this`.

## Completed 8.28.5 one-click packs and AI-started tools — 2026-10-31

- One-click install now covers the specialist layers: `PACKS.json` auto-detects
  Skyrim from the game, a mod manager or an existing Forge, and Reverse THIS!
  from its kit receipt. `-Packs` still forces a layer, `-ExcludePacks` keeps it
  off, and both choices are remembered.
- The preamble now tells every provider's AI to start project MCP servers
  itself through the toolbox `find`/`describe`/`call` or the owning CLI, never
  to ask the user to start a tool, server or installer. A host restart is the
  only step it may request, and only to index a new skill. `game-modding` runs
  the Skyrim pack installer itself and uses Forge immediately.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.28.5
  at `8eb08d4e4f046a20806b76aea930d95ad15e6663`; CI 41241265014 and CodeQL
  41241264792 succeeded, Release 41241908203 published. Core 45,388,747 B
  sha256 `40e19cb00b880ea2a31b84d41674a60e72391cf6c3ee2b469ce7a601b046eb81`;
  Full-Offline 141,909,619 B sha256
  `3aa0fa7e846a05f5f7a94e800bf474b2a814d03a511fc9814747d56d83b2a04d`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local one-click proof: deleted `packs.json`, then ran
  `INSTALL-AIO.ps1 -Mode BundledOnly -SkipSelfUpdate -SkipHouseCarlSetup` with
  no `-Packs`; the log reports `Pack 'skyrim' on: found steam app 489830, My
  Games\Skyrim Special Edition, Vortex skyrimse, SKYRIM_FORGE_ROOT,
  SKYRIM_MO2_INSTANCE, HOUSECARL_ROOT` and `Pack 'reverse' on: found registered
  companion ReverseThis/kit.json`. Install exit 0, doctor 8.28.5 with 0 errors
  and 0 warnings, 9 project tools.
- Live: preamble with the no-manual-start rule is in the root and five profile
  `SOUL.md` files; 48/48 Skyrim pack skills in the `skyrim` profile; models stay
  `deepseek/deepseek-v4.1-flash-1017` on OpenRouter. A live toolbox `find
  "skyrim mod"` returned Forge's 56 tools without the user starting anything.
- Remaining: Ponytail is enabled and healthy at 5.3.2 while the catalog lists
  5.3.3; the live gateway deferred its native refresh and the local bridge has
  no remote, so the bundled copy must be re-staged before it can update. The
  third-party catalog audit still reports 10 stale pins. Context7 does not
  index `/senjuwoo/reverse-this`; live game/GUI targets were not exercised.

## Completed 8.28.4 final doctor fix and local install — 2026-10-31

- 8.28.4 fixed the last false install check: a default
  `Test-Installed-State.ps1` run required every provider name, so a machine
  where Kimi was intentionally not installed failed with "Kimi executable
  missing after provider bootstrap". The recorded `install-state.json`
  `providers` list is now authoritative; a recorded provider with no
  executable still fails.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.28.4
  at `0d47ded2e9d05e63a2187d3926489b15c0df271f`; CI 41237530662 and CodeQL
  41237530412 succeeded, Release 41238163181 published. Core 45,381,882 B
  sha256 `0eb88989eb6fa2f3f6b4bb7760aba1a86928c3bcb4988f002e69263579466160`;
  Full-Offline 141,902,753 B sha256
  `7d8e83123f75542a7be5172dee382e0b16b781833b0b5bf477b0c793c89267ab`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local install: 8.28.4 Full-Offline installed with
  `INSTALL-AIO.ps1 -Mode BundledOnly -SkipSelfUpdate -Packs skyrim,reverse
  -SkipHouseCarlSetup`; exit 0. Direct `Test-Installed-State.ps1 -PackRoot .`
  PASS with 0 errors and 0 warnings; doctor 8.28.4; 9 project tools; recorded
  providers Claude/Codex/Grok/Hermes/Antigravity.
- Live state: root/code/skyrim/blender/unity/creative/web use
  `deepseek/deepseek-v4.1-flash-1017` on OpenRouter with MoA off;
  `sillytavern` keeps its local LM Studio model and MoA by design. No
  `claude-code-imports` tree. Skyrim Forge 6.6.0 doctor warnings empty, 50
  tools, 48/48 pack skills; houseCARL MCP present; Reverse THIS! kit 1.9.4.
- Remaining: Ponytail is enabled and healthy at 5.3.2 while the catalog lists
  5.3.3; the live gateway deferred its native refresh and the local bridge has
  no remote, so the bundled copy must be re-staged before it can update. The
  third-party catalog audit still reports 10 stale pins. Context7 does not
  index `/senjuwoo/reverse-this`; live game/GUI targets were not exercised.

## Completed 8.28.3 final audit and local install — 2026-10-31

- Goal: final audit for errors, bloat and outdated info, then a clean release
  and a working local install.
- Audit: 127 canonical skills PASS (the two pre-existing token-budget
  warnings in `img2threejs` and `skill-creator` remain); README Hermes model
  corrected to `deepseek/deepseek-v4.1-flash-1017` in 8.28.1; the third-party
  catalog audit still reports 10 stale pins that are not bundle-owned.
- 8.28.2 fixed the User-scope shared-Python check: an installer launched from
  an agent venv inherited that venv's `python`, failed verification and rolled
  back. `Set-SharedPython.ps1` now puts the chosen base interpreter first in
  the process PATH before checking.
- 8.28.3 fixed two install-scope issues: the Hermes native plugin refresh is
  deferred with a warning when the gateway has a live chat session instead of
  aborting the whole install, and the general `toolbox` MCP only receives the
  Skyrim environment variables when `SKYRIM_FORGE_ROOT` exists.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.28.3
  at `0b4baa32fe73c61c8e4adcf47bfa7d743c0deede`; CI 41234029767 and CodeQL
  41234029580 succeeded, Release 41234673865 published. Core 45,381,755 B
  sha256 `639cd487948b7d8e19ebd806276e45bed0d86db801bf02afdb964819d307d8cd`;
  Full-Offline 141,902,624 B sha256
  `4f18a6382168ca5b7c16c1e309b9d656d1465b790ceb61ab55f193c784ecb671`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local install: 8.28.3 Full-Offline extracted and installed with
  `INSTALL-AIO.ps1 -Mode BundledOnly -SkipSelfUpdate -Packs skyrim,reverse
  -SkipHouseCarlSetup`; exit 0, doctor PASS 8.28.3 with 0 errors and 0
  warnings, 9 project tools. Root/code/skyrim/blender/unity/creative/web use
  `deepseek/deepseek-v4.1-flash-1017` on OpenRouter, MoA off; `sillytavern`
  keeps its local LM Studio model and MoA by design. No
  `claude-code-imports` tree remains. Skyrim Forge 6.6.0 doctor warnings
  empty, 50 tools, 48/48 pack skills in the `skyrim` profile; houseCARL MCP
  present; Reverse THIS! kit 1.9.4.
- Deferred: the live gateway prevented the Hermes native plugin refresh, so
  Ponytail stays at 5.3.2 (enabled, `hermes plugins doctor` OK) while the
  catalog lists 5.3.3; its local bridge has no remote. The next restart can
  finish the refresh, but the bridge must be re-staged from a newer bundled
  copy first.
- Not exercised: live game/GUI targets; Context7 still does not index
  `/senjuwoo/reverse-this` (local encyclopedia fallback documented).

## Completed 8.28.0 modular foundation — 2026-10-31

- Goal: the bundle is the base layer (general skills, work hygiene, GitHub/CI,
  visuals, efficiency, compiling, base tools); Reverse THIS! and Skyrim Forge
  are optional owners on top. No hard blockers, no duplicate installs, no
  stale model pins.
- Done: `reverse-engineering` skill with the 6-tier ladder and
  `CLAIMS.md`/`anticheat-risk.md`/`re-recipes` lookup; no-hard-blocker rule in
  the SOUL, manual paste and `coding-discipline`; Hermes model policy
  (deepseek 4.1 flash / auto, stale MoA advisors removed); anti-cheat risk
  tiers instead of a blanket ban; houseCARL falls back to the default Forge
  root; README "three layers" and corrected `-Packs reverse`.
- Live checks: Skyrim Forge 6.6.0 at the default root, `forge doctor` warnings
  empty, 48/48 pack skills in the archive and the `skyrim` profile, houseCARL
  MCP starts; Reverse THIS! 1.9.2 source kit, encyclopedia present, Context7
  library not indexed yet (local fallback documented).
- Gates: release contracts 155/0, canonical audit PASS, manifest 7,913 files
  verified, docs/version gates PASS, full Windows pack gate PASS.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.28.0
  at `6cff110452e1ba876f89a95e87f4f6aeb5c35503`, self-published by
  `release.yml` (run 41225055840) after CI 41224428043 and CodeQL 41224428221
  both succeeded. Core 45,381,347 B sha256
  `d7629abe98e3f9e03cc88dd96759f9921ec92ab13161e219aa327dc32c38d38e`;
  Full-Offline 141,900,771 B sha256
  `d23160cf836ebf5dc4ab263ce74eed8673acf65345416f8dc44c5b4787daf8ba`.
- Downloaded all nine assets; `sha256sum -c SHA256SUMS.txt` is clean, the
  release target is the exact pushed SHA, and the notes open with
  "**Which file?**". Open Dependabot, code-scanning and secret-scanning
  alerts: 0/0/0.
- Next: nothing pending. Reopen AI apps once to load the refreshed skills,
  instructions and model settings.

## Completed 8.27.1 new-user audit — 2026-10-29

- Goal completed: full audit of the public bundle and the live install after 8.27.0. Nine misses from the 8.27.0 pass were found and fixed: START-HERE.txt still claimed the Skyrim pack installs when Skyrim is found; README-CORE.txt, PACKS.json and one README line still described a pinned Forge; public skills carried the maintainer's drive-letter Steam library and tools paths (saints-row-modding) and a private workspace name (codebase-memory); a stale Forge 5.x verification reference remained; README restated a wrong body-budget skill count; README buried install steps at line 215; Claude Code listed 68 of 165 live skills without descriptions (1% listing budget).
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.27.1 at fad01c35870acae958d77d60c7fae9146ff6b5ed, self-published by `release.yml` (run 40823562197) after 12/12 checks: Core 45,328,105 B sha256 5fcb95ccc2ce9ef7805e8214998f5a269b29e38461162382a09c0fe9886ab6d7; Full-Offline 141,734,101 B sha256 c1457a044bab575bf6624084dcd651f831d885aa07a9e0e872510b9a911882ce. Downloaded: `sha256sum -c` clean for all 9 assets, attestation signed by release.yml@refs/heads/main, receipt companions skyrim-forge 6.5.1 and reverse-this 1.7.0 (picked up automatically), notes open with "Which file?".
- Gates: local pack gate PASS (run with `-TestPython artifacts\recovery\test-env-314\Scripts\python.exe`), release contracts 154/0 against the latest fetched companions, maintainer/provenance/regression suites OK, docs/version/memory/manifest/privacy gates PASS. New guards: stale companion wording in five user files, README-CORE equals the shipped note, Claude listing budget pinned in the starter, drive-letter Steam library paths blocked.
- Live: install exit 0, doctor PASS 8.27.1 0/0; `~/.claude/settings.json` gained only `skillListingBudgetFraction: 0.03` (backup `settings.json.before-starter-20261029-022143807.bak`); CLAUDE.md content paragraph and Codex model/effort unchanged; live skills reconcile exactly (105 bundle + 48 Forge + knap + 11 user-installed replica-*).
- User actions left: turn off the 14 claude.ai account skills that duplicate bundle skills (adult-character-sheet, adult-image-caption, ai-tooling-stack, codebase-memory, fictional-adult-modding, housecarl, skyrim-assets-pbr, skyrim-forge, skyrim-sexlab-to-ostim-modernization, skyrim-ship-gate, skyrim-tool-router, skyrim-voiced-dialogue, tool-discovery, unrestraint-packs); optionally remove the unused replica-* skills.
- After the release: two quick pushes showed that a Release run triggered by a cancelled (superseded) CI was *skipped* and GitHub filed it under main's newest commit, so `Wait-External.ps1` read that commit as failed. `release.yml` now has no job-level `if`; its decide step turns a non-green trigger into a no-op, and the release contract forbids the job-level gate.
- Not exercised: a fresh Windows account, game/GUI runtime, paid inference, Codex/Grok/Hermes skill-listing limits; no uninstaller exists.

## Completed 8.27.0 independence pass — 2026-10-29

- Goal completed: the three repositories develop and release independently. The bundle pins no companion version (CATALOG.json holds a floor); a Forge or Reverse THIS! release never needs a bundle release. Proven live: bundle 8.27.0's Full-Offline picked up Forge 6.5.0 and Reverse 1.7.0, both released minutes earlier, and the live install then moved Forge 6.4.2 -> 6.5.1 with no bundle change.
- Releases (each published by its own `release.yml` from the exact pushed SHA, no human tag; downloaded, `sha256sum -c` clean, GitHub build attestation verified to `release.yml` on `main`):
  - Bundle https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.27.0 at d3599f3a73665700802ec940e8bfce64ea3754a8: Core 45,347,809 B sha256 df7812fa7fbef37a8b111ab35d85fb72c8a2d50d43d8bad6bafbe7d491d3e3a5; Full-Offline 141,753,844 B sha256 018069817734d37387b92d26bb405ea8e9948506fd0afb02579ab66040fd400a; plus SHA256SUMS, BUILD-RECEIPT (run 40815582771, win25-vs2026, Python 3.14.9), SBOM (SPDX 2.3, 33 packages), VALIDATION (11 observed checks, all success), MANIFEST.
  - Forge https://github.com/SenjuWoo/SkyrimForge/releases/tag/v6.5.1 at 012765ba9f62e12fc00bb4c1d69db7fdd6d28d52 (6.5.0 at 1cf795b the same day): self-publishing workflow, version-free skill, README history labelled, personal path and drive-letter scan removed, Forge-side contract tests. Skyrim-Forge-6.5.1.zip sha256 5b7314f708e52b60b87598ead503e12ebbb0a83de31a7e45b39713c13231f82f.
  - Reverse THIS! https://github.com/SenjuWoo/reverse-this/releases/tag/v1.7.0 at acee844903b04dffb70e3a444907c104c60cbd85: doctor re-hashes receipt files (CHANGED/UNVERIFIED states; all 59 live tools verify), self-publishing workflow. Reverse-This-1.7.0.zip sha256 32da083f29b03a8921a419de415354fe48013ee7a554adb2cd337c3a9968a747.
- Trunk flow live on all three: rulesets `integrity` (no force-push/deletion, no bypass) and `checks` (PR merges wait for CI, admins push directly; bundle requires 8 checks incl. "Bundle installs latest companions end to end"); classic protection retired; Dependabot auto-merge workflow; Wait-External reads effective rules. One red push per repo during the pass (bundle `$LASTEXITCODE` after an in-process script; Forge 8.3 short path in a new test) — both release workflows refused the red SHA and were fixed forward.
- Gates: `check_versions.py --set` bumps every declaration (caught the README first-line comment it missed) and rejects restated companion versions/Skyrim counts; `#ownership` anchor guarded; workspace AIO copy guarded (it had drifted); release contracts 153/0 run against the latest fetched companions; full Windows pack gate PASS; CI weekly against latest companions.
- Skyrim cost (pack off, the default): 0 skill index entries, 0 MCP servers, 0 instruction bytes (pack blocks only for enabled packs; Forge writes its skills only when on; global Forge MCP entries retired). Pack on (this machine): +48 Forge skills (6,859 index chars), +1,808-byte instruction block per provider file, 0 global MCP servers (Forge/houseCARL start through the toolbox in Skyrim projects). Discoverability: the installer prints "enable explicitly with -Packs skyrim"; README says the same.
- Ownership proof (W14): bundle install -> Forge Install-Skyrim-Pack (5 providers) -> bundle install left all 7,819 provider skill files byte-identical; 8.26.1 -> 8.27.0 changed exactly ci-convergence, Setup-HouseCarl, skyrim-forge SKILL/INSTALLATION x5 providers.
- Live: install exit 0 twice, doctor PASS 8.27.0 0/0, Forge 6.5.1, Reverse 1.7.0 (git checkout clean; the superseded uncommitted 1.6.2 plan is kept in its sandbox/backups), CLAUDE.md content paragraph intact and new trunk line present, Claude settings.json and Codex model/effort unchanged, no global skyrim-forge entry.
- Metadata: bundle description lists six providers; Forge and Reverse homepages set; ShugokiFable URLs fixed in 14 release notes; no ShugokiFable in any tree.
- Deliberately not changed: tracked MANIFEST.json (deeply wired into the builder and verifier, cheap in packed history); third-party offline payloads stay in git (reason in docs/COMPANION-ARCHITECTURE.md); git history not rewritten (it would move every published tag); Forge's own STATE "Next" lines follow its next-release convention.
- Next: nothing pending. Push to main after `TESTS/Test-Pack.ps1`; bump with `python .github/scripts/check_versions.py --set X.Y.Z` plus the changelog sections; the push publishes itself. Not exercised: game/GUI targets, clean-machine install, paid inference.

## Completed 8.26.1 Forge/bundle MCP ownership fix — 2026-10-29

- Problem fixed: Forge's standalone `Register-MCP.ps1` wrote a global `skyrim-forge` entry and the bundle installer removed it (the toolbox serves Forge on demand), so each installer undid the other.
- Forge 6.4.2: https://github.com/SenjuWoo/SkyrimForge/releases/tag/v6.4.2 (PR 30; tag at 9a568aa196d4eafbb9049deaab35ebf284a884a7 after 14/14 checks; release run success). Registration reports `DEFERRED` per provider whose MCP config has the bundle `toolbox` entry while `toolbox-profiles.json` lists `skyrim-forge`; `-Global` overrides. Bridge suite 9/9 including a real Kimi deferral/`-Global` round trip; full Forge validator PASS twice plus idempotence. Skyrim-Forge-6.4.2.zip 4,833,006 B sha256 4bb55d67d44b2c3ac0593c56d4db5dd6d3fae0ce3f5a88a3454e447953d3d496 matches GitHub digest and SHA256SUMS.
- Bundle 8.26.1: https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.26.1 published by release.yml at 8f13d795b1afabd5a015c44e335f5e8fb1020e7c (PR 24). Re-downloaded: Core 45,333,697 B sha256 087e797068d16dd371d6b581d0f26d6daa39cfb73d5f9429a6183e27e35ebfda; Full-Offline 141,738,906 B sha256 ed5a2d417ce708a6abc89f597580cfe3da84db3bbee4bdd8d607af5843cf67f5; both match GitHub digests and .sha256 files. New drift gate: `check_versions.py` fails if the pinned Forge stops deferring or INSTALL-AIO stops writing `toolbox-profiles.json` (proven failing on the 6.4.1 pin).
- Live: install exit 0, doctor PASS 8.26.1 0/0, Forge 6.4.2, five providers answer the always-on MCP checks, CLAUDE.md content paragraph intact, Claude settings.json unchanged. Proof on this machine: installed Forge `Register-MCP.ps1 -Provider All -Yes` reported DEFERRED for Codex, Claude, Grok and Hermes (Kimi not installed) and left every provider config byte-identical.
- Security: open Dependabot/code-scanning/secret-scanning 0 on all three repos; each has only `main`.
- Forge's own STATE.md still reads "Next: full gate…" for 6.4.2; per Forge's convention it is refreshed with its next release (a docs-only edit there regenerates its hashed reports).

## Completed 8.26.0 tri-repo sync — 2026-10-29

- Goal completed: three cooperating owners, proven drift gates, Skyrim optional, hands-off releases, stale branches cleared. Live versions: Bundle 8.26.0, Skyrim Forge 6.4.1, Reverse THIS! 1.6.1.
- Ownership model (unchanged): Forge and Reverse THIS! own their code and semver; the bundle pins one release of each in BUNDLED-TOOLS/CATALOG.json (tag, asset, SHA-256) and ships those archives for Full-Offline. No vendored source tree.
- Gates proven to fail on tampered copies: Forge skill inventory, offline archive digest (one flipped byte), doctor contract (`result`/`read_only_ready`).
- First hands-off release: https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.26.0 published by release.yml run 40803716797 at 3a966853864e9695051e210ac79acabe628fce86 after all 11 check runs passed; built twice identically, re-downloaded and compared in CI. Independently re-downloaded: Core 45,333,643 B sha256 d7c0879c506caeea7000f55275c7e40377de78768257eab77fbd701cfd020eb4; Full-Offline 141,737,896 B sha256 584166a3c19dfcc3ac48a7d8c2141d64d3a38ac7daaa141522e626cf35aebe55; both match GitHub digests and .sha256 files.
- First attempt (aee376f, PR 21) went red on two pack-gate legs and release.yml correctly skipped. Cause: Wait-External turned a complete `pending` poll into `unknown` when the deadline hit a re-poll. Fixed in PR 22 with a deterministic fixture case (fails on the old waiter). PR 21 had merged with 3.12 red because only 3.14/3.15 were required; main now requires all eight checks (four pack-gate legs), strict, admins enforced, no force-push/deletion.
- Live install: exit 0, doctor PASS 0/0, five providers answered the always-on MCP checks; Forge 6.4.1 and Reverse 1.6.1 in place; live CLAUDE.md keeps the content-permission paragraph, no retired paths. Claude settings.json and Codex model/effort unchanged. Log: LOCALAPPDATA/Ultimate-AI-Starter-Bundle/logs/install-20261028-225404.log.
- Security: Dependabot, code-scanning and secret-scanning open counts 0 on all three repos; code quality unavailable, left off. Each repo has only `main`.
- Branches: 37 proven-merged branches deleted across own repos (ancestor of default, or tip equal to a merged PR head, re-checked before delete); 15 green Dependabot PRs merged (three after a rebase or branch update); Cuda-Spirit 15 closed by Dependabot as superseded. Local bundle and live Reverse kit checkouts are on `main` with merged branches removed.
- Left for the owner, not merged: BDO-AIO `feat/open-chest-uncut` (4 commits, 0 behind) and `dev/partcut-research` (1 commit, 40 behind); ai-prompt-library `master` (no common history with `main`); fork branches with own commits (`modlist-stability` in four 1001Bits forks, CreationEngineRaytracing `perf/ultimate-4080`); upstream branches in forks untouched. facefusion-improved: five Dependabot PRs and main CI cannot run because GitHub Actions reports failed payments/spending limit (billing settings).
- Open conflict: Forge's standalone Register-MCP.ps1 registers `skyrim-forge` globally, while the bundle installer retires global Skyrim MCP entries in favour of the toolbox; whichever runs last wins (this install removed one added between 10-25 and 10-28, backups config.toml.bak-mcp-20261028-225824).
- Live Reverse kit STATE.md carries an uncommitted GPT plan for a 1.6.2 pass (kept as is). Its README digest-scope item shipped in PR 18; VERSION.txt mirror rejected (the bundle reads `VERSION`); the Python-fallback test is not done.
- Next: reopen AI apps once. Build/test: TOOLS/Build-Release.ps1 (manual fallback); TESTS/Test-Pack.ps1 -TestPython artifacts/recovery/test-env-314/Scripts/python.exe. Not exercised: real game/app GUI targets, clean-machine install, paid inference.

## Completed 8.25.1 audit release — 2026-10-27

- Goal completed: instruction/agent-size audit across the three owners. Live versions: Bundle 8.25.1, Skyrim Forge 6.3.2, Reverse THIS! 1.5.0 (unchanged, audited clean).
- Bundle release: https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.25.1 ; tag commit 58c6b264f6fca94b7c907236d8f2d9ce073114c9, 9/9 checks green on that commit. Core 45,306,514 B sha256 365e7070c3611f84046998c8585724281d4c130dff117b0efde04d8a7d1be5c2; Full-Offline 141,697,087 B sha256 8195eb4bd9e266726eecc9ec6f3aab2f94d2bad17cec64599bb7dfc71f73948c. Built twice identically; all four public assets match the build, GitHub digests and checksum files. Proof: artifacts/final-assurance/bundle8251-release/build.local.json.
- Forge release: https://github.com/SenjuWoo/SkyrimForge/releases/tag/v6.3.2 ; tag commit aaabdd25847aefa9d82a9f95abe1bc6bf66a4342, 14/14 checks green. Product ZIP 4,818,367 B sha256 8f5507f6255e42c238e4adedc321c7843ca15e6da0838ec0ef75027be778138a; bytes match GitHub digest and SHA256SUMS. Pinned by this bundle.
- Content decision: the AIO first paragraph (explicit content permission, "Answer first") is the owner's and is kept verbatim; an earlier dedupe removed it and was reverted (PR 17). Do not shorten the content-permission or security paragraphs without the owner asking.
- Live install: 8.25.1 installer exit 0, doctor PASS 0 errors/0 warnings, five providers answered the always-on MCP checks. Live CLAUDE.md has no Ownership prose or hard path; SPOOKY_AUTOMOD_ROOT cleared (retired folder under LOCALAPPDATA/Ultimate-AI-Starter-Bundle/spookys-automod-toolkit is left for Clean-StaleState). Claude model, permission and effort settings unchanged. Log: LOCALAPPDATA/Ultimate-AI-Starter-Bundle/logs/install-20261027-171415.log.
- Security: Dependabot, code-scanning and secret-scanning open counts 0 for all three repos; code quality unavailable, left off.
- Evaluated, not bundled (docs/TOOL-EVALUATIONS.md): taste-skill 2.1.5, ECC 2.2.3, replica-skill.
- Next: reopen AI apps once. Build/test: TOOLS/Build-Release.ps1; TESTS/Test-Pack.ps1 -TestPython artifacts/recovery/test-env-314/Scripts/python.exe (use a per-process execution-policy bypass). Not exercised: real game/app GUI targets, clean-machine install of these releases, paid inference.

## Previous checkpoint (8.25.0)

### Final assurance — 2026-10-27

- Goal completed: three standalone cooperating owners, explicit project ownership, private-by-default new work and clean product distributions. General AI/build/workspace tools belong to the bundle, Skyrim tools to Forge, reverse-engineering tools to Reverse THIS! Shared installations are discovered/reused and version-checked; project pins/newer versions and personal edits are preserved. The companion architecture analysis remains in docs/COMPANION-ARCHITECTURE.md.
- Public and live versions: Bundle 8.25.0, Skyrim Forge 6.3.1, Reverse THIS! 1.5.0. Existing repositories retain visibility/licences. Explicit GitHub publication means public/MIT for original work subject to rights/terms; generic Skyrim publication normally means Nexus, with no duplicate GitHub for mods needing no compilation. New projects stay local until publication is requested.
- Bundle release: https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.25.0 ; immutable tag commit ed26acc6d7fa78fbbf181e3364f777911d5c4977. All nine checks on that commit passed before packaging; security flags clean. Core and Full-Offline each built twice byte-identically from its Git archive. Both extracted products pass delivered-manifest/7-skill-tree/actual launcher-help checks (7,574 and 7,582 manifest rows). All four public assets were downloaded and match local bytes, GitHub digests and checksum files.
- Core: 45,261,764 bytes; SHA256 0610fe2e8beb73ef7aed3b454fff296b13059b5e120613ade201fd06cf587a6a. Full-Offline: 141,652,713 bytes; SHA256 6e9d8a6bfa5f35d075deb8721ba14cf7aa5056172c92c9f1b47b2d363b454a69. Proof: artifacts/final-assurance/bundle825-release/build.local.json and verified/final.local.json. Later handoff changes only source validation/STATE/integrity metadata and never moves this tag or replaces assets.
- Forge release: https://github.com/SenjuWoo/SkyrimForge/releases/tag/v6.3.1 ; frozen commit 533f399c7eded2fa75c0bc2dabd809ec999ccc50, clean handoff main 1f7dcb8c3a360a14c6bc678dfa1ee52950bcdcc8 (all 23 checks pass). All eight public assets match CI build/GitHub digests/checksums. Product ZIP 4,818,789 bytes; SHA256 ff6f4e04dcb362cd3ceb65d0d17292c4d2ed715e8558b093e3f635578d890fa4. Both same-toolchain builds are identical; all 540 payload files/metadata agree across Python compression toolchains and all 539 installed manifest files match public bytes. Published 6.3.0 remains immutable and is superseded; never deploy it. Proof: forge631-final/completion.local.json and verified/final.local.json.
- Reverse release: https://github.com/SenjuWoo/reverse-this/releases/tag/v1.5.0 ; frozen commit ab9b842d8a5f7bfce7c128f5f94c1421e3933723, clean source main f5c0da39501ac0257f2d58484e8f9d288caf3071 (all seven checks pass). Both public assets match build/GitHub digests/checksums. Product ZIP 64,217 bytes; SHA256 5734af455687f5c4345a497f8ea672e6fb0d2249f060e79ada36628b09b8a7ca. Existing selected tools refreshed with NoUpdate: 56 success/0 failures, doctor PASS. Proof: reverse150-final/verified/final.local.json. Private target work, tool versions and shims preserved.
- Final local gate completed BEFORE remaining releases: live bundle 8.25.0 doctor 0 errors/0 warnings; Forge native version/self-test/doctor and 53-tool MCP probe PASS; houseCARL MCP 31 tools PASS; fifteen real core MCP probes across Claude/Codex/Grok/Hermes/Antigravity PASS. Kimi remains unselected. Thirteen saved model/permission/MoA fingerprints are unchanged, including the final pre-publication recheck. Canonical ownership helper matches five provider roots and four Hermes profiles.
- Strict historical inventories proved 13 stale generated Hermes Skyrim-profile skill copies; backed up and migrated through Forge's owner installer. The general ai-tooling-stack remains bundle-owned. Private Forge workspace identity is unchanged; its config differs only in installer-owned tools.ui_worker.version. Source/runtime versions use Forge VERSION.txt, without requiring source CURRENT.txt. Dual-shell marker tests and real live install pass.
- Backups: LOCALAPPDATA/Ultimate-AI-Starter-Bundle/backups/final-8.25.0; previous Forge owner LOCALAPPDATA/Skyrim-Tools/.forge-backup-e24f81ce5dba4f229bdd866b0cb7ab1d; Hermes historical copies LOCALAPPDATA/Skyrim-Forge/backups/verified-hermes-profile-a57bf791255949f8ad170cf080b506eb. Reverse source backup remains sandbox/backups/source-1.5.0-62f9c745017b4caab100684cbb66b0b4. Keep previous tags/releases and rollback evidence.
- Source validation: full 19-section Windows pack gate PASS; release contracts 151/0; ownership/publication/junction tests 7/7; real product/fanout tests 2/2; all 7,882 source manifest hashes and version declarations agree. A stale validation release tag is now rejected. Forge full release validator: 230 Python tests plus native/Go/race/installer/reproducibility gates PASS. Unchanged compiler/shared Python 3.14.10 real compile evidence is reused, without installing another base Python. Official CI action pins refreshed across all owners.
- Evidence owner: artifacts/final-assurance. Final local receipts: pre-publication-local-proof.local.json, bundle825-final-installed-doctor.local.json, forge631-live-local-proof.local.json, installed-ownership-helper-proof.local.json, housecarl-prepublish-mcp.local.json, final-8250-settings.local.json and Hermes migration proofs. Successful installed log: LOCALAPPDATA/Ultimate-AI-Starter-Bundle/logs/install-20261027-122557.log and details. Source logs: bundle825-final-pack.log, bundle825-final-contracts.log and bundle825-frozen-build.log.
- Security: open Dependabot/code-scanning/secret-scanning counts zero. Code quality unavailable and left off; no alert dismissed or forbidden scanner/secret pattern enabled. Final source handoff check/security/clean-tree receipt is captured after this documentation commit in artifacts/final-assurance/completion.local.json.
- Next: no implementation, release or live-deployment work remains. Reopen AI apps once to load refreshed instructions/MCP state. Use START-HERE.bat when another update is wanted. Build/test: TOOLS/Build-Release.ps1; TESTS/Test-Pack.ps1 -TestPython artifacts/recovery/test-env-314/Scripts/python.exe. Preserve existing settings and use supported per-process PowerShell execution-policy bypass, never a machine policy change.
- Exact limits: actual game/app GUI targets, guest Windows Sandbox, paid inference/API runtime and real absent-provider installations remain untested. Compatibility holds remain evidence-based; no guarantee of arbitrary future upstream compatibility is claimed. No further broad research or unchanged-input checks are needed.

## History

Superseded checkpoints: docs/history/STATE-ARCHIVE-8.19-8.25.md. Per-release notes: CHANGELOG.md and docs/history/.
