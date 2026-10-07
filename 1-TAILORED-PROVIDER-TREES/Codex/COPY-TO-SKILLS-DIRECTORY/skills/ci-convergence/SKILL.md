---
name: ci-convergence
description: Use when a task may push commits, wait on CI, tag, publish, or declare a release complete.
---

# CI Convergence

## Core rule
A local green run is not release evidence. The authoritative unit is the **pushed SHA** and every required check attached to that exact SHA.

## Contract
1. Record the pushed SHA immediately after push.
2. Enumerate required checks for that SHA; never substitute “latest run”.
3. Wait while any required check is queued or running. **Pending is not success.**
4. Require every required check to reach a terminal successful state.
5. If one fails, inspect its log, fix the causal defect, push a new SHA, and restart convergence from step 1.
6. Tag, publish, or end the task only after the exact release SHA is terminal-green.

For a release, verify the tag resolves to the same green SHA and verify the uploaded artifacts after publication.

## After the checks are green

Required checks do not include GitHub security or quality flags. Code scanning and code quality can open a finding after the workflow is already green.

```
powershell -NoProfile -ExecutionPolicy Bypass -File TOOLS/Get-GitHubFlags.ps1
```

- `flags=clean` and exit 0: no open Dependabot, code-scanning, or secret-scanning alert. Code quality is either empty or `code_quality=unavailable`.
- `flags=open` and exit 2: do not tag, publish, or call the push done. Compare each flag path with `git show --name-only --format= <SHA>`. A flag on a file this push changed is fixed in source, then a new SHA restarts convergence. A flag outside that push is reported with its rule, path, and url. Do not dismiss it. Do not rewrite a vendored third-party tree just to silence a scanner.
- `flags=unknown` and exit 1: the query failed. That is not zero alerts. Do not release.
- A secret-scanning line prints `secret_type` and the alert url only. Do not print, log, or commit the secret. Stop and rotate it.
- `code_quality=unavailable` is a 403 or 404, not a clean scan. This personal public repository returned 404 on `GET /repos/{owner}/{repo}/code-quality/setup` on 2026-10-07. Do not PATCH that endpoint on. Code Quality spends Actions minutes and needs a paid plan.
- Validity checks and non-provider secret patterns stay off here. They need GitHub Secret Protection on an organization plan. Report the status the probe prints. Do not PATCH them on to match a recommended-config screenshot.
- Do not add OSV-Scanner, Gitleaks, or zizmor to the default workflow. Dependabot, code scanning, and secret scanning already run.

## Stop conditions
Do not release on cancelled, skipped-when-required, missing, unknown, pending, or stale checks. If the CI system cannot prove which SHA it tested, report that as unverified rather than inferring success.
