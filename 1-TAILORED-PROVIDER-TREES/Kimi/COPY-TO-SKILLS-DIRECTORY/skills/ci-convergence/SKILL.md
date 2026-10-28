---
name: ci-convergence
description: Use when converging exact-commit GitHub checks, branches and security alerts before merging or releasing.
---

# CI convergence

The authoritative unit is the **pushed SHA** and every required check attached
to that exact SHA. Local green is necessary, never sufficient; never substitute
the latest run for the required checks of the pushed SHA.

## One lifecycle

Local change -> commit -> push -> exact-SHA CI -> pass -> squash merge to main
-> main-SHA CI -> pass -> build/tag/publish -> download and verify shipped bytes.
Update README/changelog before the release commit; query security after every
push and before publication. `release-checklist` owns packaging/tag/publication
mechanics; this skill owns convergence.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File TOOLS/Wait-External.ps1 -GitHubRun auto -Repo OWNER/REPO -Sha FULL_SHA`.
`-Sha` defaults to HEAD; a numeric `-GitHubRun` must target it. All workflows,
check-runs, commit statuses and protected required contexts count. Polling has
backoff and a hard timeout; failure logs are capped.

| Verdict | Exit | Action |
|---|---|---|
| pass | 0 | Every required check reached a terminal successful state; tag/publish only that green main SHA. |
| fail | 1 | Inspect failing job/status; fix the cause, push a NEW SHA, re-converge. |
| pending | 8 | Wait to timeout, then report URL; never tag. |
| none | 2 | NO CI RAN. Do not release. Open PR or trigger supported CI. |
| unknown | 3 | Report command, bounded stderr and what settles it; never tag. |

A gh error is not a red check. Missing gh, auth, bad IDs, rate limits, network
and unreadable policy are unknown. `gh pr checks` also exits 8 for pending
(verify with `gh pr checks --help`). Skipped/neutral evidence requires policy
review; never silently accept cancelled, skipped, missing, stale or unknown checks.

## Branch policy

`main` is the only long-lived branch. Fetch/pull main; reuse the task's ONE
branch or create `type/short-slug`. Right after opening the PR, enable
`gh pr merge --auto --squash --delete-branch` so it merges itself once the required checks pass. Squash-merge
and delete it, or name its unfinished branch/PR and blocker at turn end. Never
merge red or force-push history. `TOOLS/Clean-MergedBranches.ps1` reports first;
`-Apply` deletes only proven merged branches, with conditional remote deletion.
Squash/superseded work requires PR/patch review, never forced deletion.

Prove ancestry with `git merge-base --is-ancestor BRANCH main` or inspect
`git log BRANCH --not main`; the reversed log legitimately contains later main
commits. Run the full gate on resulting main. Bundle releases publish themselves:
`.github/workflows/release.yml` runs after CI passes on a main commit whose
`VERSION.txt` has no tag yet, waits for every other check on that SHA, builds
twice, requires identical bytes, tags, publishes and re-downloads to compare.
A version bump is therefore the release request. Manual fallback:
`TOOLS/Build-Release.ps1`. Query security alerts after it publishes.

## Security gate

Run `TOOLS/Get-GitHubFlags.ps1 -Repo OWNER/REPO`, otherwise `gh api` per
[alert-query details](references/github-alerts.md). Dependabot, code-scanning
and secret-scanning must be clean. `flags=unknown` is not zero; fix the cause,
push, reconverge and query again. Do not dismiss alerts. Do not print secrets.
`code_quality=unavailable` stays off. Do not add OSV-Scanner, Gitleaks, or zizmor.
