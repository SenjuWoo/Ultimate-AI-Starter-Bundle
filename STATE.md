# Bundle state

## Current verified state

| | |
|---|---|
| Release | `VERSION.txt` and the git tag are the only source; a contract test fails if this row disagrees with `VERSION.txt`. no literal version is kept here on purpose |
| Branch | `main`, in sync with `origin/main` |
| Next version | the next patch after `VERSION.txt`; nothing to edit here |
| Next action | whatever the Done/Next section below lists; this header stores no release fact it could contradict |
| Evidence | `python TESTS/test_release_contract.py`, `python TESTS/test_task_state.py`, `TESTS/Test-Pack.ps1`, `gh run list --commit <sha>` |

- Done and verified: reliability pass in 8.36.0/8.36.1 (atomic version bump,
  receipt-gated cleanup, verified remote installs, reachable release recovery,
  gateway-guard ownership and exit codes, honest tool states) and the public-text
  / last-review rules in every instruction form.
- This pass: skill evaluation works on Windows and reports a missing provider
  instead of faking a result; the project template carries the memory contract and
  a vision contract with a binding corrections table; `code-review-skill` has an
  advisory concern radar; `skill-creator` has a capture checklist; release-file
  guidance matches Core vs Full-Offline.
- Roblox ownership resolved: the 23 skills and the 23 briefs live in
  RobloxForge (`skills/`, `docs/roblox-briefs/`, MIT + notices, 0.13.6) and the
  bundle no longer carries either. The earlier local copy was lost while
  untracked; it was re-fetched from the upstream repository and committed there.
- Held out of the bundle: 23 untracked Roblox skill directories plus an MIT
  licence file (EL4CTEO) appeared in `_CANONICAL-SKILLS/` on 2026-11-06. Roblox
  skills belong to RobloxForge and the pack was not credited, so they were moved
  to `Incoming/roblox-skills-2026-11-06/` with a WHY.md instead of shipping.
- Hermes config finding: the installed config uses `max_turns: 150`,
  `hard_stop_enabled: false` and `creation_nudge_interval: 15`, while the shipped
  starter keeps `null`, `true` and `0`. The live values are the operator's own, so
  nothing was changed; `compression.threshold_tokens` is a cap on the ratio
  trigger, not a floor, and was left alone.
- Next action: run the gates and publish 8.37.3.

Older sections below are the history this state summarises; anything marked
"not implemented" is superseded by the entry that implements it.

## History

Release notes before this trim: `docs/history/STATE-ARCHIVE-2026-11-07.md`. Older releases: `docs/history/V<version>-CHANGELOG.md`.
