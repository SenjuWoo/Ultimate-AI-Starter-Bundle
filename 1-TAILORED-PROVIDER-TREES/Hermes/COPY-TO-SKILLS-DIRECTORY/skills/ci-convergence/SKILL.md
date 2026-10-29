---
name: ci-convergence
description: Use when converging exact-commit GitHub checks, branches and security alerts before merging or releasing.
---

# CI convergence

The authoritative unit is the **pushed SHA** and every required check attached
to that exact SHA. Local green is necessary, never sufficient; never substitute
the latest run for the required checks of the pushed SHA.

## One lifecycle

Local change -> full local gate -> commit -> push to main -> exact-SHA CI -> pass
-> build/tag/publish that SHA (automated where a release workflow exists) ->
download and verify shipped bytes. Put changelog/version in the commit that is
the release; query security after every push and before publication.
`release-checklist` owns packaging/publication mechanics; this skill owns convergence.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File TOOLS/Wait-External.ps1 -GitHubRun auto -Repo OWNER/REPO -Sha FULL_SHA`.
It reads workflows, check-runs, commit statuses and the checks rulesets or
classic protection require; polling and logs are bounded.

| Verdict | Exit | Action |
|---|---|---|
| pass | 0 | Every required check reached a terminal successful state; release only that green SHA. |
| fail | 1 | Inspect the failing job/status; fix the cause, push a NEW SHA, re-converge. |
| pending | 8 | Wait to timeout, then report the URL; never tag. |
| none | 2 | NO CI RAN. Do not release. Push or dispatch the supported CI. |
| unknown | 3 | Report command, bounded stderr and what settles it; never tag. |

A gh error is not a red check: missing gh, auth, bad IDs, rate limits, network
and unreadable policy are unknown. Never silently accept cancelled, skipped,
missing, stale or unknown checks.

## Branch policy

`main` is the only long-lived branch. On a repository you maintain, pull main,
run the full local gate and push to main; a red main is fixed forward with a new
SHA, never force-pushed. Use one `type/short-slug` branch only where pull
requests are required (repositories you do not own, shared policy) or for work
that cannot land green in one push: right after opening its PR run
`gh pr merge --auto --squash --delete-branch`, and name any unfinished
branch/PR and blocker at turn end. Never merge red.

`TOOLS/Set-GitHubProtection.ps1` writes two rulesets: `integrity` blocks
force-push and deletion for everyone; `checks` makes pull-request merges
(Dependabot, contributors) wait for CI while admins push directly. Dependabot
PRs merge themselves when green. `TOOLS/Clean-MergedBranches.ps1` reports first
and `-Apply` deletes only proven merged branches; prove ancestry with
`git merge-base --is-ancestor BRANCH main`. Squash/superseded work needs patch
review, never forced deletion.

Bundle releases publish themselves: `.github/workflows/release.yml` runs after
CI passes on a main commit whose `VERSION.txt` has no tag yet, waits for every
other check, builds twice, requires identical bytes, attaches checksums, a build
receipt, an SBOM and the observed checks, attests, publishes and re-downloads to
compare. Manual fallback: `TOOLS/Build-Release.ps1`.

## Security gate

Run `TOOLS/Get-GitHubFlags.ps1 -Repo OWNER/REPO`, otherwise `gh api` per
[alert-query details](references/github-alerts.md). Dependabot, code-scanning
and secret-scanning must be clean. `flags=unknown` is not zero; fix the cause,
push, reconverge and query again. Do not dismiss alerts. Do not print secrets.
`code_quality=unavailable` stays off. Do not add OSV-Scanner, Gitleaks, or zizmor.
