# Bundle audit state

## v8.14.0: parked task servers, history, shadowing launchers (2026-10-15)

- Resumed after Claude's session store was wiped by BleachBits (2026-10-13; the
  owner's own report in the Codex thread). Surviving record: Codex thread
  01a0461a (Claude summaries imported). Private digests (user messages,
  assistant turns) live in the owner's AI history folder, never in this repo.
- Measured leak: Claude user scope held github, rimworldforge, avatarforge,
  melty; Codex avatarforge, melty, github; Grok and Kimi github; Hermes default
  avatarforge, github. The old doctor knew only catalog components.
- Built: `global_scope_guard` (PROFILES.json), `TOOLS/UABS-Mcp-Park.ps1`,
  `Set-McpProfile.ps1 -Park/-Unpark` and parked restore in `-Auto`, installer
  park step, doctor leak check (Hermes = warning only), GitHub skipped where gh
  is signed in (`Test-UabsGithubMcpParked`, shared with the install handshake),
  `github` project profile. npm duplicate cleaner covers both prefixes with a
  verified recovery copy; doctor checks the PATH-first launcher. Copy-only
  `Backup-AiHistory.ps1`, Claude `cleanupPeriodDays` 365. Store-stub python no
  longer counts as Python (installer runtime check, Build-Release); machine map
  names the real interpreter. project-intel mashup card + workflow-scoped
  lessons; coding-discipline read-first/no-unchanged-retry; prompts polished.
- Gates: release contracts 145/0, Test-Pack PASS (before the Python-resolver
  and machine-map edits; rerun on the final tree), McpPark/NpmDuplicate/
  AiHistoryBackup gates PASS, privacy + audit regressions PASS.
- Live machine: parked Claude rimworldforge/avatarforge/melty/github, Codex
  avatarforge/melty/github, Grok and Kimi github (exact copies in
  %LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\parked-mcp.json); all other
  ~/.claude.json content hash-identical before/after. CodeBurn 0.9.23 removed
  from the user npm prefix (recovery copy in npm-rollback); 0.9.27 now first.
- Owner decisions to confirm: GitHub server parking (undo:
  UABS_KEEP_GLOBAL_MCP=github), Melty parked (unpark per mashup project),
  Hermes default entries reported only, Desktop Commander is a Claude Desktop
  extension the pack does not own. Git Bash `python` is the Store stub: the
  durable fix is the owner's (App execution aliases off).
- Gates on the final tree: Test-Pack PASS, contracts 145/0, privacy/audit/
  Hermes bootstrap PASS.

## Publication checkpoint (v8.14.0)

- Tag `v8.14.0` -> `7ed2704b4b4ea0da27563a5e98be478eee222ced`. CI (pack gate,
  Forge end-to-end, versions, manifest) and CodeQL success on that SHA; GitHub
  flags clean before and after publishing.
- Archives built twice, byte-identical: Core 47,008,073 B `d0dade94...a59e`,
  Full-Offline 204,646,057 B `7174bea0...3f3a`. Each extracted under a
  space+Unicode path: Test-Pack PASS, contracts 145/0. Published assets
  downloaded and equal to the build (size, SHA-256, GitHub digest); latest =
  v8.14.0. Receipts: ignored `artifacts/release-v8.14.0/build-proof.json`,
  `published-proof.json`.
- Local sync `INSTALL-AIO.ps1 -SkillsOnly -SkipSelfUpdate -Mode BundledOnly`:
  installed-state doctor PASS (Hermes default avatarforge/github remain
  warnings). Claude retention 365 merged; machine map names the real Python;
  first history copy 1.7 GB to the owner's history folder (HISTORY-DIR.txt).
- Not certified: provider inference, editor/game runtime, billed savings.
- Next: owner's call on the decisions above; Hermes default-profile parking
  needs a Hermes-native design (closed app, named-profile restore).

## Publication checkpoint (v8.13.0)

- Immutable release tag: `v8.13.0` at
  `7b7ae62d00506ac6d8287ca2cbee6d2896b06ae2`. All eight exact-commit checks,
  including CodeQL and clean Windows installation, passed; GitHub flags clean.
- Source Windows pack/live-install gates PASS, 143 release contracts and
  15 executable regressions PASS. Local installed-state doctor PASS at 8.13.0;
  all 173 skills accounted for on every provider, including verified overrides.
- Authoritative publication/download state:
  [GitHub v8.13.0](https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.13.0).
  Local-only build and downloaded-byte receipts are
  `artifacts/release-v8.13.0/build-proof.json` and `published-proof.json`.
  Verify those against the tag/assets on resumption; do not recreate a release
  from older pending-work notes. A matching published receipt closes that work.
- Main may include this documentation-only checkpoint after the release tag;
  archives are built from the exact green tag, never an unrecorded dirty tree.

## v8.13.0 audit: on-demand reverse engineering and usage discipline

- Baseline is published v8.12.1 at `4763fc0`; main also records publication.
  Do not recreate that release or trust superseded pending-release notes.
- Canonical and live provider skill parsing sweep found no failures. The
  auditor accepted missing/empty trees and invalid UTF-8; three real CLI
  regressions reproduced the bugs, then passed after repair. Index sizes are
  estimates, not actual loaded or billed tokens.
- REA 6.4.0 isolated install (lifecycle scripts disabled) and help PASS;
  production dependency audit reports zero known vulnerabilities. MCP transport
  exposes 170 tools / 1,954,683 compact UTF-8 schema bytes. No global registration,
  upstream setup, target execution or native-engine certification. CLI-first.
- Accepted tested updates: Universal Modder `5ba8150`, Ponytail 5.2.0,
  Context7 4.4.1, Serena 2.0.0 and RTK 1.0.0's Apache-licensed OSS build.
  Preserved Windows/privacy/security patches; upstream global RE setup and
  the unbounded UE3 fallback are not shipped. No new indexed skill entry.
- Native Windows pack gate PASS; strict PyYAML frontmatter sweep PASS for
  canonical and all five installed trees. Ponytail 136 + 31 tests PASS;
  Universal Modder 133 PASS / one deliberately unshipped session-hook skip.
  Smaller executable regressions, fixed RTK corpus/rewrites and three Serena
  client-context transport probes passed. No inference/billing/runtime claim.
- Source/release contracts PASS (143/0); source manifest verifies 8,843 entries.
  Removed the intentionally excluded helper from generated trees/index.
- Reproduced a migrated Grok ledger retaining project-bound Serena globally.
  Repair now retires only a matching recorded duplicate after scoped wiring,
  preserving personal/global-policy variants and dry-run bytes. Native profile
  gate failed before the fix and passed after it. Installed Serena 2.0.0 uses
  the normal user tool home, not the isolated probe prefix.
- Resume publication from the checkpoint and receipts above; the audit notes
  below are dated evidence, not a separate unfinished release plan.
- Final refresh: 22 current components, seven explicit holds. Firecrawl
  3.29.1 and candidate 3.30.0 have known high-severity dependency findings;
  suggested 3.24.0 fallback is not clean either. Block new installation and
  registration; doctor reports active held entries without deleting personal
  configs. This machine has no registered Firecrawl server. No credentials or
  remote scraping calls were used. Recheck upstream before lifting the hold.
- Local v8.13.0 selected-component install and final installed-state doctor
  PASS; all 15 core provider/server handshakes passed. Bounded leftover plan
  found nothing to remove. Grok's recorded duplicate global Serena is removed
  after the project copy is verified; matching parsed arguments differed only
  by a valid trailing array comma. Quoted whitespace remains significant.
- Removed one complete matching orphan-tagged private-profile duplicate from
  the live Codex instruction file, with an exact backup (4,828 bytes less).
  Differing personal text stays; the actual writer fixtures cover both cases.
- Source reports: ignored `artifacts/audit-20261013-*`. Never publish private
  provider configs, local paths or conversation exports. Default-sandbox pack
  test hit NTFS junction access restrictions; needs a real Windows rerun.

## v8.12.1: private-profile review and safe refresh

- Resumed against the clean v8.12.0 tree, not the superseded v8.11.1 plan.
  Verified the public v8.12.0 release, exact-commit CI and clean security flags.
- Found local state still at v8.11.1, with unrestraint-packs stale on all five
  providers. Ownership-aware skills/instruction refresh completed for v8.12.1;
  installed-state doctor PASS, all 173 skills accounted for on each provider.
- Reproduced and fixed the installer removing an existing profile on oversized
  input. The actual installer-section regression now preserves original bytes.
- Removed maintainer workspace paths from portable skills/references. Added
  private-workspace path regression coverage; all twelve audit regressions pass.
- Public profile guidance is portable; private working preferences and chosen
  folders stay outside the repository. Preserved model choices, native ownership,
  local skill overrides, roleplay persona and the previous profile's rollback copy.
- Corrected preset filenames/docs; JSON parses for all 47 generator entries and
  the three Tavern preset files. GPU/frontend operation is not certified.
- Final Windows pack suite PASS, release contracts 143/0 and twelve audit
  regressions PASS, including junction cleanup. Privacy, version agreement,
  preamble history and all 8,794 manifest entries verify.
  Private profile deployment has a byte-verified rollback copy. The operator
  explicitly confirmed the newer Tavern preset belongs in this release; include
  it byte-for-byte. Preserve gateway configuration and promote only portable
  improvements, never private model selections or runtime state.
- A later local refresh recreated Codex skill duplicates with broken blanket
  provider-name replacements. All 22 copies were backed up and verified;
  ownership reconciliation and Codex doctor PASS (191 index entries).
- Junction cleanup now refuses ordinary directories and handles live/dangling
  NTFS junctions without touching their target. Both former failures were
  reproduced in disposable fixtures before repair. Public-path scan PASS.
- Publication checkpoint: the authoritative status is the v8.12.1 GitHub tag,
  its exact-commit checks, release assets and downloaded-byte verification.
  On resume, inspect that release before assuming publication is unfinished.
  Release proof is recorded locally under ignored `artifacts/`; private profile
  contents and logs remain outside the payload. Never publish from a pending SHA.

## Publication (v8.12.1)

- Recovered from the Codex thread after chat loss: v8.12.1 was pushed (`dc05b1b`)
  with CI green but untagged. Added the build-hygiene rules (code comments +
  `STATE.md` recovery note in the AIO full/Compact, detail in `coding-discipline`,
  `state-resumption`, `observability-first`); pinned preamble digest updated,
  outgoing AIO archived in `3-PREAMBLES/history/`.
- Released 2026-10-13 from commit `4763fc0` (CI + CodeQL green on that SHA; flags
  clean). Tag `v8.12.1` -> `4763fc0`. Core 46,663,920 B `a4f9dad2...`,
  Full-Offline 203,100,613 B `4a709d72...`; downloaded assets byte-equal to the build.
- Local sync: `INSTALL-AIO.ps1 -SkillsOnly -SkipSelfUpdate -Mode BundledOnly`;
  installed-state doctor PASS; one copy of the new rule in all five provider files.
- Not certified: no paid inference, host-editor interaction or game runtime.

## Previous baseline: v8.12.0

- Trimmed the preamble family: deleted the orphaned `GPT-WEB-AIO-BACKUP.md`,
  removed four retired upstream jailbreak collections (~3.6 MB, reviewed
  first — nothing durable left to fold in), trimmed story-era residue from the
  Web / Web Light / Compact variants. `SOUL.md` and the full AIO are
  byte-unchanged (wired-preamble digest does not move).
- Repaired the live wires on this machine: all 14 targets recomposed to
  `[profile block] + [SOUL] + [AIO]`, a single copy of each layer (the Hermes
  side had an older soul edition behind the current one; exact-match removal +
  the bundle's own writer). SillyTavern roleplay profile untouched by design.
  Pre/post backups in `%LOCALAPPDATA%\hermes\cache\scratch\live-backup-20261012\`.
- Docs: 3-PREAMBLES README gains the three-layer composition + never-hand-edit
  rule; `unrestraint-packs` skill (1.1.0) and pack README rewritten; root
  README stale version tags dropped.
- Rolls up the unreleased v8.11.1 audit commit (`548d3e8`).

## Previous baseline verification (v8.12.0)

- Contract 143/0; privacy PASS; audit PASS (0 fail, 6 warn); check_versions
  agree; MANIFEST 8,789 files, verified 0 missing / 0 mismatch; preamble
  history `--check` PASS; Test-Pack run for this commit.

## Publication (v8.12.0)

- Released 2026-10-12 from commit `c3ab514` (CI + CodeQL green on that SHA;
  GitHub flags clean at release). Tag `v8.12.0` was re-pointed twice before
  publication while no release existed, final object on `c3ab514`.
- Assets byte-verified after upload: Core `3a9be1d7…` (46,748,082 B),
  Full-Offline `c6b279eb…` (203,164,446 B).
- Repo topics refreshed for reach (candidates measured by search counts).
- No paid inference, host-editor interaction or game runtime is certified.

Detailed machine-specific reports remain under ignored `artifacts/`.
