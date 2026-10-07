---
name: ci-convergence
description: Use when a task may create or update a GitHub repository, push commits, wait on CI, fix security alerts, tag, publish, or declare a release complete.
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

Required checks do not include GitHub security alerts. Dependabot, code scanning, and secret scanning can open after the workflow is green. Query the repository you just created, pushed, or updated. This is every repository, not one product.

When `TOOLS/Get-GitHubFlags.ps1` is in the checkout, run it with `-Repo OWNER/REPO` (omit `-Repo` only when that origin is the repository you just wrote). Otherwise `gh api` these paths under `repos/OWNER/REPO/`, header `X-GitHub-Api-Version: 2026-03-10`: `dependabot/alerts?state=open&per_page=100`, `code-scanning/alerts?state=open&per_page=100`, `secret-scanning/alerts?state=open&per_page=100`, `code-quality/setup`, and `code-quality/findings?state=open&per_page=100`. A secret row is number, `secret_type`, and url.

- `flags=clean`, exit 0: no open Dependabot, code-scanning, or secret-scanning alert. Code quality is empty or `code_quality=unavailable`.
- `flags=open`, exit 2: do not tag, publish, or call the push done. Fix the cause. Update or replace the dependency and regenerate the lockfile that repository already gates. Fix code scanning at the path and line it names. Remove a secret from the tree and rotate it. Push the fix, wait for the new SHA, and query again. Not done while an alert that change opened is still open. Do not dismiss an alert. Do not rewrite a vendored third-party tree just to silence a scanner.
- `flags=unknown`, exit 1: the query failed. That is not zero alerts. Do not release.
- Do not print, log, or commit the secret. Stop and rotate it.
- `code_quality=unavailable` is a 403 or 404 on that repository, not a clean scan. Do not PATCH it on. It spends Actions minutes and needs a paid plan. Validity checks and non-provider patterns need organization Secret Protection; do not PATCH those on.
- Do not add OSV-Scanner, Gitleaks, or zizmor to the default workflow. Dependabot, code scanning, and secret scanning already run.

## Stop conditions
Do not release on cancelled, skipped-when-required, missing, unknown, pending, or stale checks. If the CI system cannot prove which SHA it tested, report that as unverified rather than inferring success.
