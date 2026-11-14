# ADR-0009: Domain skill families list by name only outside their work

Status: accepted
Date: 2026-11-13

## Context

Every installed skill puts its name and description in front of every request.
On one fully installed machine Claude listed 183 skills in about 42,700
characters of descriptions (roughly 10,700 tokens) on every turn. Claude Code
caps the listing at 2% of the context window and drops what does not fit, so on
a 200k window most skills were never shown at all.

A usage scan of 39 Claude transcripts found the weight concentrated in domain
families that were never invoked: 24 Roblox specialists (only their router was
used), Unity's 35 published skills and the 10-step Replica pack. Hermes had the
same problem per profile: profile creation clones the default profile's skills,
and RobloxForge installs into every profile, so the Skyrim, Unity, web and
SillyTavern profiles each carried 25 Roblox skills, and the roblox and web
profiles carried 47 Skyrim skills.

## Options considered

- Delete or move the family folders, and copy them into a project when needed.
- Rewrite each forge's skills into one router with references.
- Use each host's own listing control: Claude Code's `skillOverrides`
  (`name-only` keeps the skill callable and drops its description) and Hermes'
  per-profile `skills.disabled`.

## Decision

Use the host controls. `BUNDLED-TOOLS/SKILL-SCOPE.json` names the families,
their owners and the entry points that keep their description (the Roblox
router, `skyrim-tool-router` and `skyrim-memory`, `unity-cli`,
`new-unity-project`, Unity's ambiguous `ui`, `replica-recon`).
`TOOLS/skill_scope.py --fix`, run by the installer:

- writes `name-only` for the other family members into Claude's
  `skillOverrides`;
- adds the families a Hermes named profile does not own to that profile's
  `skills.disabled` through Hermes' own config API. The default profile is the
  generalist and is not changed. While the Hermes gateway runs, the change waits.

Nothing is deleted or moved, and forge reinstalls cannot undo it. A name matching
the policy's `protected` pattern (adult and roleplay skills) is never touched.
A user's own override always wins, only receipted entries are ever removed, and
`--undo` removes them and is remembered across reinstalls.

Rewriting forges into routers was rejected for now: it changes every provider's
install and each forge's tests for a saving the host controls already give.
Moving folders was rejected because it takes skills away from a session that
needs one by name.

## Evidence

- Claude listing on this machine: ~42,690 -> ~21,887 description characters
  (66 skills name-only), measured by `skill_scope.py`.
- 8.44.7 added the Skyrim family to Claude's name-only list: its 50 specialists
  carried ~8,400 description characters into every session, Skyrim or not, while
  the always-loaded Skyrim block already names the router and memory skills.
  Planned listing: ~21,600 -> ~14,150 characters. Hermes already disabled the
  family outside the skyrim profile.
- Hermes: 8 profiles changed; `hermes -p skyrim skills list` reports
  `roblox-ui` as `disabled`.
- `TESTS/test_skill_scope.py`: router kept, protected names untouched, user value
  wins, undo exact and remembered, a skill that leaves a family is given back,
  Hermes profile ownership, profile-scoped `HERMES_HOME` resolved to the root.

## Consequences

- A name-only skill is invisible to description matching; the family router or
  the project context has to name it. Routers and `ai-tooling-stack` already do.
- A new domain family is one entry in the policy file.
- Other providers (Codex, Grok, Antigravity) have no equivalent control yet and
  keep full listings.

## Revisit when

- A host adds a per-project or per-task skill set the bundle can drive, or
  Codex/Grok gain a listing control.
- A name-only skill is shown to be missed in real sessions; then keep its
  description.
