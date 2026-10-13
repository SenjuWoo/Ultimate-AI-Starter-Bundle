# Bundle audit state

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
