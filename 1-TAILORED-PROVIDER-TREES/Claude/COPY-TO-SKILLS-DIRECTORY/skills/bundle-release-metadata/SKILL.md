---
name: bundle-release-metadata
description: "Use when shipping a bundle change or fixing a red manifest/version CI gate."
version: 1.0.0
author: Ultimate-AI-Starter-Bundle
license: MIT
metadata:
  hermes:
    tags: [release, ci, manifest, maintenance]
    related_skills: [ci-convergence, release-checklist]
---

# Bundle release metadata

## When to Use

- You are about to commit a change to any shipped file in this bundle.
- CI is red on `MANIFEST verifies against the tree`, a version string, or a docs gate.
- You regenerated a preamble, an instruction archive or a bundled payload.

## Rule

Generated files are never hand-edited, and one of them (MANIFEST.json) is what
`TOOLS/build_release.py` uses to decide what ships. A stale manifest is a
missing file in the release, not a cosmetic diff.

| Generated | Producer |
|---|---|
| `MANIFEST.json` | `python TOOLS/generate_manifest.py .` |
| `3-PREAMBLES/history/*` | `python TOOLS/generate_preamble_history.py` |
| `BUNDLED-TOOLS/packs/*/legacy/*` | installer archive step |
| `BUNDLED-TOOLS/{CATALOG,PROFILES,OFFLINE-MANIFEST}.json`, `VALIDATION.json` | release stamps |
| `VERSION.txt` | single source for the installer banner and `install-state.json` |

## Order of operations

1. Edit content, then fan out skills: `python TOOLS/fanout_providers.py _CANONICAL-SKILLS .`
2. Archive preambles: `python TOOLS/generate_preamble_history.py`
3. Regenerate `MANIFEST.json` **last** — a local install or a test run can create
   a new archive after you generated it.
4. Run `TOOLS\Refresh-Release-Metadata.ps1`, then `TESTS\Test-Pack.ps1`.

## Red CI on the manifest

```
python TOOLS/generate_manifest.py .
python .github/scripts/verify_manifest.py
git add MANIFEST.json && git commit -m "<version>: regenerate manifest" && git push
```

`ci.yml` now refreshes the manifest before the tests, so a stale committed copy
cannot fail the run; the gate still fails when a recorded hash does not match a
file, which is the case that matters.

## Architecture decisions

`docs/decisions/` holds one ADR per decision a future maintainer could undo by
accident, indexed in `docs/decisions/README.md`. A new record needs context,
options, decision, evidence, consequences and a revisit trigger; the
maintainability audit fails a record missing any of them.

Before changing an invariant, read the ADR that owns it. If the decision has
changed, write a new ADR that supersedes the old one; do not silently rewrite
history.

## Maintainability audit

`python TOOLS/audit_maintainability.py . --strict` reports duplicate
non-generated files, skills over 500 lines, orphaned tools and TODO markers.
Known mirrors (workspace AIO, hook plugin copy, LICENSE) are allowlisted by
path. The pack gate runs it, so a new hard duplicate fails CI.

## Pre-push hook

`.\TOOLS\Install-GitHooks.ps1` writes `.git/hooks/pre-push`: it refreshes the
metadata and refuses the push when `MANIFEST.json` changed, so the commit that
would have been red never leaves the machine.
