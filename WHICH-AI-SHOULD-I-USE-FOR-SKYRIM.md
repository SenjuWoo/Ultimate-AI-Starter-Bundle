# Which AI should I use for Skyrim modding?

Use the installed assistant that can inspect the actual project, invoke the
required tools, preserve your work and produce verified artifacts. Claude, Codex,
Grok, Kimi and Hermes receive the same canonical bundle skills; installation
and callable MCP scope still differ. There is no measured universal provider
ranking in this bundle. Catalog metadata is not a reliability score.

The old model-tier rankings and percentage estimates were not controlled Skyrim
benchmarks. They have been removed rather than relabelled as current facts.
Choose the model actually available in your app; for Hermes see
[current catalog guidance](docs/HERMES-MODELS.md). Existing preferences are not
remapped to new paid endpoints by this guide.

## Match the task to evidence and tools

| Task | Capability and proof to require |
| --- | --- |
| Plugin/VMAD/record work | Typed tooling or source-locked schemas, resolved IDs/masters, structural and semantic validation |
| Papyrus | Installed framework/compiler/import evidence, lifecycle checks and compilation; graph indexing does not parse .psc |
| SKSE/CommonLib native DLL | Exact runtime/ABI/dependencies, real build/tests and runtime reproduction |
| Crash diagnosis | Newest actual crash/runtime logs, active list and a reproducible symptom; no invented winners or offsets |
| Distribution/config generation | Dedicated SPID/KID/SkyPatcher/BOS grammar, deterministic generation and unresolved-target checks |
| UI/assets | Real rendered/in-game previews, source/licence provenance and runtime checks |
| Publication | Usable archive, preserved variants/dependencies, credits/permissions, honest screenshots and release verification |

Start with `skyrim-tool-router` and `skyrim-frameworks-index`; dedicated skills
own exact grammar. Forge, houseCARL, Spooky's toolkit and Universal Modder have
separate roles, not interchangeable evidence. A missing MCP can mean installed
but inactive: see [profile discovery](AIO-GUIDE.md#when-an-ai-cannot-find-a-tool),
not a blanket reinstall. Hermes uses its native named profile; project-scoped
providers require the matching trusted/configured project.

## Keep one implementation owner

One writer owns each coupled plugin, VMAD-bearing file, Papyrus state-machine
family, native DLL, FOMOD tree, generated output set or release archive.
Independent research/review can be split when requested, but the owner merges
it and checks the actual diff. A second assistant is not mandatory ceremony and
is not a substitute for builds, tests or runtime evidence.

## Complete workflow

1. Inspect current files/status and preserve the last known-good version,
   optional variants, dependencies, permissions and gameplay intent.
2. Verify frameworks, tool paths and capabilities against the actual workspace.
   Game Data, mod-manager staging, saves and reference vaults stay read-only.
3. Make a bounded change with one owner; run the exact compiler/validator and
   tests that decide correctness. Review for behavior or scope lost in the diff.
4. Exercise the stated player-visible behavior when a runtime is available;
   otherwise report that runtime proof is still missing.
5. Package the validated staging tree and verify archive contents/hashes. For
   GitHub, wait for required checks on the exact pushed SHA, obtain publication
   approval when missing, publish usable assets and verify the downloaded bytes.

Structural success is not gameplay confirmation. An impressive model name,
large context or high effort setting does not establish accuracy, speed or
completion. Compare providers on the same task and evidence if you want a
ranking; keep it dated and separate from portable installation defaults.
