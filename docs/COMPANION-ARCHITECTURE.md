# Companion architecture and installation contract

Date: 2026-10-26. Decision: retain three independently versioned repositories,
with optional companion orchestration in the Starter Bundle. This document
records the source review and the required behavior; it is not a claim that
every proposed installer, migration or acceptance case already passes.

## Decision

The [Ultimate AI Starter Bundle](https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle),
[Skyrim Forge](https://github.com/SenjuWoo/SkyrimForge) and
[Reverse THIS!](https://github.com/SenjuWoo/reverse-this) remain standalone
products. Each installs, runs, updates and repairs its own capabilities without
requiring either companion's repository to be present. Each recommends the
other complete products when the task benefits from them.

The bundle is the convenient front door for people who want the full stack.
Its optional companion selection locates and reuses existing installations,
installs a verified owner release when missing, and calls the owner's supported
installer. Use `START-HERE.bat -Packs skyrim,reverse` for the recommended stack, or
`-ExcludePacks skyrim,reverse` for general tools only. Choices are remembered.
Selecting Reverse THIS! must not copy its payload catalog or package
installation logic into the bundle. Selecting a companion is not permission
to enable every MCP, change models, rewrite personal provider settings or grant
project trust.

For AI coding and general game work, recommend the bundle. For Skyrim SE/AE
authoring, recommend Forge and optionally the bundle. For binary, application
or game-format analysis, recommend Reverse THIS! and optionally the bundle.
Tasks spanning these domains can recommend all three. A user can install the
whole recommended stack once without making every specialist active in every
chat.

## Evidence and actual overlap

The reviewed bundle tree contained 126 canonical skill directories. Forge
6.1.1 contained 48 specialist skill directories and 28 tool-broker entries.
Reverse THIS! 1.3.0 contained 58 tool entries and no provider skill collection.
Counts describe this review baseline, not permanent release assertions.

| Intersection | Observed behavior | Consequence |
| --- | --- | --- |
| Bundle and Forge skill names | One collision: `ai-tooling-stack`, with different file bytes | Two installers can disagree about the same provider directory |
| Bundle and Reverse tool catalog IDs | Only `rea`; the bundle entry is manual/discovery-only and names Reverse THIS! as owner | No need for a second REA installer |
| Forge and Reverse payload capabilities | Forge recognizes `texconv` and `seven_zip`; Reverse supplies DirectXTex and 7-Zip | Reuse the installed payload through Forge's configured path and hash |
| Shared dependencies | Python, Node and .NET support more than one product; Java supports several Reverse tools | Reuse compatible base runtimes; keep application dependencies isolated |
| General game workflow | The bundle already installs Universal Modder | Reverse discovers that installation instead of installing another workflow stack |

The skill collision is being resolved by retaining a general bundle-owned
`ai-tooling-stack` and renaming Forge's Skyrim-specific index to
`skyrim-tooling-stack`. With the directory counts otherwise unchanged, the
expected number of distinct names rises from 173 to 174. Installation and
reference migration still require explicit verification; a rename alone is
not proof of a successful live migration.

The current boundaries already support most of this design:

- [Bundle catalog](../BUNDLED-TOOLS/CATALOG.json) names the companions and
  delegates REA ownership. The [RE task recipe](../_CANONICAL-SKILLS/capability-profiles/references/task-recipes.json)
  and [discovery guide](../_CANONICAL-SKILLS/tool-discovery/references/reverse-engineering.md)
  route to the existing kit pointer and owner instructions.
- [Install-SkyrimForge.ps1](../TOOLS/Install-SkyrimForge.ps1) installs Forge's
  latest release at or above the catalog floor (GitHub digest and SHA256SUMS
  verified), preserves newer deployments and Git source checkouts, stages
  replacement files, and retains a previous deployment. Its doctor invokes
  Forge rather than reproducing Forge validation in the bundle.
- Forge's `scripts/Provider-Skills.ps1` has its own preservation ledger,
  reads legacy bundle ownership proof, and does not rewrite the bundle ledger.
  `Install-HouseCarl.ps1` compares versions and retains an older server backup.
- Forge's `skyrim_forge/toolchain.py` imports approved tools into a private
  hash-addressed vault. Existing executable-path and SHA-256 configuration
  can instead reference another owner's installed binary.
- Reverse's `Install-Modkit.ps1` has stable shims, installed records, payload
  backups and rollback. `Get-ExternalRea` in the reviewed baseline reuses an exact matching PATH copy
  as unowned. The new candidate adds validated external receipts; this baseline special case alone was not general external-tool reuse.

The reviewed baseline had concrete gaps: exact-only external REA reuse,
Python/Node requirements that could stop standalone setup, package tools that
only refreshed with `-Force`, and source update preservation risks. The current
candidates address these with shared prerequisite discovery, owner receipts,
explicit pinned/newer comparisons and transactional owner updates. Validation
below remains a contract; actual verdicts belong in each owner's VALIDATION.md
and release records. An unknown external binary is preserved and reported,
rather than guessed to be current or silently replaced.

## Companion versions and payloads in git (decided 2026-10-29)

The bundle no longer pins companion releases. Pinning made each Forge or
Reverse THIS! release force a bundle release, and committing their archives grew
history by about 5 MB per Forge release (nine Forge archives in the last 43
commits; the repository reached ~570 MB). CATALOG.json now holds a floor per
companion; the installer and the release build fetch the owner's latest release
and verify it, and companion archives are never committed. Third-party offline
payloads stay pinned in git: Full-Offline must reproduce exactly what the bundle
reviewed, they change rarely, and two of them are wheels built here from pinned
source. Existing history is not rewritten, because that would move every
published tag; maintainers who need a light clone use `git clone --filter=blob:none`.

## Options considered

| Option | Maintenance and failure effects | Installation and usage costs |
| --- | --- | --- |
| Merge Reverse source and catalog into the bundle | One repository, but 58 specialist entries, their tests, package rules, rollback and independent tool state still need maintenance. Provider releases and analysis-tool changes acquire a wider regression surface. Standalone RE packaging still needs a boundary. | One visible download can be convenient, but merging does not remove payload bytes, runtime setup or provider context costs. It can make unrelated bundle updates larger. |
| Keep independent companions with documentation only | Keeps release and ownership boundaries clear; existing owner installers remain reusable. Users and agents still coordinate discovery, prerequisites and update commands themselves. | Lowest new implementation cost; more setup friction and more opportunity for duplicate installations. |
| Keep independent companions with optional bundle orchestration | One front door delegates to separately versioned owners. A failed specialist install reports that component's failure without rewriting other owners' successful state. Small cross-product contracts need tests. | Convenient full-stack setup, reuse of installed payloads and task-scoped activation. Adds a small orchestrator rather than another package manager. |

Choose the third option. Repository count is not itself the main maintenance
cost: duplicated catalogs, conflicting writers, unsupported runtime selection
and repeated package logic are. The largest practical savings come from
preventing those problems while preserving independent releases.

## Source, installation and state ownership

| Owner | Authoritative source and policy | May consume from companions |
| --- | --- | --- |
| Bundle | General provider setup, common skills, shared runtime/compiler provisioning, task/MCP routing and optional companion orchestration | Specialist discovery receipts, versions and supported installer/doctor entry points |
| Forge | Skyrim skills, houseCARL, Skyrim-specific tool/workflow policy and its own ledgers | Compatible shared runtimes; existing generic binaries such as texconv and 7-Zip |
| Reverse THIS! | REA and analysis payload catalog, tool version selection, stable shims, tool records, private target workspace and rollback | Compatible shared runtimes and the existing Universal Modder installation |

Source ownership does not require a private installed copy of every dependency.
A compatible shared executable can serve multiple products. Its install owner
remains the product or package manager that installed it; consumers record a
reference and validation evidence rather than claiming its directory.

Application venvs and package prefixes remain separate where dependency
isolation requires them. They can share the same compatible base Python or
Node installation. A project's pinned Go, Rust, Python, .NET or other toolchain
remains a project requirement even when a newer shared default exists. Do not
replace a project pin merely to reduce the number of runtime directories.

Each installer writes its own ledger only. Another owner's receipts are
read-only discovery evidence. Preserve unknown JSON extensions and unrelated
tool/provider records. Coordinate concurrent writes with owner locks, and
commit payload/state changes transactionally. A bundle orchestration receipt
records component outcomes without becoming a second specialist tool ledger.

## Reuse and update contract

1. Discover from an explicit user path, current owner pointer/receipt, supported
   environment variables, package-manager records and PATH. Probe the selected
   candidate's actual version and required capabilities. Do not infer health
   from a filename, folder version or catalog entry; do not scan whole drives.
2. Identify installation ownership before modifying an existing path. A known
   product-owned deployment can be refreshed by that owner; a package-managed
   runtime is updated through that package manager. Unknown ownership or
   unknown version is not permission to overwrite, downgrade or create a
   competing default. Preserve it and report the evidence needed to resolve it.
3. Select the owner's supported current stable target and compatibility policy.
   Reviewed security/compatibility holds and project pins remain explicit
   exceptions. A bundle's reviewed offline pin is a reproducible snapshot;
   an online owner update is a separately recorded resolution, not permission
   to relabel new bytes as that old snapshot. Prereleases require a documented
   owner exception or explicit task need.
4. Reuse an equal healthy installation. Update a known-owned older installation
   in place through its owner when its version is below the selected supported
   target. Keep a newer compatible installation without downgrading. A newer
   incompatible or project-pinned version needs a side-by-side compatible
   environment or an explicit resolution; never silently change the default.
5. Preserve personal configuration, credentials, model/reasoning choices,
   provider trust, workspaces and edited skills. Adopt legacy files only when
   ownership proof and their whole-tree digest identify an unchanged managed
   copy. Back up modified state before a scoped migration.
6. Verify source provenance and the selected archive/package integrity before
   activation. Stage replacement payloads, retain the last known-good files
   and state, validate the candidate, then atomically activate and record it.
   On failure restore the prior payload, shims, pointer and owner state. If
   rollback is incomplete, report the exact retained paths and recovery gap.
7. Validate at the capability boundary: version/help or owner doctor plus the
   smallest relevant sample; compilers need a compile-and-run probe. File and
   manifest checks do not prove game compatibility or target behavior. A
   locked/running executable must leave the working install intact and report
   a deferred replacement or actionable close/retry requirement.
8. Report each component as reused, updated, installed, preserved, deferred or
   failed, with the resolved version/path and reason. Unknown is not success.
   A partially successful all-stack installation must not claim full success.

The skill-name migration follows the same rules: update callers and provider
references, migrate only proven managed legacy copies, retain edited copies,
and keep the bundle and Forge ledgers independent. Do not remove a user's
edited `ai-tooling-stack` because its directory name matches an old release.

## Smallest implementation path

Reuse the existing entry points rather than replacing the installers:

- Bundle `Install-SkyrimForge.ps1`, `Get-UabsStateRoot`, archive-integrity helpers
  and component result reporting supply the existing orchestration pattern.
- Forge `Find-Python`/candidate probing, Reverse `Find-JdkHome`/`Get-JavaMajor`
  and `Find-DotNet10`/`Test-DotNet10`, and bundle
  `Find-BuildCommand`/`Require-BuildCommand` already cover much prerequisite
  detection. Preserve each tool's actual capability/version checks.
- Reverse `Test-AlreadyInstalled`, `Get-ExternalRea`, `Write-AtomicJson` and
  `Assert-OwnedToolPath` supply reuse, owner-record and path-safety patterns.
  Extend external reuse to selected verified tools rather than teaching the
  bundle all 58 install methods.
- Configure Forge's existing executable/hash fields from the selected
  Reverse-owned texconv and 7-Zip payloads; importing another copy is optional
  only when a project actually requires an isolated pinned tool.

No shared prerequisite framework is needed for this change. Each standalone
owner keeps its small runtime resolver and uses platform package managers;
common behavior is covered by boundary fixtures. A separate shared module is
only justified if later maintenance demonstrates repeated defects that cannot
be fixed cleanly in these small owner entry points. Do not import all of
`UABS-Common.ps1`, share a mutable global ledger or create another package manager.

## Required acceptance matrix

These cases are release criteria for the integration. They are not results.
Run clean-layout fixtures without the other products' source directories,
plus supported real-runtime probes where the capability requires them.

| Installed products | Required outcome |
| --- | --- |
| Bundle only | General setup and common tools work; missing specialists are accurately reported; optional companions remain optional |
| Forge only | Core Forge, its skills and selected Skyrim setup work with independently resolved prerequisites; no bundle import required |
| Reverse only | Selected analysis tools install/run using standalone prerequisite resolution; no provider setup or Forge dependency |
| Bundle + Forge | Bundle delegates Skyrim skills/tools; separate ledgers; personal provider settings and edited skills survive |
| Bundle + Reverse | Existing kit and shared runtimes are reused; selected tool updates go through Reverse; no second REA/Universal Modder installation |
| Forge + Reverse | Compatible generic tools/runtimes are shared by reference; neither installs the bundle as an implicit dependency |
| All three | One optional setup front door, correct owner per component, no same-name skill collision, stable discovery and explicit partial failures |

Exercise each applicable owner/consumer path against the following states:

| State or operation | Required assertion |
| --- | --- |
| Missing | Install selected capability through its owner; record provenance, version, path and successful validation |
| Older known-owned | Update to the owner's selected supported target; retain rollback files and user state |
| Equal healthy | Reuse without payload replacement or configuration churn |
| Newer compatible | Keep without downgrade; validate and record the actual version |
| Unknown version or ownership | Preserve; report unresolved evidence; do not overwrite or silently install a competing default |
| Project-pinned or personal edits | Keep the requirement/edit; use explicit compatible isolation or report the conflict |
| Broken known-owned | Repair transactionally through its owner; successful executable presence alone is insufficient |
| Moved/missing external reference | Report stale discovery; select a verified replacement or repair through the owner, retaining unrelated state |
| Locked/running path or concurrent installer | Keep the working payload and pointer intact; defer or fail clearly; enforce owner locks |
| Offline with valid cache | Use verified selected cached bytes and already available prerequisites; record the actual version |
| Offline without required bytes/prerequisite | Report the precise missing item; preserve all existing working components |
| Failed validation, interrupted update or rollback failure | Restore last-good payload/state/shims/pointer when possible; report incomplete rollback explicitly and retain recovery evidence |
| Companion source Git checkout | Preserve local edits and repository identity; update source through its owner workflow, not deployment extraction |

Completion evidence must identify the tested combination, owner versions,
selected runtime/tool paths, source/package digests, preservation assertions,
sample or compile/run outcome and any remaining runtime gap. Updating this
decision document does not satisfy those implementation gates.

## Additional supplied tools

Xmake joins the bundle's shared compiler suite and is consumed by native Skyrim
projects. Nx, Turbo, Vite and webpack remain project-local general build tools;
the bundle documents their routes rather than copying full source monorepos.
CLibDT and the distinct CommonLib forks belong to Forge's discovery/native build
guidance. CommonLib source is pinned per plugin project, not auto-updated globally.
Reverse THIS! reuses shared build tools when analysis requires compilation; none
of these additions needs a second analysis-tool installer.
