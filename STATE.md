# Bundle audit state

## v8.12.0: unrestraint-family hygiene + live-wire repair

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

## Verification (local)

- Contract 143/0; privacy PASS; audit PASS (0 fail, 6 warn); check_versions
  agree; MANIFEST 8,789 files, verified 0 missing / 0 mismatch; preamble
  history `--check` PASS; Test-Pack run for this commit.

## Pending (external records)

- Exact-SHA CI and GitHub security flags; tag `v8.12.0`; Core + Full-Offline
  builds; published-asset SHA-256 equality. Publication is not complete until
  these return green.
- No paid inference, host-editor interaction or game runtime is certified.

Detailed machine-specific reports remain under ignored `artifacts/`.
