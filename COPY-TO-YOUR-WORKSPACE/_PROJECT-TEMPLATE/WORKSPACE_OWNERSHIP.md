# Workspace ownership

- Project root: the directory containing this file; reuse one owner across agents.
- Active source/version: resolve existing CURRENT/version/Git metadata before editing.
- Versioning: preserve the project layout; use Git tags for Git projects.
- Repository/publication: local/private by default; no remote or public upload merely because work reaches a release candidate. Preserve established repository visibility and authorized maintenance/release workflow.
- Read-only inputs: installed products, game Data/staging/saves and supplied references.
- Outputs: stage runtime payload separately; never ship this file, STATE/PLAN/changelog/validation, publication paperwork, logs or backups in a mod ZIP. Retain required licensing.
- Recovery: keep STATE.md, build/run commands and the last known-good artifact current.

Fill these fields from the actual project before substantive writes. WORKSPACE.md is an optional multi-project map; it does not replace this record.

New work stays local/private until publication is requested. "Put it on GitHub" means public and MIT for original work by default, subject to third-party rights and platform terms; preserve existing licences and explicit choices. Generic publication uses the appropriate destination (normally Nexus Mods for Skyrim). A mod needing no compilation does not get a duplicate GitHub repository by default; add source hosting when requested or needed for development.
