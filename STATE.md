# Bundle audit state

## Completed 8.29.0 mod workspace repair and presentation — 2026-10-31

- New `mod-workspace-organization` skill and `TOOLS/workspace_doctor.py`:
  source/package/release/state separation, one version source, stale root FOMOD
  detection, version-snapshot and nested-cache counts, and a narrow `--apply`
  that moves only high-confidence unreferenced clutter with a backup manifest.
  FOMOD roots, snapshots, nested Git repositories and game/binary assets are
  never moved automatically.
- New `mod-presentation` skill, `TOOLS/presentation_check.py` and
  README/Nexus/plan templates: a public page needs a real 16:9 cover, three
  gallery stills, three local README images with alt text, and a kind-specific
  shot (face, angles, wide/detail, motion, installer/menu). A text-only public
  page fails. Wired into `game-modding`, `MODDING-LAWS`, the ship gate,
  `workspace-organization` and `public-copy-durability`; 129 canonical skills.
- Real `NemesisCombatAI` audit (read-only): 18 root entries; root FOMOD `2.0.4`
  while `CURRENT.txt` says `3.0.0`; two version snapshots; five nested caches
  including `github-repo/build` 1.15 GB and `TOOLS/vcpkg` 554 MB; no
  high-confidence automatic moves because the FOMOD root and snapshots are
  path-dependent. Report: `artifacts/workspace-audit/NemesisCombatAI-plan.md`.
- Presentation check on the same folder: FAIL, 0 images; its own media plan
  already says presentation is incomplete. This is the gap the new gate exposes,
  not a fabricated result.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.29.0
  at `2c574e7a9aaf522bd4117943b51afdb4b8c83d26`; CI 41246082727 and CodeQL
  41246082537 succeeded, Release 41246730300 published. Core 45,470,840 B
  sha256 `1d4d171002e7fc0dca24ebd48fd075ebe53fc067c56f29e0c12c8bd848331629`;
  Full-Offline 142,020,227 B sha256
  `6d4cb17f34cc2c08dc695a73500be6dc16c888e6a9294508cad001d622790ea9`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local install: 8.29.0 Full-Offline installed with no `-Packs`; packs
  auto-detected Skyrim and Reverse; exit 0; doctor 8.29.0 with 0 errors and 0
  warnings; 129 general skills plus the two new ones in the `code` profile;
  models stay `deepseek/deepseek-v4.1-flash-1017`.
- Remaining: the example still needs a decision on the stale 2.0.4 root package
  and real captures; Ponytail stays 5.3.2 pending a bundled re-stage; 10
  third-party catalog pins remain stale; Context7 does not index
  `/senjuwoo/reverse-this`.

## Completed 8.28.5 one-click packs and AI-started tools — 2026-10-31

- One-click install now covers the specialist layers: `PACKS.json` auto-detects
  Skyrim from the game, a mod manager or an existing Forge, and Reverse THIS!
  from its kit receipt. `-Packs` still forces a layer, `-ExcludePacks` keeps it
  off, and both choices are remembered.
- The preamble now tells every provider's AI to start project MCP servers
  itself through the toolbox `find`/`describe`/`call` or the owning CLI, never
  to ask the user to start a tool, server or installer. A host restart is the
  only step it may request, and only to index a new skill. `game-modding` runs
  the Skyrim pack installer itself and uses Forge immediately.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.28.5
  at `8eb08d4e4f046a20806b76aea930d95ad15e6663`; CI 41241265014 and CodeQL
  41241264792 succeeded, Release 41241908203 published. Core 45,388,747 B
  sha256 `40e19cb00b880ea2a31b84d41674a60e72391cf6c3ee2b469ce7a601b046eb81`;
  Full-Offline 141,909,619 B sha256
  `3aa0fa7e846a05f5f7a94e800bf474b2a814d03a511fc9814747d56d83b2a04d`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local one-click proof: deleted `packs.json`, then ran
  `INSTALL-AIO.ps1 -Mode BundledOnly -SkipSelfUpdate -SkipHouseCarlSetup` with
  no `-Packs`; the log reports `Pack 'skyrim' on: found steam app 489830, My
  Games\Skyrim Special Edition, Vortex skyrimse, SKYRIM_FORGE_ROOT,
  SKYRIM_MO2_INSTANCE, HOUSECARL_ROOT` and `Pack 'reverse' on: found registered
  companion ReverseThis/kit.json`. Install exit 0, doctor 8.28.5 with 0 errors
  and 0 warnings, 9 project tools.
- Live: preamble with the no-manual-start rule is in the root and five profile
  `SOUL.md` files; 48/48 Skyrim pack skills in the `skyrim` profile; models stay
  `deepseek/deepseek-v4.1-flash-1017` on OpenRouter. A live toolbox `find
  "skyrim mod"` returned Forge's 56 tools without the user starting anything.
- Remaining: Ponytail is enabled and healthy at 5.3.2 while the catalog lists
  5.3.3; the live gateway deferred its native refresh and the local bridge has
  no remote, so the bundled copy must be re-staged before it can update. The
  third-party catalog audit still reports 10 stale pins. Context7 does not
  index `/senjuwoo/reverse-this`; live game/GUI targets were not exercised.

## Completed 8.28.4 final doctor fix and local install — 2026-10-31

- 8.28.4 fixed the last false install check: a default
  `Test-Installed-State.ps1` run required every provider name, so a machine
  where Kimi was intentionally not installed failed with "Kimi executable
  missing after provider bootstrap". The recorded `install-state.json`
  `providers` list is now authoritative; a recorded provider with no
  executable still fails.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.28.4
  at `0d47ded2e9d05e63a2187d3926489b15c0df271f`; CI 41237530662 and CodeQL
  41237530412 succeeded, Release 41238163181 published. Core 45,381,882 B
  sha256 `0eb88989eb6fa2f3f6b4bb7760aba1a86928c3bcb4988f002e69263579466160`;
  Full-Offline 141,902,753 B sha256
  `7d8e83123f75542a7be5172dee382e0b16b781833b0b5bf477b0c793c89267ab`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local install: 8.28.4 Full-Offline installed with
  `INSTALL-AIO.ps1 -Mode BundledOnly -SkipSelfUpdate -Packs skyrim,reverse
  -SkipHouseCarlSetup`; exit 0. Direct `Test-Installed-State.ps1 -PackRoot .`
  PASS with 0 errors and 0 warnings; doctor 8.28.4; 9 project tools; recorded
  providers Claude/Codex/Grok/Hermes/Antigravity.
- Live state: root/code/skyrim/blender/unity/creative/web use
  `deepseek/deepseek-v4.1-flash-1017` on OpenRouter with MoA off;
  `sillytavern` keeps its local LM Studio model and MoA by design. No
  `claude-code-imports` tree. Skyrim Forge 6.6.0 doctor warnings empty, 50
  tools, 48/48 pack skills; houseCARL MCP present; Reverse THIS! kit 1.9.4.
- Remaining: Ponytail is enabled and healthy at 5.3.2 while the catalog lists
  5.3.3; the live gateway deferred its native refresh and the local bridge has
  no remote, so the bundled copy must be re-staged before it can update. The
  third-party catalog audit still reports 10 stale pins. Context7 does not
  index `/senjuwoo/reverse-this`; live game/GUI targets were not exercised.

## Completed 8.28.3 final audit and local install — 2026-10-31

- Goal: final audit for errors, bloat and outdated info, then a clean release
  and a working local install.
- Audit: 127 canonical skills PASS (the two pre-existing token-budget
  warnings in `img2threejs` and `skill-creator` remain); README Hermes model
  corrected to `deepseek/deepseek-v4.1-flash-1017` in 8.28.1; the third-party
  catalog audit still reports 10 stale pins that are not bundle-owned.
- 8.28.2 fixed the User-scope shared-Python check: an installer launched from
  an agent venv inherited that venv's `python`, failed verification and rolled
  back. `Set-SharedPython.ps1` now puts the chosen base interpreter first in
  the process PATH before checking.
- 8.28.3 fixed two install-scope issues: the Hermes native plugin refresh is
  deferred with a warning when the gateway has a live chat session instead of
  aborting the whole install, and the general `toolbox` MCP only receives the
  Skyrim environment variables when `SKYRIM_FORGE_ROOT` exists.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.28.3
  at `0b4baa32fe73c61c8e4adcf47bfa7d743c0deede`; CI 41234029767 and CodeQL
  41234029580 succeeded, Release 41234673865 published. Core 45,381,755 B
  sha256 `639cd487948b7d8e19ebd806276e45bed0d86db801bf02afdb964819d307d8cd`;
  Full-Offline 141,902,624 B sha256
  `4f18a6382168ca5b7c16c1e309b9d656d1465b790ceb61ab55f193c784ecb671`.
  All nine assets downloaded and `sha256sum -c SHA256SUMS.txt` is clean.
- Local install: 8.28.3 Full-Offline extracted and installed with
  `INSTALL-AIO.ps1 -Mode BundledOnly -SkipSelfUpdate -Packs skyrim,reverse
  -SkipHouseCarlSetup`; exit 0, doctor PASS 8.28.3 with 0 errors and 0
  warnings, 9 project tools. Root/code/skyrim/blender/unity/creative/web use
  `deepseek/deepseek-v4.1-flash-1017` on OpenRouter, MoA off; `sillytavern`
  keeps its local LM Studio model and MoA by design. No
  `claude-code-imports` tree remains. Skyrim Forge 6.6.0 doctor warnings
  empty, 50 tools, 48/48 pack skills in the `skyrim` profile; houseCARL MCP
  present; Reverse THIS! kit 1.9.4.
- Deferred: the live gateway prevented the Hermes native plugin refresh, so
  Ponytail stays at 5.3.2 (enabled, `hermes plugins doctor` OK) while the
  catalog lists 5.3.3; its local bridge has no remote. The next restart can
  finish the refresh, but the bridge must be re-staged from a newer bundled
  copy first.
- Not exercised: live game/GUI targets; Context7 still does not index
  `/senjuwoo/reverse-this` (local encyclopedia fallback documented).

## Completed 8.28.0 modular foundation — 2026-10-31

- Goal: the bundle is the base layer (general skills, work hygiene, GitHub/CI,
  visuals, efficiency, compiling, base tools); Reverse THIS! and Skyrim Forge
  are optional owners on top. No hard blockers, no duplicate installs, no
  stale model pins.
- Done: `reverse-engineering` skill with the 6-tier ladder and
  `CLAIMS.md`/`anticheat-risk.md`/`re-recipes` lookup; no-hard-blocker rule in
  the SOUL, manual paste and `coding-discipline`; Hermes model policy
  (deepseek 4.1 flash / auto, stale MoA advisors removed); anti-cheat risk
  tiers instead of a blanket ban; houseCARL falls back to the default Forge
  root; README "three layers" and corrected `-Packs reverse`.
- Live checks: Skyrim Forge 6.6.0 at the default root, `forge doctor` warnings
  empty, 48/48 pack skills in the archive and the `skyrim` profile, houseCARL
  MCP starts; Reverse THIS! 1.9.2 source kit, encyclopedia present, Context7
  library not indexed yet (local fallback documented).
- Gates: release contracts 155/0, canonical audit PASS, manifest 7,913 files
  verified, docs/version gates PASS, full Windows pack gate PASS.
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.28.0
  at `6cff110452e1ba876f89a95e87f4f6aeb5c35503`, self-published by
  `release.yml` (run 41225055840) after CI 41224428043 and CodeQL 41224428221
  both succeeded. Core 45,381,347 B sha256
  `d7629abe98e3f9e03cc88dd96759f9921ec92ab13161e219aa327dc32c38d38e`;
  Full-Offline 141,900,771 B sha256
  `d23160cf836ebf5dc4ab263ce74eed8673acf65345416f8dc44c5b4787daf8ba`.
- Downloaded all nine assets; `sha256sum -c SHA256SUMS.txt` is clean, the
  release target is the exact pushed SHA, and the notes open with
  "**Which file?**". Open Dependabot, code-scanning and secret-scanning
  alerts: 0/0/0.
- Next: nothing pending. Reopen AI apps once to load the refreshed skills,
  instructions and model settings.

## Completed 8.27.1 new-user audit — 2026-10-29

- Goal completed: full audit of the public bundle and the live install after 8.27.0. Nine misses from the 8.27.0 pass were found and fixed: START-HERE.txt still claimed the Skyrim pack installs when Skyrim is found; README-CORE.txt, PACKS.json and one README line still described a pinned Forge; public skills carried the maintainer's drive-letter Steam library and tools paths (saints-row-modding) and a private workspace name (codebase-memory); a stale Forge 5.x verification reference remained; README restated a wrong body-budget skill count; README buried install steps at line 215; Claude Code listed 68 of 165 live skills without descriptions (1% listing budget).
- Release https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.27.1 at fad01c35870acae958d77d60c7fae9146ff6b5ed, self-published by `release.yml` (run 40823562197) after 12/12 checks: Core 45,328,105 B sha256 5fcb95ccc2ce9ef7805e8214998f5a269b29e38461162382a09c0fe9886ab6d7; Full-Offline 141,734,101 B sha256 c1457a044bab575bf6624084dcd651f831d885aa07a9e0e872510b9a911882ce. Downloaded: `sha256sum -c` clean for all 9 assets, attestation signed by release.yml@refs/heads/main, receipt companions skyrim-forge 6.5.1 and reverse-this 1.7.0 (picked up automatically), notes open with "Which file?".
- Gates: local pack gate PASS (run with `-TestPython artifacts\recovery\test-env-314\Scripts\python.exe`), release contracts 154/0 against the latest fetched companions, maintainer/provenance/regression suites OK, docs/version/memory/manifest/privacy gates PASS. New guards: stale companion wording in five user files, README-CORE equals the shipped note, Claude listing budget pinned in the starter, drive-letter Steam library paths blocked.
- Live: install exit 0, doctor PASS 8.27.1 0/0; `~/.claude/settings.json` gained only `skillListingBudgetFraction: 0.03` (backup `settings.json.before-starter-20261029-022143807.bak`); CLAUDE.md content paragraph and Codex model/effort unchanged; live skills reconcile exactly (105 bundle + 48 Forge + knap + 11 user-installed replica-*).
- User actions left: turn off the 14 claude.ai account skills that duplicate bundle skills (adult-character-sheet, adult-image-caption, ai-tooling-stack, codebase-memory, fictional-adult-modding, housecarl, skyrim-assets-pbr, skyrim-forge, skyrim-sexlab-to-ostim-modernization, skyrim-ship-gate, skyrim-tool-router, skyrim-voiced-dialogue, tool-discovery, unrestraint-packs); optionally remove the unused replica-* skills.
- After the release: two quick pushes showed that a Release run triggered by a cancelled (superseded) CI was *skipped* and GitHub filed it under main's newest commit, so `Wait-External.ps1` read that commit as failed. `release.yml` now has no job-level `if`; its decide step turns a non-green trigger into a no-op, and the release contract forbids the job-level gate.
- Not exercised: a fresh Windows account, game/GUI runtime, paid inference, Codex/Grok/Hermes skill-listing limits; no uninstaller exists.

## Completed 8.27.0 independence pass — 2026-10-29

- Goal completed: the three repositories develop and release independently. The bundle pins no companion version (CATALOG.json holds a floor); a Forge or Reverse THIS! release never needs a bundle release. Proven live: bundle 8.27.0's Full-Offline picked up Forge 6.5.0 and Reverse 1.7.0, both released minutes earlier, and the live install then moved Forge 6.4.2 -> 6.5.1 with no bundle change.
- Releases (each published by its own `release.yml` from the exact pushed SHA, no human tag; downloaded, `sha256sum -c` clean, GitHub build attestation verified to `release.yml` on `main`):
  - Bundle https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.27.0 at d3599f3a73665700802ec940e8bfce64ea3754a8: Core 45,347,809 B sha256 df7812fa7fbef37a8b111ab35d85fb72c8a2d50d43d8bad6bafbe7d491d3e3a5; Full-Offline 141,753,844 B sha256 018069817734d37387b92d26bb405ea8e9948506fd0afb02579ab66040fd400a; plus SHA256SUMS, BUILD-RECEIPT (run 40815582771, win25-vs2026, Python 3.14.9), SBOM (SPDX 2.3, 33 packages), VALIDATION (11 observed checks, all success), MANIFEST.
  - Forge https://github.com/SenjuWoo/SkyrimForge/releases/tag/v6.5.1 at 012765ba9f62e12fc00bb4c1d69db7fdd6d28d52 (6.5.0 at 1cf795b the same day): self-publishing workflow, version-free skill, README history labelled, personal path and drive-letter scan removed, Forge-side contract tests. Skyrim-Forge-6.5.1.zip sha256 5b7314f708e52b60b87598ead503e12ebbb0a83de31a7e45b39713c13231f82f.
  - Reverse THIS! https://github.com/SenjuWoo/reverse-this/releases/tag/v1.7.0 at acee844903b04dffb70e3a444907c104c60cbd85: doctor re-hashes receipt files (CHANGED/UNVERIFIED states; all 59 live tools verify), self-publishing workflow. Reverse-This-1.7.0.zip sha256 32da083f29b03a8921a419de415354fe48013ee7a554adb2cd337c3a9968a747.
- Trunk flow live on all three: rulesets `integrity` (no force-push/deletion, no bypass) and `checks` (PR merges wait for CI, admins push directly; bundle requires 8 checks incl. "Bundle installs latest companions end to end"); classic protection retired; Dependabot auto-merge workflow; Wait-External reads effective rules. One red push per repo during the pass (bundle `$LASTEXITCODE` after an in-process script; Forge 8.3 short path in a new test) — both release workflows refused the red SHA and were fixed forward.
- Gates: `check_versions.py --set` bumps every declaration (caught the README first-line comment it missed) and rejects restated companion versions/Skyrim counts; `#ownership` anchor guarded; workspace AIO copy guarded (it had drifted); release contracts 153/0 run against the latest fetched companions; full Windows pack gate PASS; CI weekly against latest companions.
- Skyrim cost (pack off, the default): 0 skill index entries, 0 MCP servers, 0 instruction bytes (pack blocks only for enabled packs; Forge writes its skills only when on; global Forge MCP entries retired). Pack on (this machine): +48 Forge skills (6,859 index chars), +1,808-byte instruction block per provider file, 0 global MCP servers (Forge/houseCARL start through the toolbox in Skyrim projects). Discoverability: the installer prints "enable explicitly with -Packs skyrim"; README says the same.
- Ownership proof (W14): bundle install -> Forge Install-Skyrim-Pack (5 providers) -> bundle install left all 7,819 provider skill files byte-identical; 8.26.1 -> 8.27.0 changed exactly ci-convergence, Setup-HouseCarl, skyrim-forge SKILL/INSTALLATION x5 providers.
- Live: install exit 0 twice, doctor PASS 8.27.0 0/0, Forge 6.5.1, Reverse 1.7.0 (git checkout clean; the superseded uncommitted 1.6.2 plan is kept in its sandbox/backups), CLAUDE.md content paragraph intact and new trunk line present, Claude settings.json and Codex model/effort unchanged, no global skyrim-forge entry.
- Metadata: bundle description lists six providers; Forge and Reverse homepages set; ShugokiFable URLs fixed in 14 release notes; no ShugokiFable in any tree.
- Deliberately not changed: tracked MANIFEST.json (deeply wired into the builder and verifier, cheap in packed history); third-party offline payloads stay in git (reason in docs/COMPANION-ARCHITECTURE.md); git history not rewritten (it would move every published tag); Forge's own STATE "Next" lines follow its next-release convention.
- Next: nothing pending. Push to main after `TESTS/Test-Pack.ps1`; bump with `python .github/scripts/check_versions.py --set X.Y.Z` plus the changelog sections; the push publishes itself. Not exercised: game/GUI targets, clean-machine install, paid inference.

## Completed 8.26.1 Forge/bundle MCP ownership fix — 2026-10-29

- Problem fixed: Forge's standalone `Register-MCP.ps1` wrote a global `skyrim-forge` entry and the bundle installer removed it (the toolbox serves Forge on demand), so each installer undid the other.
- Forge 6.4.2: https://github.com/SenjuWoo/SkyrimForge/releases/tag/v6.4.2 (PR 30; tag at 9a568aa196d4eafbb9049deaab35ebf284a884a7 after 14/14 checks; release run success). Registration reports `DEFERRED` per provider whose MCP config has the bundle `toolbox` entry while `toolbox-profiles.json` lists `skyrim-forge`; `-Global` overrides. Bridge suite 9/9 including a real Kimi deferral/`-Global` round trip; full Forge validator PASS twice plus idempotence. Skyrim-Forge-6.4.2.zip 4,833,006 B sha256 4bb55d67d44b2c3ac0593c56d4db5dd6d3fae0ce3f5a88a3454e447953d3d496 matches GitHub digest and SHA256SUMS.
- Bundle 8.26.1: https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.26.1 published by release.yml at 8f13d795b1afabd5a015c44e335f5e8fb1020e7c (PR 24). Re-downloaded: Core 45,333,697 B sha256 087e797068d16dd371d6b581d0f26d6daa39cfb73d5f9429a6183e27e35ebfda; Full-Offline 141,738,906 B sha256 ed5a2d417ce708a6abc89f597580cfe3da84db3bbee4bdd8d607af5843cf67f5; both match GitHub digests and .sha256 files. New drift gate: `check_versions.py` fails if the pinned Forge stops deferring or INSTALL-AIO stops writing `toolbox-profiles.json` (proven failing on the 6.4.1 pin).
- Live: install exit 0, doctor PASS 8.26.1 0/0, Forge 6.4.2, five providers answer the always-on MCP checks, CLAUDE.md content paragraph intact, Claude settings.json unchanged. Proof on this machine: installed Forge `Register-MCP.ps1 -Provider All -Yes` reported DEFERRED for Codex, Claude, Grok and Hermes (Kimi not installed) and left every provider config byte-identical.
- Security: open Dependabot/code-scanning/secret-scanning 0 on all three repos; each has only `main`.
- Forge's own STATE.md still reads "Next: full gate…" for 6.4.2; per Forge's convention it is refreshed with its next release (a docs-only edit there regenerates its hashed reports).

## Completed 8.26.0 tri-repo sync — 2026-10-29

- Goal completed: three cooperating owners, proven drift gates, Skyrim optional, hands-off releases, stale branches cleared. Live versions: Bundle 8.26.0, Skyrim Forge 6.4.1, Reverse THIS! 1.6.1.
- Ownership model (unchanged): Forge and Reverse THIS! own their code and semver; the bundle pins one release of each in BUNDLED-TOOLS/CATALOG.json (tag, asset, SHA-256) and ships those archives for Full-Offline. No vendored source tree.
- Gates proven to fail on tampered copies: Forge skill inventory, offline archive digest (one flipped byte), doctor contract (`result`/`read_only_ready`).
- First hands-off release: https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.26.0 published by release.yml run 40803716797 at 3a966853864e9695051e210ac79acabe628fce86 after all 11 check runs passed; built twice identically, re-downloaded and compared in CI. Independently re-downloaded: Core 45,333,643 B sha256 d7c0879c506caeea7000f55275c7e40377de78768257eab77fbd701cfd020eb4; Full-Offline 141,737,896 B sha256 584166a3c19dfcc3ac48a7d8c2141d64d3a38ac7daaa141522e626cf35aebe55; both match GitHub digests and .sha256 files.
- First attempt (aee376f, PR 21) went red on two pack-gate legs and release.yml correctly skipped. Cause: Wait-External turned a complete `pending` poll into `unknown` when the deadline hit a re-poll. Fixed in PR 22 with a deterministic fixture case (fails on the old waiter). PR 21 had merged with 3.12 red because only 3.14/3.15 were required; main now requires all eight checks (four pack-gate legs), strict, admins enforced, no force-push/deletion.
- Live install: exit 0, doctor PASS 0/0, five providers answered the always-on MCP checks; Forge 6.4.1 and Reverse 1.6.1 in place; live CLAUDE.md keeps the content-permission paragraph, no retired paths. Claude settings.json and Codex model/effort unchanged. Log: LOCALAPPDATA/Ultimate-AI-Starter-Bundle/logs/install-20261028-225404.log.
- Security: Dependabot, code-scanning and secret-scanning open counts 0 on all three repos; code quality unavailable, left off. Each repo has only `main`.
- Branches: 37 proven-merged branches deleted across own repos (ancestor of default, or tip equal to a merged PR head, re-checked before delete); 15 green Dependabot PRs merged (three after a rebase or branch update); Cuda-Spirit 15 closed by Dependabot as superseded. Local bundle and live Reverse kit checkouts are on `main` with merged branches removed.
- Left for the owner, not merged: BDO-AIO `feat/open-chest-uncut` (4 commits, 0 behind) and `dev/partcut-research` (1 commit, 40 behind); ai-prompt-library `master` (no common history with `main`); fork branches with own commits (`modlist-stability` in four 1001Bits forks, CreationEngineRaytracing `perf/ultimate-4080`); upstream branches in forks untouched. facefusion-improved: five Dependabot PRs and main CI cannot run because GitHub Actions reports failed payments/spending limit (billing settings).
- Open conflict: Forge's standalone Register-MCP.ps1 registers `skyrim-forge` globally, while the bundle installer retires global Skyrim MCP entries in favour of the toolbox; whichever runs last wins (this install removed one added between 10-25 and 10-28, backups config.toml.bak-mcp-20261028-225824).
- Live Reverse kit STATE.md carries an uncommitted GPT plan for a 1.6.2 pass (kept as is). Its README digest-scope item shipped in PR 18; VERSION.txt mirror rejected (the bundle reads `VERSION`); the Python-fallback test is not done.
- Next: reopen AI apps once. Build/test: TOOLS/Build-Release.ps1 (manual fallback); TESTS/Test-Pack.ps1 -TestPython artifacts/recovery/test-env-314/Scripts/python.exe. Not exercised: real game/app GUI targets, clean-machine install, paid inference.

## Completed 8.25.1 audit release — 2026-10-27

- Goal completed: instruction/agent-size audit across the three owners. Live versions: Bundle 8.25.1, Skyrim Forge 6.3.2, Reverse THIS! 1.5.0 (unchanged, audited clean).
- Bundle release: https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.25.1 ; tag commit 58c6b264f6fca94b7c907236d8f2d9ce073114c9, 9/9 checks green on that commit. Core 45,306,514 B sha256 365e7070c3611f84046998c8585724281d4c130dff117b0efde04d8a7d1be5c2; Full-Offline 141,697,087 B sha256 8195eb4bd9e266726eecc9ec6f3aab2f94d2bad17cec64599bb7dfc71f73948c. Built twice identically; all four public assets match the build, GitHub digests and checksum files. Proof: artifacts/final-assurance/bundle8251-release/build.local.json.
- Forge release: https://github.com/SenjuWoo/SkyrimForge/releases/tag/v6.3.2 ; tag commit aaabdd25847aefa9d82a9f95abe1bc6bf66a4342, 14/14 checks green. Product ZIP 4,818,367 B sha256 8f5507f6255e42c238e4adedc321c7843ca15e6da0838ec0ef75027be778138a; bytes match GitHub digest and SHA256SUMS. Pinned by this bundle.
- Content decision: the AIO first paragraph (explicit content permission, "Answer first") is the owner's and is kept verbatim; an earlier dedupe removed it and was reverted (PR 17). Do not shorten the content-permission or security paragraphs without the owner asking.
- Live install: 8.25.1 installer exit 0, doctor PASS 0 errors/0 warnings, five providers answered the always-on MCP checks. Live CLAUDE.md has no Ownership prose or hard path; SPOOKY_AUTOMOD_ROOT cleared (retired folder under LOCALAPPDATA/Ultimate-AI-Starter-Bundle/spookys-automod-toolkit is left for Clean-StaleState). Claude model, permission and effort settings unchanged. Log: LOCALAPPDATA/Ultimate-AI-Starter-Bundle/logs/install-20261027-171415.log.
- Security: Dependabot, code-scanning and secret-scanning open counts 0 for all three repos; code quality unavailable, left off.
- Evaluated, not bundled (docs/TOOL-EVALUATIONS.md): taste-skill 2.1.5, ECC 2.2.3, replica-skill.
- Next: reopen AI apps once. Build/test: TOOLS/Build-Release.ps1; TESTS/Test-Pack.ps1 -TestPython artifacts/recovery/test-env-314/Scripts/python.exe (use a per-process execution-policy bypass). Not exercised: real game/app GUI targets, clean-machine install of these releases, paid inference.

## Previous checkpoint (8.25.0)

### Final assurance — 2026-10-27

- Goal completed: three standalone cooperating owners, explicit project ownership, private-by-default new work and clean product distributions. General AI/build/workspace tools belong to the bundle, Skyrim tools to Forge, reverse-engineering tools to Reverse THIS! Shared installations are discovered/reused and version-checked; project pins/newer versions and personal edits are preserved. The companion architecture analysis remains in docs/COMPANION-ARCHITECTURE.md.
- Public and live versions: Bundle 8.25.0, Skyrim Forge 6.3.1, Reverse THIS! 1.5.0. Existing repositories retain visibility/licences. Explicit GitHub publication means public/MIT for original work subject to rights/terms; generic Skyrim publication normally means Nexus, with no duplicate GitHub for mods needing no compilation. New projects stay local until publication is requested.
- Bundle release: https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.25.0 ; immutable tag commit ed26acc6d7fa78fbbf181e3364f777911d5c4977. All nine checks on that commit passed before packaging; security flags clean. Core and Full-Offline each built twice byte-identically from its Git archive. Both extracted products pass delivered-manifest/7-skill-tree/actual launcher-help checks (7,574 and 7,582 manifest rows). All four public assets were downloaded and match local bytes, GitHub digests and checksum files.
- Core: 45,261,764 bytes; SHA256 0610fe2e8beb73ef7aed3b454fff296b13059b5e120613ade201fd06cf587a6a. Full-Offline: 141,652,713 bytes; SHA256 6e9d8a6bfa5f35d075deb8721ba14cf7aa5056172c92c9f1b47b2d363b454a69. Proof: artifacts/final-assurance/bundle825-release/build.local.json and verified/final.local.json. Later handoff changes only source validation/STATE/integrity metadata and never moves this tag or replaces assets.
- Forge release: https://github.com/SenjuWoo/SkyrimForge/releases/tag/v6.3.1 ; frozen commit 533f399c7eded2fa75c0bc2dabd809ec999ccc50, clean handoff main 1f7dcb8c3a360a14c6bc678dfa1ee52950bcdcc8 (all 23 checks pass). All eight public assets match CI build/GitHub digests/checksums. Product ZIP 4,818,789 bytes; SHA256 ff6f4e04dcb362cd3ceb65d0d17292c4d2ed715e8558b093e3f635578d890fa4. Both same-toolchain builds are identical; all 540 payload files/metadata agree across Python compression toolchains and all 539 installed manifest files match public bytes. Published 6.3.0 remains immutable and is superseded; never deploy it. Proof: forge631-final/completion.local.json and verified/final.local.json.
- Reverse release: https://github.com/SenjuWoo/reverse-this/releases/tag/v1.5.0 ; frozen commit ab9b842d8a5f7bfce7c128f5f94c1421e3933723, clean source main f5c0da39501ac0257f2d58484e8f9d288caf3071 (all seven checks pass). Both public assets match build/GitHub digests/checksums. Product ZIP 64,217 bytes; SHA256 5734af455687f5c4345a497f8ea672e6fb0d2249f060e79ada36628b09b8a7ca. Existing selected tools refreshed with NoUpdate: 56 success/0 failures, doctor PASS. Proof: reverse150-final/verified/final.local.json. Private target work, tool versions and shims preserved.
- Final local gate completed BEFORE remaining releases: live bundle 8.25.0 doctor 0 errors/0 warnings; Forge native version/self-test/doctor and 53-tool MCP probe PASS; houseCARL MCP 31 tools PASS; fifteen real core MCP probes across Claude/Codex/Grok/Hermes/Antigravity PASS. Kimi remains unselected. Thirteen saved model/permission/MoA fingerprints are unchanged, including the final pre-publication recheck. Canonical ownership helper matches five provider roots and four Hermes profiles.
- Strict historical inventories proved 13 stale generated Hermes Skyrim-profile skill copies; backed up and migrated through Forge's owner installer. The general ai-tooling-stack remains bundle-owned. Private Forge workspace identity is unchanged; its config differs only in installer-owned tools.ui_worker.version. Source/runtime versions use Forge VERSION.txt, without requiring source CURRENT.txt. Dual-shell marker tests and real live install pass.
- Backups: LOCALAPPDATA/Ultimate-AI-Starter-Bundle/backups/final-8.25.0; previous Forge owner LOCALAPPDATA/Skyrim-Tools/.forge-backup-e24f81ce5dba4f229bdd866b0cb7ab1d; Hermes historical copies LOCALAPPDATA/Skyrim-Forge/backups/verified-hermes-profile-a57bf791255949f8ad170cf080b506eb. Reverse source backup remains sandbox/backups/source-1.5.0-62f9c745017b4caab100684cbb66b0b4. Keep previous tags/releases and rollback evidence.
- Source validation: full 19-section Windows pack gate PASS; release contracts 151/0; ownership/publication/junction tests 7/7; real product/fanout tests 2/2; all 7,882 source manifest hashes and version declarations agree. A stale validation release tag is now rejected. Forge full release validator: 230 Python tests plus native/Go/race/installer/reproducibility gates PASS. Unchanged compiler/shared Python 3.14.10 real compile evidence is reused, without installing another base Python. Official CI action pins refreshed across all owners.
- Evidence owner: artifacts/final-assurance. Final local receipts: pre-publication-local-proof.local.json, bundle825-final-installed-doctor.local.json, forge631-live-local-proof.local.json, installed-ownership-helper-proof.local.json, housecarl-prepublish-mcp.local.json, final-8250-settings.local.json and Hermes migration proofs. Successful installed log: LOCALAPPDATA/Ultimate-AI-Starter-Bundle/logs/install-20261027-122557.log and details. Source logs: bundle825-final-pack.log, bundle825-final-contracts.log and bundle825-frozen-build.log.
- Security: open Dependabot/code-scanning/secret-scanning counts zero. Code quality unavailable and left off; no alert dismissed or forbidden scanner/secret pattern enabled. Final source handoff check/security/clean-tree receipt is captured after this documentation commit in artifacts/final-assurance/completion.local.json.
- Next: no implementation, release or live-deployment work remains. Reopen AI apps once to load refreshed instructions/MCP state. Use START-HERE.bat when another update is wanted. Build/test: TOOLS/Build-Release.ps1; TESTS/Test-Pack.ps1 -TestPython artifacts/recovery/test-env-314/Scripts/python.exe. Preserve existing settings and use supported per-process PowerShell execution-policy bypass, never a machine policy change.
- Exact limits: actual game/app GUI targets, guest Windows Sandbox, paid inference/API runtime and real absent-provider installations remain untested. Compatibility holds remain evidence-based; no guarantee of arbitrary future upstream compatibility is claimed. No further broad research or unchanged-input checks are needed.

## History

Superseded checkpoints: docs/history/STATE-ARCHIVE-8.19-8.25.md. Per-release notes: CHANGELOG.md and docs/history/.
