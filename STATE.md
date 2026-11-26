# Bundle state

## Current work

- Goal: reliable prompt-first capability discovery across providers, preserving
  creative intent and personal settings with small default context.
- Version: `VERSION.txt`; published revisions and recovery points are Git tags.
- Implemented: advisory workflow routing; conservative Ponytail auto classification;
  bounded companion discovery with explicit-owner precedence; moved MCP path
  repair; active launch-path diagnostics; provider-scoped prompt hook wiring;
  stable instruction boundaries; profile overflow handling; retained legacy skill
  backups; deterministic memory indexing of hooks, companions and profiles.
- Architecture: `docs/decisions/0007-advisory-discovery.md`. Prior model-ranking
  claims in ADR-0003 are historical; provider model selection remains operator-owned.
- Recovery: machine inventories, session exports, graph snapshots and deployment
  receipts stay outside the public payload. Private historical exports are not
  live provider configuration. No source or game tree is moved just to rename it.
- Audit fixes: literal Windows task paths, empty evidence, MCP section/comment
  isolation, uncommitted line-ending checks and bounded manifest traversal.
- Architecture review: `docs/decisions/0008-cheap-hooks-and-truthful-roots.md`
  (hook cost, source/runtime discovery, moved folders, awkward paths).
- Validation commands: `python TOOLS/release_gate.py`; installed diagnostics:
  `powershell -NoProfile -ExecutionPolicy Bypass -File TOOLS/Test-Installed-State.ps1`.

## Current verified state

| | |
|---|---|
| Release | `VERSION.txt` and the git tag are the only source; a contract test fails if this row disagrees with `VERSION.txt`. no literal version is kept here on purpose |
| Branch | `main`; verify the exact SHA against the remote before delivery |
| Next version | the next patch after `VERSION.txt`; nothing to edit here |
| Next action | whatever the Done/Next section below lists; this header stores no release fact it could contradict |
| Evidence | `python TESTS/test_release_contract.py`, `python TESTS/test_task_state.py`, `TESTS/Test-Pack.ps1`, `gh run list --commit <sha>` |

- Build: `python TOOLS/build_release.py`. The release workflow verifies the exact
  main SHA, builds twice, compares bytes and verifies downloaded release assets.
- CI and alert convergence: `TOOLS/Wait-External.ps1` and `TOOLS/Get-GitHubFlags.ps1`.
- A path or registration is not execution evidence. MCP handshakes prove transport
  and tool listing; task calls establish capability. Paid model benchmarks remain
  opt-in and are not implied by deterministic tests.
- Re-index a source owner after structural changes, with a consistent database
  backup first. Verify its current root and a source query afterward.
- Next action: use the full gate and exact-SHA CI for maintenance; retain private
  deployment evidence locally and published receipts with the release assets.

## History

8.53.11 (2026-11-26): Hermes gate wiring passes the known config path (-~3 s per call, 44 calls here);
CI pack gate sharded across the four required Python jobs (Test-Pack -Shard 1..4; schedule/manual = full);
Fable hands implementer only self-contained packages; advisor only at decision points; team checked against
Anthropic's measurements (docs/TOOL-EVALUATIONS.md); Hermes opus alias -> 5.5. Measured install phases still
open: Reverse THIS! companion 60-120 s (93 owner-managed tool checks), Codex plugin remove+add ~75 s, the rest of
the Connecting phase ~125 s, Skyrim Forge ~40 s, final check ~40 s.
Verified: gate 41/41; four shards print the same 129 checks as the unsharded gate; CI 12/12 on e5823bb in 251 s
(was ~490 s); v8.53.11 Core zip SHA-256 matches; alerts clean; repeat install 874 s -> 592 s (gate wiring 253 s
-> 113 s); doctor PASS, 7 agents byte-equal, one current routing block, 8 Hermes hooks approved. Not verified:
delegation behaviour in new chats (count subagent_type in session logs newer than this install); a planted
failure per shard; the fresh-home install path.

8.53.10 (2026-11-26): delegate down, never sideways - Opus sessions build inline instead of spawning the Opus
implementer (logs showed up to 26 spawns per session); implementer description de-defaulted; Explore Haiku medium;
doctor flags a stale routing block; prompts and private templates synced.
Verified: gate 41/41; CI 11/11 on 46409bc; v8.53.10 Core zip SHA-256 matches SHA256SUMS and ships the new
routing; alerts clean; install + doctor PASS, 7 live agents byte-equal, one current routing block. Not verified:
runtime delegation behaviour (headless `claude -p` probe needs a CLI login on this PC).

8.53.9 (2026-11-25): doctor finds the toolbox (catalog `server_id: toolbox`, contract test); README
cover, badges, nav and a real-run integrity shot in docs/presentation; archive sizes corrected.
After the release (docs-only, ships with the next version): README doctor shot from a real run on the
8.53.9 install (doctor PASS, toolbox registered in all six apps).

8.53.8 (2026-11-25): fresh Claude CLAUDE.md no longer grows per install (legacy prefix matched inside
the current head; pack writer EOL); doctor agent check scoped; agent-team and head tests in the gate.

8.53.7 (2026-11-25): Claude agent team (7 tiers, Opus High default builder); installer-managed
agent-team routing block; doctor check; Team: line in every prompt; GENERAL-0-AGENT-TEAM.

8.53.6 (2026-11-24): GENERAL-5-UPGRADE prompt (START-RESUME-UPGRADE.md retired);
shorthand forge manifests self-register (Gta-Forge was skipped for a missing title);
ai-tooling-stack routes GTA V.

8.53.5 (2026-11-23): install-fail fix - a Hermes profile MCP pinned to Hermes's
rotating private venv (installs\<id>\environments\<hash>) is moved to the shared
Python after a proven handshake, else to the env Hermes's facts.json records;
RobloxForge registration uses the shared Python. Bundle FIELD-REPORTS cleared
(companion_registry --roots, comfy-3d launcher, task_state record-only commits;
the HEDR report moved to its owner Skyrim-Forge; a RobloxForge sys.executable
report filed with its owner). Log of the failed install:
%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\logs\INSTALL-FAILED.txt.
Open: catalog pins behind upstream (`python TOOLS/audit_catalog_versions.py`
reported stale=14 on 2026-11-23, among them headroom, playwright-mcp,
firecrawl-mcp, context7, github-mcp-server, blender-mcp, unity-mcp, rtk,
windows-mcp, super-mcp-router, playwright-cli, comfy-cli; two skill packs
drifted) - next release refreshes them with handshake/payload verification per pin.

8.53.4 (2026-11-17): Claude subagent tiers (Explore/Haiku, researcher/Sonnet,
implementer/Opus); Hermes memory
import cleanup covers pack/preamble/agreements blocks; Hermes profile backup families
pruned; GENERAL-2 architect prompt edit shipped.

8.53.3 (2026-11-16): contract wording clarification; published as release.

8.53.2 (2026-11-16): expanded creative scope and cut false blocks - the
instruction forms state the full range of adult work plainly; the one
hard line is unchanged and the Antigravity 24 KB AGENTS.md cap is respected
(template trimmed to fit); local gate and full install pass on Windows.

8.53.1 (2026-11-16): maintenance release - the 8.53.0 preamble-archive retirement
is completed (49 archived texts removed; marked-block installs converge alone);
SOUL.md slimmed to what the contract does not carry (identity, consent framing +
hard line, yesman, recency, hard blocker - everything else restated
AIO-INSTRUCTION.md); MANUAL-PASTE.txt rebuilt from it; CLAUDE-CODE-ADDENDUM.md
slimmed to output identity + attribution stripping (was a restatement of the
contract); docs/GLOBAL-INSTRUCTION-AUDIT.md retired (findings live in ADR-0007);
unsynced working-tree duplication reverted; 2-PREAMBLES/README.md, docs/GUIDE.md,
0-UNRESTRAINT-PACKS/README.md synced (web agents route to AIO-INSTRUCTION - Web.md;
MANUAL-PASTE is the persona paste); changelog links to the retired per-version
notes repaired to tag permalinks; GENERAL-1 prompt regains "and its design is up
to you".
8.53.0 (2026-11-16): debloat - every provider installs from _CANONICAL-SKILLS (six
generated skill copies, 3,600 files, removed); dead templates, copy maps, workspace
instruction copies, mega pack and docs/history retired; release body cut from
CHANGELOG.md; 2-PREAMBLES rename, preamble archive and four root docs retired;
owner's four GENERAL prompt files added.
8.52.0 (2026-11-15): forges self-register through uabs-companion.json (no bundle
release for a new forge or launcher); TOOLS/field_report.py records a forge defect in
the owner folder (rule in the contract, ai-tooling-stack, forge standard);
MarvelRivals-Forge registered and routed.
8.51.1 (2026-11-15): catalog Unity install command matches 1.11.1; freshness check
recorded (22 current, 3 held, Blender 2.3.0 / Unity 1.11.3 under a day old, not
adopted); installed hooks, settings and six provider skill homes verified live.
8.51.0 (2026-11-15): stop gates honour stop_hook_active (no repeated blocks);
prompts merged into PROMPTS/START-RESUME-UPGRADE.md; docs gate checks Markdown
links per page (41 dead GUIDE links fixed); workspace template states each rule
once; codebase-memory skill split (indexing/install in a reference).
8.50.1 owner audit (2026-11-15): baseline green (gate 23/23, CI, doctor). Fixed:
Claude routing ignored native-plugin skills (Superpowers never suggested); leftover
cleanup exited 0 on failed removals and could edit a provider config whose backup
failed; the local gate lacked ten CI contracts, the Core artifact check and four
orphaned tests (now held by `TESTS/test_gate_parity.py`); duplicated GUIDE/README
markup; six dead PowerShell helpers. Open gap: no uninstaller (documented).
Final audit: the local gate stages and release contracts passed, including
Windows-path, awkward-path launch and MCP parsing regressions. Installed-state
diagnostics passed.
Exact-commit CI and downloadable build receipts remain the release evidence.
8.44.7 audit: install-time cleanup now also removes older-version leftovers
(backups only by retention), and ponytail "off" switches its Claude/Antigravity
plugin off; sandboxed tests no longer reach real provider folders.

Older release notes: `CHANGELOG.md` and git history.
