---
name: reasoning-discipline
description: Reasoning under uncertainty before acting - assumptions, ambiguity, contradictions, evidence confidence, self-review, requirement tracing, user intent, sources of truth, dependency capabilities, automation.
---

# Reasoning discipline

Most expensive mistakes are a wrong premise acted on confidently. Pick the row that matches the doubt and read that reference before deciding.

| When | Read |
|---|---|
| A plan relies on guessed paths, versions, APIs, user state, defaults, environment behavior, or undocumented facts | `references/assumption-audit.md` |
| A requirement, error, API, name, or observed behavior has multiple plausible interpretations that would lead to different actions | `references/ambiguity-resolution.md` |
| Documentation, tests, configs, user requirements, source code, runtime behavior, or external sources disagree about the same fact | `references/contradiction-detection.md` |
| Making factual claims, estimates, diagnoses, rankings, recommendations, or confidence statements under incomplete evidence | `references/evidence-calibration.md` |
| Finalizing a complex answer, implementation, diagnosis, migration, or release where an initially plausible result could hide a costly mistake | `references/adversarial-self-review.md` |
| Implementing a multi-part request, specification, migration, release, audit, or acceptance-test-driven task | `references/requirements-traceability.md` |
| Optimizing, refactoring, simplifying, automating, or making trade-offs could accidentally remove or weaken something the user explicitly asked for | `references/user-intent-lock.md` |
| The same fact appears in multiple files, configs, generated reports, caches, docs, or external systems | `references/source-of-truth.md` |
| A task depends on runtimes, CLIs, SDKs, APIs, provider features, plugins, or platform-specific behavior | `references/dependency-capability-check.md` |
| A workflow asks the user to copy, edit, approve, restart, configure, repair, or verify steps that software may be able to perform | `references/automation-first.md` |
