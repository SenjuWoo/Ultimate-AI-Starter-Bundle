# Free tooling and verification tiers

Audit date: **2026-11-05**. Nothing below is installed by the bundle unless it
is already on the operator's PATH. FAST verification uses only PowerShell and
the shared Python; optional linters are probes, not requirements.

## Current inventory

| Layer | What exists | Gap found |
|---|---|---|
| PowerShell syntax | AST parse in `Verify-Fast.ps1` (new) | no linter, only parse |
| Python syntax | `py_compile` in FAST; full tests in the pack gate | no style lint |
| JSON | `ConvertFrom-Json` on changed files | schema validation absent |
| Workflows | release-provenance contract; no YAML lint | actionlint absent |
| Docs links | `verify_docs.py` checks local links | external URL checking absent |
| Tests | 161 contracts + pack gate | no incremental selection |
| Git hooks | pre-push metadata guard | no pre-commit hook |
| Caching | content-hash cache for FAST (new) | build cache in CI only |

## Adoption matrix

| Tool | Source | Licence | Windows | Decision | Why |
|---|---|---|---|---|---|
| actionlint | github.com/rhysd/actionlint | MIT | yes (single exe) | **optional probe** | catches workflow schema errors the release contract cannot see |
| Ruff | github.com/astral-sh/ruff | MIT | yes | **optional probe** | fast Python lint; not installed to keep the base free of a Rust runtime requirement |
| check-jsonschema | github.com/python-jsonschema/check-jsonschema | Apache-2.0 | yes (Python) | **not adopted** | the only schemas are the pack's own JSON, already parsed by FAST |
| ast-grep | github.com/ast-grep/ast-grep | MIT | yes | **rejected for now** | duplicates grep/rg for every current search need |
| lychee | github.com/lycheeverse/lychee | check repo | yes | **not adopted** | `verify_docs.py` owns link policy; a second link checker would disagree |
| hyperfine | github.com/sharkdp/hyperfine | check repo | yes | **manual only** | useful for one-off benchmarks, not a gate |
| watchexec | github.com/watchexec/watchexec | check repo | yes | **manual only** | a watcher must be started by the operator, never by install |
| prek | github.com/j178/prek | check repo | yes | **rejected** | the existing pre-push hook is smaller and has no runtime |
| PSScriptAnalyzer | github.com/PowerShell/PSScriptAnalyzer | MIT | yes (module) | **optional probe** | duplicate of parse for now; adopt when a Windows PS 5.1 rule is needed |
| Biome / ty | biomejs.dev / docs.astral.sh/ty | check repo | yes | **not adopted** | no JS/TS app and no type checking need in this pack |

"Check repo" means the licence was not verified in this audit; verify it at the
official repo before installing. No tool is vendored or auto-installed.

## Verification tiers

| Tier | Command | Covers | Never replaces |
|---|---|---|---|
| FAST | `.\TOOLS\Verify-Fast.ps1` | changed-file PowerShell parse, Python compile, JSON parse, optional linters; content-hash cache in `.uabs-cache/verify` | pack gate |
| FULL | `.\TESTS\Test-Pack.ps1` | every regression suite and gate | CI |
| RELEASE | `.\TOOLS\Verify-Release.ps1` | metadata refresh + FULL | exact-SHA CI and the release workflow |

`Verify-Release.ps1` adds no checks: it runs the same mandatory gates in the
same order and prints one verdict. Incremental checking is an inner loop only.

## Measured baseline

| Action | Before | After |
|---|---|---|
| Syntax check of 3 changed scripts | full pack gate (~4-6 min) | FAST parse (<2 s), cache hit on re-run |
| Workflow YAML errors | found by reading CI logs | found locally by actionlint when installed |

No token or cost saving is claimed: FAST runs locally and calls no model.
