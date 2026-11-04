---
name: verification-discipline
description: Verification that proves a change or release works - test oracles, real boundaries, edge cases, reproducers, regressions, fresh-install and upgrade proof, CI parity, artifacts, provenance, reproducible builds, versions, performance, numbers.
---

# Verification discipline

A green run proves only what it actually exercised. Pick the row that matches what you are about to claim and read that reference first; it says what evidence the claim needs.

| When | Read |
|---|---|
| A test passes but may be checking the wrong signal, mocks its own assumption, snapshots unstable output, or cannot distinguish correct behavior from a broken implementation | `references/test-oracle-quality.md` |
| Tests mock subprocesses, filesystems, parsers, databases, networks, CLIs, serialization, or OS/provider integration | `references/real-boundary-testing.md` |
| Changing parsers, installers, APIs, inputs, file handling, state machines, or code with many boundary conditions | `references/edge-case-matrix.md` |
| A bug is intermittent, complex, cross-layer, or buried in a large application and the causal input or boundary is not yet isolated | `references/minimal-reproducer.md` |
| A test, build, install, CI job, tool call, or repeated attempt fails and the task must continue reliably | `references/failure-recovery-loop.md` |
| A bug was fixed or shared behavior, schemas, helpers, installers, or cross-provider integrations changed and sibling regressions may exist | `references/regression-sweep.md` |
| Software installs, updates, migrates, downloads, writes files, invokes networks, or crosses boundaries where partial failure could corrupt state | `references/failure-injection-testing.md` |
| Shipping installers, setup scripts, portable bundles, bootstrap flows, or “works on a fresh machine” claims | `references/fresh-install-proof.md` |
| A release, installer, schema, configuration, or tool must work for both new users and users upgrading from an older version | `references/upgrade-path-testing.md` |
| Code passes locally but fails in CI, production, a clean machine, another shell, or a user's installation due to environmental differences | `references/environment-parity.md` |
| Behavior depends on combinations of operating system, shell, architecture, runtime, model/provider, API revision, application version, or optional dependency | `references/compatibility-matrix.md` |
| Producing a ZIP, installer, executable, wheel, package, release asset, or other built deliverable | `references/artifact-proof.md` |
| Building, publishing, comparing, debugging, or accepting binaries, archives, generated files, installers, models, or release assets | `references/artifact-provenance.md` |
| Building release binaries, generated assets, archives, manifests, wheels, native helpers, or supply-chain-sensitive artifacts | `references/reproducible-builds.md` |
| Bumping versions, publishing packages, rebuilding binaries, changing protocol compatibility, or updating release metadata | `references/version-sync.md` |
| Optimizing speed, memory, latency, startup time, throughput, token cost, build time, or runtime resource use | `references/performance-evidence.md` |
| Calculations, pricing, timings, sizes, probabilities, rates, memory limits, token budgets, measurements, or converted values affect a decision | `references/numerical-sanity-check.md` |
