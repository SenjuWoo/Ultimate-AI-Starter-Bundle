# Phase 2 report - intelligent skill integration

Version 8.38.0. Two MIT packs evaluated; 12 of their 64 skills installed on request,
the rest deliberately skipped with a reason.

## What was added

| Piece | What it does |
| --- | --- |
| `TOOLS/recommended_skills.py` | Installs a curated, namespaced (`pocock-`, `addy-`) subset from a pinned SHA, copies the shared `references/` addy's links need, records a receipt and can remove exactly what it added. |
| `docs/RECOMMENDED-SKILLS-PACKS.md` | Per-skill integration matrix: upstream skill, existing bundle equivalent, decision, reason. |
| `TOOLS/task_route.py` | Deterministic one-workflow router: request -> one primary workflow + specialists. No model call. |
| `capability-routing` (canonical + six provider copies) | "Choosing the workflow" section and the continuity pointer to `task_state.py`. |
| `TESTS/test_recommended_skills.py`, `TESTS/test_skill_routing.py`, `TESTS/test_task_route.py` | 7 + 6 + 12 cases; installed-state, routing and scenario behaviour. |

## What was intentionally omitted

- **The full packs.** 64 skills would add 64 descriptions to every request and duplicate
  TDD, debugging, planning, review and lifecycle owners the bundle already has.
- **Addy's lifecycle and interview skills** (`interview-me`, `planning-and-task-breakdown`,
  `spec-driven-development`, …): Superpowers already owns that pipeline; two routers is
  the conflict Phase 2 exists to prevent.
- **Pocock's interactive workflows** (`grilling`, `wizard`, `loop-me`, `wayfinder`): they
  interview by design and must not become mandatory for ordinary requests.
- **`frontend-ui-engineering`**: `impeccable` owns frontend UI here.
- **Any automatic issue, PR or external artifact creation**: unchanged, still requires
  explicit authorization.

## Routing model

`task_route.py` is a lookup over named signals, not a classifier and not a second router.
It always returns exactly one primary workflow (`lightweight`, `requirements-pass`,
`superpowers-autonomous`, `lifecycle`) and borrows specialists. Ambiguity buys one
requirements pass, not an interview loop; an authorized long run gets no checkpoints
until blocked; a security or release surface promotes a "simple" change to the lifecycle.

## Context overhead

| Measure | Before | After |
| --- | --- | --- |
| Canonical skills | 81 | 81 |
| Skill description bytes per provider tree | 12,705 | 12,705 (unchanged) |
| Always-on instructions added | 0 | 0 |
| Optional packs pre-installed | - | none (install on request only) |

## Provider compatibility

- Claude honours `CLAUDE_CONFIG_DIR`; Codex, Grok, Kimi, Hermes and Antigravity use their
  existing skill roots.
- Addy's `../../references/<file>` links resolve because the shared checklists land at
  `<provider>/references/`; verified by resolving the link after a real install.
- Nothing assumes a provider-specific `Skill` tool: the packs install as plain skills.
- No native plugin is installed alongside a copied equivalent.

## Tests

- `test_recommended_skills.py` 7/7 - pure plan, namespacing, shared references, backup
  instead of overwrite, receipt-scoped removal, refusal without a receipt, custom Claude dir.
- `test_skill_routing.py` 6/6 - one owner per scenario, no pack pre-installed in any
  provider tree, no duplicate skill names, detect-only registry entries, no optional skill
  shadowing a bundle skill, usable metadata.
- `test_task_route.py` 12/12 - the addendum's scenarios, determinism, single primary.
- Release contracts 175/175; release gate green; real install and installed-state doctor
  green; Ponytail OFF unchanged (0 bytes from the hook, 0 leaks).

## Correctness pass before release

- **Repeated installs.** A receipt records the paths this tool created. Reinstalling
  replaces its own copy instead of backing it up, so `install -> install -> remove`
  restores the user's original byte for byte with one backup and no nested
  `.backup-*` folders. Receipts are keyed by destination root (two homes never mix) and
  rewritten after every item, so an interrupted run is still removable. 12 installer
  tests cover repeats, interruption, two homes, backup-restore and refusal without a receipt.
- **Discovery agrees with the router.** Installed skills carry a namespaced `name:` equal
  to their directory (`addy-security-and-hardening`), plus `license: MIT` and
  `upstream: <repo>@<pin>`; the router resolves `security-and-hardening` to that exact
  installed skill and reports `bundle` / `installed` / `fallback`.
- **Routing is not keyword-only.** A request is only interviewed when it is vague *and*
  thin: a `detail` score (length, named files/commands, acceptance words, numbers) keeps a
  concrete work order from being derailed by the word "idea". Conflict rules: a "quick"
  fix that touches auth still runs the lifecycle; an unattended run with a concrete goal
  gets no checkpoints.
- **No dead specialists.** Every optional specialist has an installed fallback
  (`security-and-hardening` -> `code-review-skill`, `observability-and-instrumentation`
  -> `observability-first`, `context-engineering` -> `token-efficiency`, `to-spec` /
  `codebase-design` -> `writing-plans`, `triage` -> `systematic-debugging`,
  `writing-for-agents` -> `skill-creator`, `impeccable` -> `popular-web-designs`).
- **Licensing.** Both packs' LICENSE files are installed at
  `<provider>/references/<pack>-LICENSE.txt`, and each installed skill's frontmatter names
  the licence and the upstream pin.
- **Durable install.** Copies are staged beside the destination and swapped in under a
  journal phase; a crash discards staging, removes an uncommitted destination and puts
  the user's original back. Fault-injection and partial-destination tests cover it.
- **Token disambiguation.** LLM token/context cost requests no longer reach
  `security-and-hardening`; credential tokens still do.

## Remaining limitations

- No live conversational turn was run inside each of the six providers; the evidence is
  the installed file layout, the resolved links and the doctor's checks.
- Upstream packs move: the pins are recorded and `TOOLS/check_upstream_drift.py` reports
  when they do, but updating is a deliberate re-run, never automatic.
- Pack skills are copied, not vendored: a new upstream revision requires
  `recommended_skills.py install` again.
- Pocock's `domain-modeling` etc. are only present when installed; the bundle's own 81
  skills remain the always-available baseline.

## Post-release corrections (v8.38.1)

- Provider availability is real: the router scans the selected provider's skills
  directory, labels source-only skills `source`, and reports `unavailable` rather than
  claiming an install that is not there.
- Security and token-cost detection are independent signals; a mixed OAuth + token-cost
  request stays a security lifecycle.
- `install` requires `--apply`, like `remove`.
- Workflow selection is automatic: a Claude `UserPromptSubmit` / Hermes `pre_llm_call`
  hook injects one routing line only when the route is not the default lightweight one,
  installed outside the repo so it works from any project directory.
