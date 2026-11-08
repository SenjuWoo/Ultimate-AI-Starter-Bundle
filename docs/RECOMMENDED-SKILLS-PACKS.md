# Recommended skill packs: mattpocock/skills and addyosmani/agent-skills

Both repositories are MIT, actively maintained, and larger than they look: 39 and 25
`SKILL.md` files. Installing them wholesale would put 64 extra skill descriptions in
front of every request and duplicate owners the bundle already has (code review,
debugging, TDD, planning, review). So the bundle does **not** vendor them. It offers a
curated, namespaced subset that is installed on request, pinned, and removable.

```
python TOOLS/recommended_skills.py list
python TOOLS/recommended_skills.py install pocock --provider claude --apply
python TOOLS/recommended_skills.py install addy   --provider hermes --apply
python TOOLS/recommended_skills.py remove  addy   --provider hermes --apply
```

Providers: `claude`, `codex`, `grok`, `kimi`, `hermes`, `antigravity`. Claude honours
`CLAUDE_CONFIG_DIR`.

## What is installed, and why

Everything installed is prefixed (`pocock-`, `addy-`), so it can never shadow a bundle
skill, and every item is recorded in a receipt under
`%LOCALAPPDATA%\\Ultimate-AI-Starter-Bundle\\recommended-skills\\`. An existing skill of
the same name is moved to a `.backup-<utc>` folder first; `remove` deletes only what the
receipt lists and puts the backup back.

| Upstream skill | Bundle equivalent | Decision | Reason |
| --- | --- | --- | --- |
| pocock `domain-modeling` | none | **install** | Glossary and ADR discipline is a genuine gap; the bundle has no owner for vocabulary drift. |
| pocock `codebase-design` | `reverse-engineering` (binary focus) | **install** | Module boundaries and interface shape have no owner; `reverse-engineering` is about reading code that exists, not designing it. |
| pocock `to-spec` | `writing-plans` | **install** | Turns a conversation into a spec file; `writing-plans` starts after the spec exists. |
| pocock `triage` | `systematic-debugging` | **install** | Issue triage and severity is not the same job as root-causing one bug. |
| pocock `retro` | none | **install** | No post-task retrospective owner. |
| pocock `writing-for-agents` | `skill-creator` | **install** | Wording of pointers and instructions; `skill-creator` covers packaging, not prose. |
| pocock `tdd`, `code-review`, `implement`, `research`, `grill-with-docs`, `grilling`, `wizard`, `wayfinder`, `pr`, `prototype`, `improve-codebase-architecture`, `implement-spec`, `to-tickets`, `handoff`, `teach`, `ask-matt`, `wait-what`, `to-questionnaire`, `setup-*`, `loop-me`, `software-factory`, `chief-of-staff`, `writing-*` | Superpowers TDD/debugging/planning/review, `brainstorming`, `handoff`, `state-resumption`, `writing-plans` | **skip** | Duplicates of owners that already exist, or interactive workflows (`grilling`, `wizard`) that must not become mandatory. |
| addy `security-and-hardening` | none | **install** | Real gap: the bundle has review checklists but no security owner. |
| addy `performance-optimization` | none | **install** | Real gap; includes a measurement checklist. |
| addy `observability-and-instrumentation` | `observability-first` (debugging discipline) | **install** | Different job: instrumenting a product vs debugging a failure. |
| addy `api-and-interface-design` | none | **install** | No API-contract owner. |
| addy `context-engineering` | `token-efficiency` | **install** | Context shape for agents; `token-efficiency` is about cost of a run. |
| addy `deprecation-and-migration` | `release-checklist` | **install** | Migration plans and deprecation windows are not in `release-checklist`. |
| addy `using-agent-skills`, `interview-me`, `idea-refine`, `planning-and-task-breakdown`, `spec-driven-development`, `incremental-implementation`, `test-driven-development`, `debugging-and-error-recovery`, `code-review-and-quality`, `code-simplification`, `doubt-driven-development`, `shipping-and-launch`, `git-workflow-and-versioning`, `documentation-and-adrs`, `browser-testing-with-devtools`, `ci-cd-and-automation`, `source-driven-development`, `constraint-driven-development`, `frontend-ui-engineering` | Superpowers lifecycle, `executing-plans`, `impeccable`, `ci-convergence`, `release-checklist`, `brainstorming` | **skip** | Overlapping lifecycle router and interview skills are exactly the duplication Phase 2 must avoid; `impeccable` owns frontend UI here. |

## Shared references

Addy's skills link shared files as `../../references/<file>`, which resolves to
`<provider>/references/`. The installer copies the referenced checklists there (not into
`skills/`), because a link that cannot resolve is worse than no link. Removal deletes
only the files the receipt lists.

## Repeat installs, updates and removal

A receipt lists every path this tool created and every path it moved aside. Reinstalling
the same pack replaces its own copy in place, so `install -> install -> remove` puts the
user's original skill back byte for byte, with one `.backup-<utc>` folder and no nesting.
Receipts are keyed by destination root, so two homes (or two providers) never share
state; the receipt is rewritten after every item, so an interrupted download is still
removable. `remove` deletes only receipt paths, then restores anything that was backed up.

Updating is a deliberate `install` at a newer pin, never an automatic overwrite. An
installed skill carries `license: MIT` and `upstream: <repo>@<pin>` in its frontmatter and
its directory name is also its `name:` field, so provider discovery and the router agree.

## If a pack is not installed

Every optional specialist has an installed fallback, so a task never stalls on a missing
pack: `security-and-hardening` -> `code-review-skill`, `observability-and-instrumentation`
-> `observability-first`, `context-engineering` -> `token-efficiency`, `to-spec` /
`codebase-design` -> `writing-plans`, `triage` -> `systematic-debugging`,
`writing-for-agents` -> `skill-creator`, `impeccable` -> `popular-web-designs`. The router
resolves names against what is actually present (`bundle`, `installed`, `fallback`) and
never returns a skill that does not exist.

## What this deliberately is not

- Not a second router: the packs add no always-on instructions and no plugin. They appear
  as ordinary skills only after you install them.
- Not a fork: nothing is edited, so updating means running `install` again at a new pin.
- Not automatic updates: the pin in `TOOLS/recommended_skills.py` is the recorded
  revision; `TOOLS/check_upstream_drift.py` reports when upstream has moved.

## Licence and provenance

| Pack | Licence | Pin |
| --- | --- | --- |
| `mattpocock/skills` | MIT | `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` |
| `addyosmani/agent-skills` | MIT | `301b02b12bff98e4688e6984af6556802322bbde` |

Both require their copyright and permission notice when redistributed. The pinned
tarball is fetched from `codeload.github.com` at that exact SHA; nothing upstream is
executed. Keep each repository's `LICENSE` beside the installed skills if you
redistribute them; the installer does not copy it automatically.
