---
name: reliability-engineering
description: Reliability for code that persists, retries, migrates, runs processes or crosses a trust boundary - atomic writes, idempotent retries, migrations, concurrency, cleanup, secrets, shell quoting, portability, supply chain.
---

# Reliability engineering

Code that writes state, retries, migrates, spawns processes or touches another trust boundary fails in ways a happy-path test never shows. Pick the row that matches the change and read that reference before writing the code; several rows often apply.

| When | Read |
|---|---|
| Writing manifests, databases, JSON/YAML/TOML, caches, indexes, save files, generated reports, or other persisted state | `references/data-integrity.md` |
| An operation changes multiple files, registrations, database rows, configs, versions, or external resources that must not be left half-updated | `references/transactional-updates.md` |
| Operations may be retried after timeouts, transient errors, duplicate delivery, process interruption, or uncertain acknowledgement | `references/retry-idempotency.md` |
| Moving user data/config, renaming install roots, changing schemas, upgrading persisted state, or replacing existing installations | `references/migration-rollback.md` |
| JSON, YAML, TOML, databases, APIs, manifests, messages, configs, or persisted objects change shape across versions | `references/schema-evolution.md` |
| Changing commands, schemas, APIs, protocols, config formats, plugin interfaces, or behavior consumed by other components | `references/api-compatibility.md` |
| Work can overlap across threads, processes, agents, hooks, async tasks, parallel builds, or shared mutable files/state | `references/concurrency-safety.md` |
| Completion depends on asynchronous jobs, CI checks, processes, files, services, or other state that changes over time | `references/condition-based-waiting.md` |
| Code launches child processes, local servers, workers, browsers, watchers, or temporary services that must not survive failure or shutdown | `references/process-lifecycle-cleanup.md` |
| A batch, installer, migration, fan-out, provider sweep, or multi-resource action can succeed for some targets and fail for others | `references/partial-success-accounting.md` |
| Software automatically switches providers, models, algorithms, parsers, tools, cached data, compatibility modes, or optional components after a failure | `references/fallback-degradation.md` |
| Failures from APIs, subprocesses, installers, parsers, providers, networks, or validation are being retried, surfaced, grouped, or mapped to recovery actions | `references/error-taxonomy.md` |
| Code chooses among multiple files, providers, releases, candidates, records, plugins, matches, or equally valid options and repeatability matters | `references/deterministic-selection.md` |
| Designing or changing stateful systems, installers, serializers, concurrent code, workflows, or APIs whose correctness depends on facts always remaining true | `references/invariant-driven-design.md` |
| Reading, merging, editing, migrating, or generating user-owned JSON, YAML, TOML, INI, or settings files | `references/config-preservation.md` |
| Work may write to external systems, perform destructive operations, publish, migrate, delete, send, push, or broadly modify files | `references/side-effect-safety.md` |
| Code executes commands, installs hooks/plugins, handles untrusted input, writes outside a workspace, or crosses privilege/network boundaries | `references/security-boundaries.md` |
| Handling API keys, tokens, cookies, credentials, private URLs, environment files, logs, reports, or release artifacts | `references/secret-hygiene.md` |
| Commands cross batch, PowerShell, cmd, Bash, native executable, subprocess, quoting, environment, or exit-code boundaries | `references/shell-boundary-safety.md` |
| Code, installers, archives, configs, subprocesses, or scripts handle filesystem paths across machines | `references/path-portability.md` |
| Downloading, vendoring, executing, updating, or redistributing third-party binaries, scripts, packages, actions, plugins, models, or archives | `references/supply-chain-verification.md` |
