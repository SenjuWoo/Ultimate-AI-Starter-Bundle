# Bundle audit state

## Fresh Windows recovery (2026-10-23, v8.21.1 source gates)

- This tree is v8.21.1. The published GitHub release is still v8.21.0 until a
  release is cut from the pushed commit. Source fixes do not change the
  downloadable archives by themselves.
- Failure that was fixed: an empty provider scan installed all six providers,
  then the old Codex PowerShell installer URL returned HTTP 404. A plain run
  now stops when no app is installed. Choose `-Providers Claude,Codex` or
  `-AllProviders`. A missing Codex CLI installs with `npm install -g @openai/codex`.
  Git for Windows is still required, because plugin hooks need Git Bash.
- Workspace seeding fills only missing files. Stale-state cleanup previews
  unless `-Apply` is passed. Fresh Grok starter settings keep the vendor
  permission prompt. Existing permission and model choices stay user-owned.
- Hook commands that still point at the pre-rename hooks folder are recognized
  through `Get-UabsLegacyHookRoots`. The retired folder name stays in that helper.
- Shared Python is the `python` / `UABS_PYTHON` interpreter (3.14.9 on this
  machine). The Python 3.15 directory has no `python.exe`; do not point tools
  at it. Pack tests use `-TestPython` on a disposable venv. `pwsh.exe` is not
  installed; the gates below ran on Windows PowerShell 5.1.
- GitHub CLI auth was restored from the existing keyring into the real
  `%AppData%\GitHub CLI` hosts file. No new browser login. Re-query flags
  after the push.
- Measured 2026-10-23:
  - `.github/scripts/check_versions.py` exit 0.
  - `.github/scripts/verify_manifest.py`: verified=10361, missing=0, mismatch=0.
  - `python TESTS/test_release_contract.py`: 151 passed, 0 failed, exit 0.
    Log: `artifacts/recovery/contract-8211b.log`.
  - `TESTS/Test-Pack.ps1 -TestPython` on a disposable venv with mcp==1.30.0
    and PyYAML==6.0.3: PACK GATE: PASS, exit 0. That run includes all 63
    provider subsets, bootstrap, workspace seeding, installer preservation,
    hook scope, and the doctor scope gate.
    Log: `artifacts/recovery/pack-8211b.log`.
  - `TOOLS/hooks/hermes_wire.py --selftest`: PASS on that same interpreter.
- Pushed `74f1c90` to `main`. CodeQL succeeded. GitHub flags were clean
  (Dependabot, code scanning, and secret scanning 0 open; code quality
  unavailable). CI failed on the Core zip: `README-CORE.txt` was written twice.
  The builder writes that note once. That fix is not on `74f1c90`.
- First live `INSTALL-AIO.ps1 -Providers Claude,Codex -SkipSelfUpdate` left
  Grok, Kimi, Hermes, and Antigravity untouched, then stopped because the
  Codex MCP proof used `Get-Command codex` and the CLI was not on that
  process PATH. Log:
  `%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\logs\install-20261023-205012.log`.
- The same command, after the shared Codex resolver and the shell check,
  finished: `INSTALL COMPLETE (v8.21.1)`, exit 0. Claude and Codex always-on
  tools answered (context7, headroom, toolbox). The installed-state doctor
  inside that run passed. Grok, Kimi, Hermes, and Antigravity were not
  touched. Existing Claude and Codex settings were preserved. Log:
  `%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\logs\install-20261023-211512.log`.
  Doctor report:
  `%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\installed-state-doctor.json`.
- The doctor used to fail on `bash.exe` because Windows searches the machine
  PATH first and `System32\bash.exe` is the WSL launcher. Git's `bin` was
  already on the user PATH, and `sh.exe` already resolved to Git. Hook
  dispatchers skip the launcher, so a later Git Bash counts.
- Re-ran after those edits: release contract 151 passed, 0 failed;
  `TESTS/Test-Pack.ps1 -TestPython` PACK GATE: PASS on the disposable venv;
  hook-shell gate PASS, including a real Git shell.
- Pushed tip `29e2cd7` (code fix `2327c20`). CI run 40044617095 succeeded,
  including the Core archive step on Python 3.14 and 3.15. CodeQL run
  40044617122 succeeded. GitHub flags were clean (Dependabot, code scanning,
  and secret scanning 0 open; code quality unavailable). Public v8.21.1
  archives are not published. Restart Claude and Codex so they inherit the
  updated environment. `cua_repl` stays unwired
  (`CUA_REPL_NODE_REPL_PATH` unset) and is not an always-on installer check.
  `pwsh.exe` is still not installed.
- Notes below this heading describe the pre-reset machine and the v8.21.0
  release. They are not this install's result.


## Active whole-bundle audit: v8.21.0 (2026-10-22)

- Baseline 48097c7 (v8.20.1), clean checkout, moved owner folder verified.
- Fixed toolbox ambiguous write replay (real fixture failed with two writes,
  now one), hung-start cancellation and HTTP prerequisites; toolbox 1.0.2.
- Offline updater now rejects bytes outside its reviewed manifest pin and
  propagates errors before InstallAfter; disposable real-file gate PASS.
- Accepted Superpowers 7.0.1 (six vendored fixes + canonical routing preserved),
  GitHub MCP 2.0.3 (official digest + scoped 47-tool handshake), Chrome DevTools
  1.12.0 (32-tool handshake), optional Comfy CLI 1.23.0 (UTF-8 help).
- Freshness: current=23, held=6, stale=0, skipped=1 (bundle-owned), error=0.
- Source gates: Windows Test-Pack PASS; supported contract runner 151/0;
  toolbox real stdio + timeout/HTTP/lost-reply gate PASS; offline-update PASS;
  audit regressions 15 + 7 subtests PASS; privacy/bootstrap/UM PASS;
  Impeccable security PASS. Superpowers documented sequential integration
  runner PASS (parallel node --test produced shared-port fixture conflicts).
- All 174 skills retained; oversized bodies 6 -> 4, upstream references retained.
  No reasoning/model/validation downgrade. Report: docs/AUDIT-2026-10-22.md.
- Python 3.12 was removed externally during the audit (child imports failed);
  discovered 3.14 and revalidated contracts/toolbox/audit there. Use py -3.14.
- Installed baseline doctor: ledger 8.20.0, modified/duplicate Codex skill-creator;
  no global task MCP leaks. Ownership-aware skills sync pending; full runtime
  refresh should run with AI apps closed to avoid in-memory config writers.
- Skills sync complete: doctor 8.21.0 PASS, zero warnings; modified duplicate
  skill-creator backed up by the installer. Old toolbox/GitHub processes are
  still running; refresh runtimes after AI apps close.
- Late hold recheck: engine 0.1.16 still fails malformed script/style; Firecrawl
  3.34.1 audit 0 findings + integrity + credential-scrubbed handshake PASS.
  Replaced obsolete hold with a toolbox/project route and key prerequisite.
- Owner removed 3.15 and installed 3.14.9; verified python == py default,
  only one registered shared base. Applied shared runtime policy with local
  environment backup; uv automatic interpreter downloads disabled. Embedded
  app runtimes are app-owned and are not removed.
- Shared-runtime wiring now covers uv tool installs, project auto-install,
  uvx profiles, Hermes creative profiles and toolbox launchers. Default
  fresh runtime comes from the official stable default; existing user PATH
  wins over Forge hints, and manager default/version choices are preserved.
  Shared Python boundary gate PASS (runner vs child arguments, failure,
  idempotence, rejection of a venv as shared base).
- Toolbox 1.0.2 wheel built; catalog/offline pin updated. Machine-map generator
  now probes the working install-manager alias instead of assuming Store stub.
- Seven uv tools rebuilt against shared 3.14.9 and toolbox 1.0.2. Active
  Hermes launcher uses its app-owned managed engine; its obsolete source venv
  is not the active interpreter. Managed engines are not treated as a shared
  base or deleted. Hermes config helpers now resolve the active launcher.
- Real Hermes LocalEnvironment.execute returned code 0 and Python 3.14.9;
  shell-init route applied to ten profiles, preserving unrelated config.
  Hermes hooks now use shared user Python; hook wiring and starter API/shim
  sync PASS. All six provider executable/startup probes PASS; auth/inference
  not exercised. Live provider apps still need reopening to inherit settings.
- Shared Python gate and toolbox stdio gate PASS. MCP profile gate PASS after
  preventing a launcher on PATH from initializing an explicitly absent data
  root. Old source tests failed on an accidental RTK pin edit; pin restored.
- Final local contract runner 151/0; full Windows pack gate PASS. Real YAML
  preservation/idempotence/malformed-input fixture PASS. Seven tool dependency
  checks + five CLI help probes PASS; all six provider startup probes PASS.
- Scoped installed sync completed; all six core MCP handshakes and doctor PASS.
  Its registrar warned on a removed legacy property; both consumers are fixed
  and the real Hermes registrar refresh now PASS. Native plugins/skills and
  machine maps synced with personal model/trust/settings preserved.
- Public fresh setup now uses the official Python install manager's stable
  default (signed index dry-run selects 3.15.1), preserving existing versions;
  no manager minor-version lock. CI covers shared Python 3.14 and 3.15. Explicit
  project venvs retain priority inside Hermes terminal sessions.
- Upgrade binding repair PASS. Added real Unicode-base-path regression after
  reproducing a PS 5.1/OEM path corruption: Python probes now return ASCII JSON,
  preserving the actual path without copying or downloading a runtime.
- Owner rebooted; shared 3.14.9 and the no-download policy survived. Previous
  revision 30bd948 has green CI on both 3.14/3.15 plus CodeQL. New Unicode
  discovery/PATH verification gate PASS, including a real junction alias.
  Working Python manager aliases are kept rather than adding a version lock.
- Released v8.21.0 (tag `v8.21.0` -> `d6cdf74`, Latest). Exact-SHA CI and
  CodeQL green; catalog audit current=23, held=6, stale=0, error=0.
  Archives built twice with DIFF=0 and re-hashed after public download equal:
  Core 54,934,756 B `0914670bc2b9cd0a...`, Full-Offline 223,309,264 B
  `1a4123740c6d94b7...`. Final review fixed one unbalanced paren in the uv
  tool base probe (`print(json.dumps(sys._base_executable)))`), which had
  silently forced needless tool reinstalls.
- Next: reopen AI apps so they inherit the new shared-runtime environment;
  the held components (houseCARL 1.9.0, impeccable, unity-mcp, firecrawl,
  perplexity) still need their own migrations before they can auto-update.



## v8.20.0: Tools/Modding folder review, mashup skill, UM refresh (2026-10-21, released)

- Owner asked to review the new `Tools` (6 snapshots) and `Modding` (bench +
  `Game-Mashup-Passthrough/LESSONS.md`) folders and bundle or document as best.
  Decision: bundle nothing from the bench (5 GB third-party binaries); everything
  else below. Read-only review, no bench tool executed.
- `Tools`: all six already covered. REA snapshot 6.5.0 < pin 6.7.0 (current);
  `universal-modder-main` predated the pin (no `sprixen.py`) and upstream had 28
  newer commits -> refreshed UM `6a8865a` -> `c1dff21` with
  `TOOLS/refresh_universal_modder.py --apply` (20 patches re-applied; changed
  `um/*.py` read; new `um voidless` uses the patched hidden `mask`), wheel
  `universal_modder-0.2.0+uabs.c1dff21` 3,618,451 B sha256 `43207bb6...5d82`
  built twice identical (SOURCE_DATE_EPOCH=1792022400), CATALOG/OFFLINE-MANIFEST/
  test pin updated, old wheel removed. CLI-Anything 0.4.0, anti-slop 3.2.21,
  jevgrep 0.8.0, Reverse THIS! 1.2.1 each still latest -> stay documented only.
- `Modding`: new skill `_CANONICAL-SKILLS/game-mashup-passthrough` (order of work,
  guardrails, shell traps); `project-intel/references/game-mashup-melty.md` +
  "Drawing under the UI", texture/hair rules, spike order, freeze/teleport traps;
  router row updated; `tool-discovery/references/modding-bench.md` re-inventoried
  (Noita, RoR2 kit/SDK, Roblox Chrono, `_downloads`, Tools-folder lag note). The
  source file's section 9 (install/log paths, launch URI) and game-specific
  offsets/file counts deliberately NOT shipped. `docs/TOOL-EVALUATIONS.md`
  dated section added.
- Counts: 174 canonical skills (125 general per AI + 49 Skyrim pack); contract
  `test_game_mashup_passthrough_knowledge_is_wired_and_private` (151 tests).
  `RETIRED-SKILLS.json` regenerated; new provider-tree skill paths are
  gitignored and need `git add -f` (fanout prints the command).
- Gates so far: contracts 151/0 (-W error clean), privacy, UM, audit regressions,
  hermes bootstrap, toolbox PASS; MANIFEST 10,280 verified; versions agree.
- After the first push (fa07679) Dependabot opened hundreds of alerts (Pillow
  <=12.3.0 x3 advisories, certifi critical) over every Pillow pin: UM pyproject
  and `img2threejs` `vision` + `glb_character_pipeline` (pyproject + uv.lock, in
  canonical and all six provider trees). Fixed at the source: UM `pillow==13.0.0`
  (refresh-tool patch too; UM tests 178 pass on Pillow 13.0.0 in a scratch venv),
  both integrations `<14` and `uv lock --upgrade-package pillow --upgrade-package
  certifi`; fanout re-run. Dependabot PR #7 (vision only) is superseded.

### Publication checkpoint (v8.20.0)

- Tag `v8.20.0` -> `55465b75071198c0afa306f9a613336c0a35fef0` (not fa07679: the
  first push was superseded by the Pillow/certifi fix before any tag existed).
  CI (4 jobs) and CodeQL (3 jobs) success on that SHA; Dependabot / code-scanning
  / secret-scanning open alerts 0 (`TOOLS/Get-GitHubFlags.ps1` flags=clean;
  code_quality unavailable, left off).
- Archives built twice byte-identical: Core 54,893,843 B
  `eb09f5faf192eb77cc4561379bfbfd52dd16bfcb4ef9ca6f61657310c10ed5e5`,
  Full-Offline 223,136,062 B
  `3e427ffee1802d99224660e29272b647ee445bac30e8032051fb9eec6b0eb08f`.
  Extracted under a space+Unicode path: contracts 151/0, manifest verified
  (10,272 Core / 10,280 Full), Test-Pack PASS in both.
- Release published as latest; downloaded assets equal the build (cmp, size,
  sha256 sidecars, GitHub digests). Receipts: ignored `artifacts/release-v8.20.0/`.
- Real START-HERE run on this PC after the release (336 s, longer than the
  265 s of 2026-10-20: new wheel and Pillow 13 download, skills re-synced):
  INSTALL COMPLETE, doctor PASS, 0 warnings, 0 TerminatingError;
  `game-mashup-passthrough` present in Claude, Codex, Grok, Kimi, Hermes and
  Antigravity skill dirs; preserved Impeccable 4.3.1 untouched; `um voidless`
  live.
- Not certified: the new skill was not exercised in a live mashup session
  (needs a fresh chat after the apps are reopened); provider inference; game
  runtime; billed-token savings.
- Open for the owner: the local `Tools\rea-main` (6.5.0) and
  `Tools\universal-modder-main` snapshots lag the pack's pins; the pack never
  reads them. Dependabot PR #7 (img2threejs vision) is superseded by the fix;
  close it if it stays open.

## v8.19.2: review of v8.15.1..v8.19.1 + install speed (2026-10-20, released)

- Owner asked to verify the DeepSeek-era edits (v8.15.1..v8.19.1, all committed),
  find bugs, make the install faster. Baseline on HEAD 58c8180: contracts 150/0,
  Test-Pack PASS, manifest 10,241, versions agree, privacy/toolbox/hermes/MCP/
  codex-native/UM gates PASS; catalog audit stale=1 (blender-mcp).
- Profiled the last real install (logs `install-20261018-050020*`, 5 min 24 s).
  Fixed, each measured on this machine:
  - Hermes migrator read config with `hermes config get` per key per profile
    (~4.2 s each). Now one `load_config` process per profile, cached, cleared
    after writes: reads 279.6 s -> 6.6 s (values identical), plan-only run
    152.0 s -> 7.6 s, plans line-identical. Also raw (CLI masked secrets that
    the map write-back would have persisted; none present here).
  - `Get-UabsTreeDigest`: reused SHA-256 instead of Get-FileHash; identical on
    321 trees x 2 sort modes, 4.8x faster.
  - Plugin-owned skills (63: Claude/Codex/Kimi) no longer copied then deduped
    every run; skipped from prior state's `owned`, restored if not native now.
  - Spooky external update re-ran every install (folder-name version) and copied
    from the archive root: now copies from the `.sln` folder, stamps
    `.uabs-version`, `Get-UabsPathVersion` reads the stamp first.
  - `Get-UabsProcessVersion`: stdin closed, 10 s timeout (was unbounded).
    New gate `TESTS/Test-VersionProbes.ps1` (in Test-Pack + contract list).
  - Antigravity plugins refreshed every run; config.json written only on change
    (+ `.bak-uabs`), missing `enabled` property no longer throws.
  - blender-mcp 2.2.0 -> 2.2.2 (handshake PASS, 9 tools, 15,754 B).
  - test_release_contract.py: 4 invalid escape sequences (SyntaxWarning) fixed.
  - VALIDATION.md was left at v8.19.0 with the v8.15.0 text; now v8.19.2.
  - First real install stopped: "Local skill override changed: Claude/impeccable".
    Cause: the v8.19.1 session ran `TOOLS/install_live_skills.py`, which ignored
    `skill-overrides.json` and merged pack Impeccable 4.1.3 over the preserved
    4.3.1 (Claude/Codex/Grok). Restored from `skills.bak-uabs-20261019-195419`
    (ordinal digest == registry, all three); overwritten copies kept under
    `backups\impeccable-overwritten-<prov>-20261020-221510`. Tool now skips
    preserved skills (+ contract); file-handle leaks closed (-W error clean).
  - Second real install: doctor FAIL on REA 6.5.0 (hand-installed, cli-optional,
    never installed by the bundle) after v8.19.1 pinned 6.7.0; advice "re-run"
    could never fix it. Doctor now fails only on `npm-global` copies the bundle
    owns, warns otherwise. Machine's REA moved to 6.7.0 (integrity == catalog).
  - Starter settings: 15 `hermes config get` -> one load_config pass with CLI
    fallback (65.5 s -> 10.2 s). PS 5.1 `'[]'|ConvertFrom-Json` unwrap bug
    caught by the first run (empty key set refused; nothing written).
  - A timing probe of mine re-copied plugin skills into Claude/Kimi and retired
    Antigravity's brainstorming; re-synced with correct excludes (verified).
- Third real START-HERE run (UABS_NO_PAUSE=1, UABS_NO_SELF_UPDATE=1):
  INSTALL COMPLETE, 265 s (324 s on 2026-10-18), 0 TerminatingError, handshakes
  all six apps, doctor PASS; after the REA move the doctor is 0 errors 0
  warnings. Skills+settings 37 s (was 82 s), Hermes migration 20 s (was ~107 s).
- Not changed (by design / needs owner): MCP handshakes stay serial (~35 s;
  parallel npx risks cache contention); `.git` 492 MiB history (needs rewrite).
- Gates after changes: contracts 150/0 (warnings-as-errors clean), manifest
  10,243, versions agree, privacy, hermes bootstrap, toolbox, MCP protocol, UM,
  RTK candidate PASS. Final Test-Pack PASS on the committed tree.

### Publication checkpoint (v8.19.2)

- Tag `v8.19.2` -> `26118b00921b3cea81f1754bd22af49cc12ea89c`. CI (4 jobs) and
  CodeQL (3 jobs) success on that SHA; Dependabot / code-scanning /
  secret-scanning open alerts 0 (`TOOLS/Get-GitHubFlags.ps1` flags=clean;
  code_quality unavailable, left off).
- Archives built twice, byte-identical: Core 53,388,399 B
  `8c1cec4a8f1537747c9211a4b4fad96c817a0c3a62c7d9dfc8c69892408a4a99`,
  Full-Offline 220,186,174 B
  `2eed3917821f5ab5182739c99fa77b9e650a480f8c05b8956a8782ac3294d111`.
  Extracted under a space+Unicode path: contracts 150/0, manifest verified
  (10,235 Core / 10,243 Full), Test-Pack PASS in both.
- Release published as latest; downloaded assets equal the build (cmp, size,
  sha256 sidecars, GitHub digests). Receipts: ignored `artifacts/release-v8.19.2/`.
- Not certified: provider inference, editor/game runtime, billed-token savings.
- Next: owner closes/reopens AI apps once. Candidate follow-ups (not done):
  MCP handshakes are serial (~35 s of ~265 s); `Remove-UabsHermesLegacyOpenRouterExtra`
  still makes 2 `hermes config get` calls (~8 s); `.git` is 492 MiB (needs an
  owner-approved history rewrite).

## v8.19.0: CodeQL fixes, Antigravity provider integration, tool refreshes, full verification (2026-10-18)

- All 11 open GitHub CodeQL alerts (#235–#245) fixed in code in `_CANONICAL-SKILLS/impeccable/scripts/`:
  - Alert #235: `context.mjs:855` regex empty-string replaced with space.
  - Alert #236: `detector/shared/page.mjs:5` comment removal sanitized.
  - Alerts #237, #238: `live-accept.mjs:655-690` index-based string slicing replacing unbounded regex.
  - Alerts #239–#242: `live/svelte-component.mjs:761, 1021` sanitized script/style tag cleanup.
  - Alert #243: `live-server.mjs:96, 1199` explicit relational comparisons breaking taint propagation.
  - Alerts #244, #245: `live-browser.js:29, 7822, 11494` dynamic script loading sanitized with `LIVE_ORIGIN`.
  - Regression suite `node TESTS/impeccable-security-regressions.mjs` PASS.
- Full Antigravity provider integration:
  - Added Antigravity to `CATALOG.json`, `PROFILES.json`, `registry-corrections.json`, `Add-Reasoning-MCPs.ps1`, `Install-SkyrimForge.ps1`, `Set-McpProfile.ps1`, `UABS-Mcp-Write.ps1`, `UABS-Mcp-Park.ps1`, `Test-Installed-State.ps1`, `install_live_skills.py`, `Test-Pack.ps1`, `test_release_contract.py`.
- Windows PowerShell 5.1 extensionless `npm` resolution fixed via `Resolve-UabsExecutable` in `UABS-Common.ps1`, `INSTALL-AIO.ps1`, and launcher filters in `Test-Installed-State.ps1`.
- Hermes `ponytail` plugin manifest detection fixed and upgraded to `5.3.2` with foreign harness manifest stripping in `UABS-Common.ps1` and `INSTALL-AIO.ps1`. Fixed junction collision in `Migrate-HermesProfiles.ps1`.
- Universal Modder refreshed to commit `6a8865ae171b406f50892c7f46fc5f45655269eb`, offline wheel rebuilt (`universal_modder-0.2.0+uabs.6a8865a-py3-none-any.whl`), `OFFLINE-MANIFEST.json`, `CATALOG.json`, and `TESTS/test_universal_modder.py` updated.
- Catalog versions refreshed (`context7` 4.4.2, `chrome-devtools-mcp` 1.11.0, `shadcn-mcp` 4.22.0, `super-mcp-router` 2.8.4); `python TOOLS/audit_catalog_versions.py` passes with 0 stale, 0 errors.
- Verification battery 100% PASS:
  - `INSTALL-AIO.ps1 -SkipSelfUpdate -Mode BundledOnly`: complete (exit code 0).
  - `Migrate-HermesProfiles.ps1 -Apply`: complete (exit code 0).
  - `Test-Installed-State.ps1 -PackRoot . -SkipForge`: PASS (0 errors, 0 warnings).
  - `test_universal_modder.py`: PASS.
  - `Test-Pack.ps1`: PASS (all 19 sections).
  - `test_release_contract.py`: PASS (all 150 tests).
  - `check_versions.py`: PASS (all declared versions agree on v8.19.0).
  - `verify_manifest.py`: PASS (10,239 verified, 0 missing, 0 mismatch).

## Post-v8.15.2: caveman + OmniRoute evaluated, not installed (2026-10-16, docs only)

- Owner asked about JuliusBrussee/caveman 4.0.1 (Apache-2.0, npm
  `@caveman-ai/cli`) and diegosouzapw/OmniRoute 3.8.51 (MIT). Both analysed and
  documented in the README third-party table and `docs/TOOL-EVALUATIONS.md`;
  neither is installed or vendored.
- Caveman conflicts structurally, not stylistically: its installer writes the
  same provider files this pack owns (pinned `installer/install.js` names
  hooks/`settings.json`/statusline/`SOUL.md`/`AGENTS.md`/skills heavily, and it
  installs native Hermes skills), its routing layer repoints
  `ANTHROPIC_BASE_URL`, and `Auto` switches models per request - the
  `token-efficiency` invariant forbids that as a default. Against Ponytail the
  pack already holds the head-to-head data: Ponytail's vendored benchmark
  (5 tasks x 3 models x 10 runs) shows 39/44/51 median LOC vs caveman's
  116/120/67, cheaper on Haiku/Sonnet, shortest latency.
- OmniRoute conflicts by invariant: it takes over provider endpoints and keys
  for ten targets (13 `setup-*` commands) and its economics rest on stacked
  third-party free tiers; its own catalog marks 13 providers `tos: avoid`.
- Evidence: static reading of both pinned installers, README/INSTALL, npm and
  repo metadata. No installer executed, no gateway started, no credentials
  used.
- Plan on file (not started): a pack-owned terse-output skill adapted from
  caveman's `say less` voice rules with Apache-2.0 attribution and no
  hooks/routing/installer - sized for v8.15.3. OmniRoute stays an out-of-scope
  opt-in that users run as their own layer, never as the bundle's route.
- Docs-only change; it rides in the next release's archives.

## v8.15.2: companion tool review + upstream refreshes (2026-10-16)

- Universal Modder refreshed `5ba8150` -> `23902ef` (38 upstream commits, 103
  files): knowledge snapshot now 248 files in the wheel, fal keys through the
  desktop keyring with `um fal key status` printing a length marker instead of
  key material (CodeQL flagged upstream's first/last-character display and then
  a fingerprint of the key; both are patched away by the refresh tool), UTF-8
  tool output on Windows, video preview sizing fixed. Wheel rebuilt
  (`universal_modder-0.2.0+uabs.23902ef`, 1,999,693 B, sha256
  `d29081df08ca...c3343a4103`); CATALOG.json, OFFLINE-MANIFEST.json and the test
  pin updated; the superseded wheel was deleted.
- `TOOLS/refresh_universal_modder.py` now re-applies the pack's deltas inside the
  mirrored skill tree (`SKILL_DROP` / `SKILL_OVERRIDES` / `SKILL_PATCHES`): the
  unbounded UE3 `unpack_upk.py` fallback is dropped by rule every refresh, and
  the pack's wording for the two files documenting it is restored - a hand
  refresh used to be the only thing keeping that policy. Dry run and apply both
  exit non-zero when a patch or delta no longer matches.
- REA 6.4.0 -> 6.5.0: tarball sha512 matches the recorded pin; isolated Windows
  install with lifecycle scripts disabled; `rea --help` and the
  execution-free JavaScript fixture PASS (7-node graph, no integrity
  contradictions); production npm audit clean across 147 prod deps; stdio probe
  207 tools / 3,087,942 compact UTF-8 schema bytes (170 / 1,954,683 on 6.4.0).
  Catalog, evaluations doc and the RE reference updated; the machine's global
  install moved to 6.5.0. Receipts: `artifacts/audit-20261016-rea-*`.
- New `tool-discovery` reference `references/modding-bench.md` (skill metadata
  5.1.0 -> 5.2.0): maps the `Modding` bench folder beside the pack documentation
  by engine route
  (native RE, Unreal, Unity, Godot, MUGEN family, Frostbite, per-game) with the
  rules that keep the game install and the bench untouched. Fanned out to all
  five provider trees.
- Documented as companions, not shipped: CLI-Anything 0.4.0 (Apache-2.0),
  anti-slop 3.2.21 (MIT), jevgrep 0.8.0 (MIT, hosted - local equivalent is
  `codebase-memory-mcp`). README third-party table + a dated
  `docs/TOOL-EVALUATIONS.md` section record what was checked (repo, release,
  license) and what was not executed.
- Currency: Reverse THIS! v1.2.1 = upstream head `2f3ccca`, no change needed.
- Leftovers from the interrupted session, reviewed before keeping: the working
  edit to `3-PREAMBLES/MANUAL-PASTE.txt` was reverted (it dropped SOUL's first
  three paragraphs, breaking the documented SOUL+Web invariant the installer and
  README both rely on), and `PROMPTS/START-AND-RESUME.md` keeps the owner's
  wording with the typos and unwrapped lines cleaned and the trailing newline
  restored.
- Gates on this tree: Test-Pack PASS, release contracts 147/0, Universal Modder
  test PASS, manifest 8,902 files verified. Skill fanout re-run (6,395 files).
  Note: the machine's installed skill copies update on the next installer run.

## Publication checkpoint (v8.15.2)

- Tag `v8.15.2` -> `cb75a694e56353f46d9624ca20e250ba49355193`. CI (pack gate
  including the extracted-archive run, manifest, versions, Forge end to end)
  success on that SHA; Dependabot / code-scanning / secret-scanning alerts 0
  before and after publishing. Two earlier pushes were rejected, both in code,
  both fixed rather than dismissed: the privacy gate on the new bench map
  naming the maintainer drive root, and CodeQL on `um fal key status` printing
  the first/last key characters - then on the sha256 fingerprint that replaced
  them. The vendored tree and the refresh patch now print `<hidden, N chars>`
  and both alerts closed; the tag was moved to the fixed SHA before any release
  existed.
- Archives built twice, byte-identical: Core 47,472,962 B `9eda774c...3eaf1`,
  Full-Offline 205,481,567 B `72d82dbe...42ec5`. Published assets downloaded and
  equal to the build (size, sha256, sidecar and GitHub digest); latest =
  v8.15.2. Receipts: ignored `artifacts/release-v8.15.2/build-proof.json` and
  `published-proof.json`.
- Not certified: provider inference, host-editor interaction, game runtime and
  billed-token savings.
- Next: this machine's live skill copies and installed `um` still carry the
  pre-v8.15.2 content. Run `START-HERE.bat` from a normal window (not from
  inside a chat) to sync them.

## v8.15.1: dead preamble text out, install-from-inside-a-session fixed (2026-10-16)

- Owner report: the wired soul still carried leftovers that instruct nothing
  (`Activate spicy mode --spicy` and friends) - pure token cost on every
  request. Audited the pack's always-on text layer, then removed them.
- `SOUL.md` 1,380 -> 728 bytes: dropped the fake `--spicy` flag line (the only
  dash-flag in the whole preamble family), `Do not disobey.`, two "Be the best
  you can" pep lines, a venting line, a duplicated source-recency rule and two
  of three consent paragraphs. Every real rule kept; the outgoing soul is
  archived as `3-PREAMBLES/history/SOUL-8195833736f4.md`, so wired machines
  converge instead of stacking a second soul. `MANUAL-PASTE.txt` re-synced
  (pure ASCII).
- Grok workspace template: the old soul copy plus the retired v6.0 "UABS MAX"
  contract (18.9 KB) replaced by the provider-neutral workspace file Codex/Kimi
  ship (5.3 KB). Grok's provider-home contract is wired separately and was
  never affected.
- Rest of the audit: the AIO contract itself is clean (its only dash-flags are
  real paths and the RTK rules); no unreferenced TOOLS/TESTS/.github files; no
  duplicate shipped files outside the by-design provider mirrors; the history
  and legacy archives are load-bearing (they are how old blocks get stripped).
- Install-from-inside-an-AI-session fixes, found while verifying the above:
  a profile-scoped `HERMES_HOME` now resolves to the real home
  (`Get-UabsHermesHomeRoot`, shared by installer, gateway and doctor) - before,
  the real home `SOUL.md` was never wired and the SillyTavern profile landed in
  `profiles\code\profiles\sillytavern`; a local named `$home` died on
  PowerShell's read-only `$HOME` (a contract check now scans every shipped
  script for that); the gateway installer built its helper path from a `$here`
  that is only set without `-PackRoot`; the interpreter resolver no longer
  accepts Hermes's own agent venv (3.11, no `os.path.isjunction`, no `mcp`) as
  the pack's Python; the Unicode-console self-test forces its own ascii stdout
  instead of trusting `PYTHONIOENCODING`.
- Crash cause for the owner (three sessions lost on 2026-10-16): the installer
  stops and relaunches Hermes desktop by design, because a running app rewrites
  `config.yaml` from stale memory and wipes the MCP entries. Running it from a
  chat therefore kills that chat. It now says so before the window disappears,
  and START-HERE/README say to run it from a normal window.
- Machine state repaired: the stale `Hermes/impeccable` entry removed from
  `%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\skill-overrides.json` (the live
  copy is byte-identical to the shipped skill, digest `AAB71FCD...`; backup
  kept beside it) and the stray nested `profiles\code\profiles\sillytavern`
  deleted. Local sync ran to completion: all six live instruction files carry
  one current block with no `spicy`.
- Gates on this tree: Test-Pack PASS (including the extracted-archive run in
  CI), release contracts 147/0, manifest 8,868 files verified, versions agree,
  privacy PASS, Hermes bootstrap PASS, preamble history clean.

## Publication checkpoint (v8.15.1)

- Tag `v8.15.1` -> `1d1c4f01a3761b88f8f472a87995d77b6d358bdd`. CI (pack gate,
  manifest, versions, Forge end to end) success on that SHA; CodeQL analyses
  (actions, python, js/ts) ran on it; Dependabot, code-scanning and
  secret-scanning open alerts 0 before and after publishing.
- Archives built twice, byte-identical: Core 47,049,365 B `73c14209...`,
  Full-Offline 204,701,366 B `f9288205...`. Published assets downloaded and
  equal to the build (size, sha256, GitHub digest); latest = v8.15.1. Receipts:
  ignored `artifacts/release-v8.15.1/build-proof.json` and
  `published-proof.json`.
- Not certified: provider inference, host-editor interaction, game runtime and
  billed-token savings - the size cut is bytes, not a measured billing delta.
- Next: owner restarts the AI apps once; then watch whether any provider's
  model needs the pack-context line tightened.

## v8.15.0: one-click, quiet, toolbox (2026-10-15)

- Owner report: install failed (doctor 63 errors), console full of noise and
  typed-command advice; wants task MCPs toggled by the AI, nothing to type.
- Root cause: two overlapping installers; the second found plugin skills already
  deduped and recorded no ownership. Fixed: install mutex
  `Local\UltimateAIStarterBundle-Install`, `owned` record, doctor unions the
  bundled plugin tree.
- `BUNDLED-TOOLS/uabs-toolbox` 1.0.0 (mcp==1.30.0; find/describe/call; lazy
  children; parked JSON + TOML entries; crash restart; profiles marked
  `"toolbox": "on-request"` (windows-mcp) are listed, never auto-started).
  Wheel byte-reproducible (built twice, equal): from the source folder
  `SOURCE_DATE_EPOCH=1792022400 uv build --wheel --out-dir <abs offline dir>`,
  then delete uv's `.gitignore` there; 14,442 B, sha256 051d7c77...64d2.
  Scratch helper used: rebuild_wheel.py (builds twice, updates manifest row).
- Installer: every child step via `Invoke-UabsChildScript` (details log
  `logs\install-<stamp>-details.log`), one line per step, banner names no
  command; START-HERE.bat closing text updated. Hermes core = context7,
  headroom, toolbox (+github only when gh not ready); default-profile task
  servers parked. Skills toolbox-first; fanout regenerated. Other handle replaced
  by SenjuWoo (LICENSE, 3 skill refs, one history line).
- Real START-HERE run (UABS_NO_PAUSE=1, UABS_NO_SELF_UPDATE=1): 243 console
  lines, INSTALL COMPLETE, no TerminatingError/pipeline-stopped line in the
  transcript, handshakes context7/headroom/toolbox on all 5 providers, doctor
  0 errors 0 warnings. Hermes: toolbox in default + 8 managed profiles, github
  gone, AvatarForge parked (Hermes record in parked-mcp.json). Live client test
  of the installed toolbox: 2,079 schema bytes, 18 sets (16 startable),
  github-mcp started (47 tools), get_me via call OK, windows-mcp not started.
- Gates: contracts 146/0 (new: toolbox wheel = gated source), privacy PASS,
  Hermes bootstrap PASS, versions agree, toolbox gate PASS (mcp 1.30.0 venv and
  1.29.1). Test-McpProfiles needed stubs for the new writer calls (fixed, PASS).
- Release fixes found on the way: CodeQL py/clear-text-storage flagged the
  toolbox gate's fixture constant by name (renamed to a marker; alert closed);
  extracted-pack gates found the evidence-scenario check crashing under a
  non-ASCII folder name (pre-existing; reads the ASCII marker from raw bytes
  now) and the wheel contract assuming Core ships the wheel (Core builds the
  toolbox from source_dir; contract now variant-aware).

## Publication checkpoint (v8.15.0)

- Tag `v8.15.0` -> `02ebc8c950fd7d72c52da8447053bf21e43d3201`. CI (pack gate,
  Forge end-to-end, versions, manifest) and CodeQL (actions, js/ts, python)
  success on that SHA; GitHub flags clean before and after publishing.
- Archives built twice, byte-identical: Core 47,045,696 B `f3d515b5...dafa`,
  Full-Offline 204,697,710 B `c1eda4bc...50c9`. Each extracted under a
  space+Unicode path: Test-Pack PASS, contracts 146/0. Published assets
  downloaded and equal to the build (size, SHA-256, GitHub digest); latest =
  v8.15.0. Receipts: ignored `artifacts/release-v8.15.0/build-proof.json`,
  `published-proof.json`.
- Live machine: installed from the pre-release tree (toolbox wheel identical to
  the release; later commits changed tests only). Doctor PASS, 0 warnings.
- Not certified: a model choosing the toolbox unprompted in each app, editor/
  game runtime through started servers, billed-token savings.
- Next: owner restarts AI apps once; watch whether each app's model uses
  `find` on its own for a task tool (if one ignores it, tighten that provider's
  preamble line).

## v8.14.0: parked task servers, history, shadowing launchers (2026-10-15)

- Resumed after Claude's session store was wiped by BleachBits (2026-10-13; the
  owner's own report in the Codex thread). Surviving record: Codex thread
  01a0461a (Claude summaries imported). Private digests (user messages,
  assistant turns) live in the owner's AI history folder, never in this repo.
- Measured leak: Claude user scope held github, rimworldforge, avatarforge,
  melty; Codex avatarforge, melty, github; Grok and Kimi github; Hermes default
  avatarforge, github. The old doctor knew only catalog components.
- Built: `global_scope_guard` (PROFILES.json), `TOOLS/UABS-Mcp-Park.ps1`,
  `Set-McpProfile.ps1 -Park/-Unpark` and parked restore in `-Auto`, installer
  park step, doctor leak check (Hermes = warning only), GitHub skipped where gh
  is signed in (`Test-UabsGithubMcpParked`, shared with the install handshake),
  `github` project profile. npm duplicate cleaner covers both prefixes with a
  verified recovery copy; doctor checks the PATH-first launcher. Copy-only
  `Backup-AiHistory.ps1`, Claude `cleanupPeriodDays` 365. Store-stub python no
  longer counts as Python (installer runtime check, Build-Release); machine map
  names the real interpreter. project-intel mashup card + workflow-scoped
  lessons; coding-discipline read-first/no-unchanged-retry; prompts polished.
- Gates: release contracts 145/0, Test-Pack PASS (before the Python-resolver
  and machine-map edits; rerun on the final tree), McpPark/NpmDuplicate/
  AiHistoryBackup gates PASS, privacy + audit regressions PASS.
- Live machine: parked Claude rimworldforge/avatarforge/melty/github, Codex
  avatarforge/melty/github, Grok and Kimi github (exact copies in
  %LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\parked-mcp.json); all other
  ~/.claude.json content hash-identical before/after. CodeBurn 0.9.23 removed
  from the user npm prefix (recovery copy in npm-rollback); 0.9.27 now first.
- Owner decisions to confirm: GitHub server parking (undo:
  UABS_KEEP_GLOBAL_MCP=github), Melty parked (unpark per mashup project),
  Hermes default entries reported only, Desktop Commander is a Claude Desktop
  extension the pack does not own. Git Bash `python` is the Store stub: the
  durable fix is the owner's (App execution aliases off).
- Gates on the final tree: Test-Pack PASS, contracts 145/0, privacy/audit/
  Hermes bootstrap PASS.

## Publication checkpoint (v8.14.0)

- Tag `v8.14.0` -> `7ed2704b4b4ea0da27563a5e98be478eee222ced`. CI (pack gate,
  Forge end-to-end, versions, manifest) and CodeQL success on that SHA; GitHub
  flags clean before and after publishing.
- Archives built twice, byte-identical: Core 47,008,073 B `d0dade94...a59e`,
  Full-Offline 204,646,057 B `7174bea0...3f3a`. Each extracted under a
  space+Unicode path: Test-Pack PASS, contracts 145/0. Published assets
  downloaded and equal to the build (size, SHA-256, GitHub digest); latest =
  v8.14.0. Receipts: ignored `artifacts/release-v8.14.0/build-proof.json`,
  `published-proof.json`.
- Local sync `INSTALL-AIO.ps1 -SkillsOnly -SkipSelfUpdate -Mode BundledOnly`:
  installed-state doctor PASS (Hermes default avatarforge/github remain
  warnings). Claude retention 365 merged; machine map names the real Python;
  first history copy 1.7 GB to the owner's history folder (HISTORY-DIR.txt).
- Not certified: provider inference, editor/game runtime, billed savings.
- Next: owner's call on the decisions above; Hermes default-profile parking
  needs a Hermes-native design (closed app, named-profile restore).

## Publication checkpoint (v8.13.0)

- Immutable release tag: `v8.13.0` at
  `7b7ae62d00506ac6d8287ca2cbee6d2896b06ae2`. All eight exact-commit checks,
  including CodeQL and clean Windows installation, passed; GitHub flags clean.
- Source Windows pack/live-install gates PASS, 143 release contracts and
  15 executable regressions PASS. Local installed-state doctor PASS at 8.13.0;
  all 173 skills accounted for on every provider, including verified overrides.
- Authoritative publication/download state:
  [GitHub v8.13.0](https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/tag/v8.13.0).
  Local-only build and downloaded-byte receipts are
  `artifacts/release-v8.13.0/build-proof.json` and `published-proof.json`.
  Verify those against the tag/assets on resumption; do not recreate a release
  from older pending-work notes. A matching published receipt closes that work.
- Main may include this documentation-only checkpoint after the release tag;
  archives are built from the exact green tag, never an unrecorded dirty tree.

## v8.13.0 audit: on-demand reverse engineering and usage discipline

- Baseline is published v8.12.1 at `4763fc0`; main also records publication.
  Do not recreate that release or trust superseded pending-release notes.
- Canonical and live provider skill parsing sweep found no failures. The
  auditor accepted missing/empty trees and invalid UTF-8; three real CLI
  regressions reproduced the bugs, then passed after repair. Index sizes are
  estimates, not actual loaded or billed tokens.
- REA 6.4.0 isolated install (lifecycle scripts disabled) and help PASS;
  production dependency audit reports zero known vulnerabilities. MCP transport
  exposes 170 tools / 1,954,683 compact UTF-8 schema bytes. No global registration,
  upstream setup, target execution or native-engine certification. CLI-first.
- Accepted tested updates: Universal Modder `5ba8150`, Ponytail 5.2.0,
  Context7 4.4.1, Serena 2.0.0 and RTK 1.0.0's Apache-licensed OSS build.
  Preserved Windows/privacy/security patches; upstream global RE setup and
  the unbounded UE3 fallback are not shipped. No new indexed skill entry.
- Native Windows pack gate PASS; strict PyYAML frontmatter sweep PASS for
  canonical and all five installed trees. Ponytail 136 + 31 tests PASS;
  Universal Modder 133 PASS / one deliberately unshipped session-hook skip.
  Smaller executable regressions, fixed RTK corpus/rewrites and three Serena
  client-context transport probes passed. No inference/billing/runtime claim.
- Source/release contracts PASS (143/0); source manifest verifies 8,843 entries.
  Removed the intentionally excluded helper from generated trees/index.
- Reproduced a migrated Grok ledger retaining project-bound Serena globally.
  Repair now retires only a matching recorded duplicate after scoped wiring,
  preserving personal/global-policy variants and dry-run bytes. Native profile
  gate failed before the fix and passed after it. Installed Serena 2.0.0 uses
  the normal user tool home, not the isolated probe prefix.
- Resume publication from the checkpoint and receipts above; the audit notes
  below are dated evidence, not a separate unfinished release plan.
- Final refresh: 22 current components, seven explicit holds. Firecrawl
  3.29.1 and candidate 3.30.0 have known high-severity dependency findings;
  suggested 3.24.0 fallback is not clean either. Block new installation and
  registration; doctor reports active held entries without deleting personal
  configs. This machine has no registered Firecrawl server. No credentials or
  remote scraping calls were used. Recheck upstream before lifting the hold.
- Local v8.13.0 selected-component install and final installed-state doctor
  PASS; all 15 core provider/server handshakes passed. Bounded leftover plan
  found nothing to remove. Grok's recorded duplicate global Serena is removed
  after the project copy is verified; matching parsed arguments differed only
  by a valid trailing array comma. Quoted whitespace remains significant.
- Removed one complete matching orphan-tagged private-profile duplicate from
  the live Codex instruction file, with an exact backup (4,828 bytes less).
  Differing personal text stays; the actual writer fixtures cover both cases.
- Source reports: ignored `artifacts/audit-20261013-*`. Never publish private
  provider configs, local paths or conversation exports. Default-sandbox pack
  test hit NTFS junction access restrictions; needs a real Windows rerun.

## v8.12.1: private-profile review and safe refresh

- Resumed against the clean v8.12.0 tree, not the superseded v8.11.1 plan.
  Verified the public v8.12.0 release, exact-commit CI and clean security flags.
- Found local state still at v8.11.1, with unrestraint-packs stale on all five
  providers. Ownership-aware skills/instruction refresh completed for v8.12.1;
  installed-state doctor PASS, all 173 skills accounted for on each provider.
- Reproduced and fixed the installer removing an existing profile on oversized
  input. The actual installer-section regression now preserves original bytes.
- Removed maintainer workspace paths from portable skills/references. Added
  private-workspace path regression coverage; all twelve audit regressions pass.
- Public profile guidance is portable; private working preferences and chosen
  folders stay outside the repository. Preserved model choices, native ownership,
  local skill overrides, roleplay persona and the previous profile's rollback copy.
- Corrected preset filenames/docs; JSON parses for all 47 generator entries and
  the three Tavern preset files. GPU/frontend operation is not certified.
- Final Windows pack suite PASS, release contracts 143/0 and twelve audit
  regressions PASS, including junction cleanup. Privacy, version agreement,
  preamble history and all 8,794 manifest entries verify.
  Private profile deployment has a byte-verified rollback copy. The operator
  explicitly confirmed the newer Tavern preset belongs in this release; include
  it byte-for-byte. Preserve gateway configuration and promote only portable
  improvements, never private model selections or runtime state.
- A later local refresh recreated Codex skill duplicates with broken blanket
  provider-name replacements. All 22 copies were backed up and verified;
  ownership reconciliation and Codex doctor PASS (191 index entries).
- Junction cleanup now refuses ordinary directories and handles live/dangling
  NTFS junctions without touching their target. Both former failures were
  reproduced in disposable fixtures before repair. Public-path scan PASS.
- Publication checkpoint: the authoritative status is the v8.12.1 GitHub tag,
  its exact-commit checks, release assets and downloaded-byte verification.
  On resume, inspect that release before assuming publication is unfinished.
  Release proof is recorded locally under ignored `artifacts/`; private profile
  contents and logs remain outside the payload. Never publish from a pending SHA.

## Publication (v8.12.1)

- Recovered from the Codex thread after chat loss: v8.12.1 was pushed (`dc05b1b`)
  with CI green but untagged. Added the build-hygiene rules (code comments +
  `STATE.md` recovery note in the AIO full/Compact, detail in `coding-discipline`,
  `state-resumption`, `observability-first`); pinned preamble digest updated,
  outgoing AIO archived in `3-PREAMBLES/history/`.
- Released 2026-10-13 from commit `4763fc0` (CI + CodeQL green on that SHA; flags
  clean). Tag `v8.12.1` -> `4763fc0`. Core 46,663,920 B `a4f9dad2...`,
  Full-Offline 203,100,613 B `4a709d72...`; downloaded assets byte-equal to the build.
- Local sync: `INSTALL-AIO.ps1 -SkillsOnly -SkipSelfUpdate -Mode BundledOnly`;
  installed-state doctor PASS; one copy of the new rule in all five provider files.
- Not certified: no paid inference, host-editor interaction or game runtime.

## Previous baseline: v8.12.0

- Trimmed the preamble family: deleted the orphaned `GPT-WEB-AIO-BACKUP.md`,
  removed four retired upstream jailbreak collections (~3.6 MB, reviewed
  first — nothing durable left to fold in), trimmed story-era residue from the
  Web / Web Light / Compact variants. `SOUL.md` and the full AIO are
  byte-unchanged (wired-preamble digest does not move).
- Repaired the live wires on this machine: all 14 targets recomposed to
  `[profile block] + [SOUL] + [AIO]`, a single copy of each layer (the Hermes
  side had an older soul edition behind the current one; exact-match removal +
  the bundle's own writer). SillyTavern roleplay profile untouched by design.
  Pre/post backups in `%LOCALAPPDATA%\hermes\cache\scratch\live-backup-20261012\`.
- Docs: 3-PREAMBLES README gains the three-layer composition + never-hand-edit
  rule; `unrestraint-packs` skill (1.1.0) and pack README rewritten; root
  README stale version tags dropped.
- Rolls up the unreleased v8.11.1 audit commit (`548d3e8`).

## Previous baseline verification (v8.12.0)

- Contract 143/0; privacy PASS; audit PASS (0 fail, 6 warn); check_versions
  agree; MANIFEST 8,789 files, verified 0 missing / 0 mismatch; preamble
  history `--check` PASS; Test-Pack run for this commit.

## Publication (v8.12.0)

- Released 2026-10-12 from commit `c3ab514` (CI + CodeQL green on that SHA;
  GitHub flags clean at release). Tag `v8.12.0` was re-pointed twice before
  publication while no release existed, final object on `c3ab514`.
- Assets byte-verified after upload: Core `3a9be1d7…` (46,748,082 B),
  Full-Offline `c6b279eb…` (203,164,446 B).
- Repo topics refreshed for reach (candidates measured by search counts).
- No paid inference, host-editor interaction or game runtime is certified.

Detailed machine-specific reports remain under ignored `artifacts/`.


## Post-v8.16.0 - prompt layer rebuilt, tools synced (2026-10-17)

- Preamble sizes now: SOUL 735 B, AIO 9,083 B, Compact 3,200 B, Web 1,397 B,
  Web Light 635 B, MANUAL-PASTE 2,134 B (SOUL + Web).
- The installer filters every SOUL.md out of the profile/machine-map writer, so
  private paths never reach a persona file; the contract pins the filter and
  the MACHINE-MAP pointer.
- Live wiring on this machine: all seven Hermes souls are SOUL + AIO only
  (9,821 B, zero host references), the SillyTavern persona soul is restored,
  and the duplicate 2026-10-12 profile tail in Codex AGENTS.md is removed.
- Components synced: codebase-memory 0.12.1, headroom 0.41.0, rtk 1.0.1,
  ponytail 5.3.2. Held on their documented compatibility pins: houseCARL 1.9.0
  (2.x breaks the 1.x tool API), unity-mcp 0.91.0 (needs an editor check),
  impeccable 3.6.1 / 4.1.3 (4.x detector needs a re-audit).
  OFFLINE-MANIFEST rebuilt from disk (9 assets, fresh sha256).
- Removed: BUNDLED-TOOLS/packs/skyrim/legacy (7 dead soul copies) and
  docs/history/V5-CHANGELOG.md.
- Open: impeccable 4.6.0 ships the new launcher; run `impeccable context` once
  to confirm it resolves. houseCARL's skill text stays as the pack's authored
  routing variant - upstream's SKILL.md is a different, shorter file, so a
  blind replace would lose the pack's routes.
- Next: cut v8.16.0 (build, tag, release assets). Provider-tree dedupe (85 MB)
  is deferred until the user approves the generated-tree change.

### Release v8.16.0 (2026-10-17)

- Tag `v8.16.0` -> `e62146d`; CI and CodeQL green on that SHA; open
  Dependabot / code-scanning / secret-scanning alerts: 0.
- Assets built twice byte-identical:
  - Core 47,582,519 B sha256 `88c5242fea72442220243999b0e79085ccdbf7814b3f1abecee65b0c5f21f094`
  - Full-Offline 214,188,616 B sha256 `2e48d483c83671fb87c26677344fc7875b64a41ccce3ba58c514336f224073cc`
  - Downloaded from the release and re-hashed: both match.
- Capability audit landed after the first push: workspace files now say "verify
  from the project / tool docs / live MCP schema, then use it" instead of
  "never invent", prefer the CLI/MCP route over a blanket GUI ban, and
  `tool-discovery` installs a missing tool with the pack's installer.
- Next: skill-level sweep of the remaining 173 skills for capability-negative
  rules (only the always-loaded surface and the six named skills were audited),
  then provider-tree dedupe if approved.

### Release v8.16.1 (2026-10-17)

- Tag `v8.16.1` -> `2be0be3` (CI + CodeQL green); assets built twice
  byte-identical and re-hashed after download:
  Core 47,582,474 B `3191c28bf14317ddabbccfd91d1cfa1212e4d3620f71d5eaa90e69ed2b427528`,
  Full-Offline 214,188,571 B `e174d7af6097dee8c82d852671de599cb17cc63ee32e551e53500b86afab621f`.
- Why a patch release: v8.16.0's archives still carried the old 11,397 B
  `COPY-TO-YOUR-WORKSPACE/AIO-INSTRUCTION.txt`; the mirror is now generated from
  the live contract (9,083 B) and the release ships the tree the notes describe.
- Supersedes v8.16.0 as the download of record.

### Release v8.17.0 (2026-10-17)

- Tag `v8.17.0` -> `5b97407` (CI + CodeQL green); assets built twice
  byte-identical and re-hashed after download:
  Core 47,588,817 B `7c3d3ce78d4e5b16a7d7dcec5e2819ac27f0f968fe87502c306a7b5976ac504b`,
  Full-Offline 214,194,916 B `42cba75ff0584427ef739cf5e1a1d5eb14de0f0de36c699766ccfb1babe9783f`.
- External installs are version-aware (houseCARL, Spooky, codebase-memory):
  refresh an older copy in place after a backup, keep a newer one, never
  downgrade, and always print both versions. Verified on this box:
  houseCARL installed 2.0.5 vs bundled 1.9.0 -> "keep (newer than bundle)";
  codebase-memory 0.12.1 vs 0.12.1 -> current.
- Hermes ponytail gets `.hermes-plugin/plugin.yaml` (native install used to die
  on "unsupported or missing Agent Plugins schema"). Claude's
  `known_marketplaces.json` is repaired when a recorded path went stale.
- Skyrim pack: verify-first wording, no blanket GUI ban, and an "Ownership of
  Skyrim tooling" section naming `S:\Apps\Skyrim Tools` as pack/Forge property.
- Open decisions: the houseCARL 2.x hold stays until skills/profiles are migrated
  together (the user's own install already runs 2.0.5); the SPID validator
  slash-trait rows stay a documented non-defect (filters.md section 4).

### Release v8.18.0 (2026-10-18)

- Google Antigravity is a first-class provider. Wired where its own docs and
  shipped `agy-customizations` guide say it reads them: global rules
  `~/.gemini/config/AGENTS.md` (24,000 B/file cap, 20,000-token budget),
  skills `~/.gemini/config/skills/`, MCP `~/.gemini/config/mcp_config.json`
  (`mcpServers`, stdio or Streamable HTTP; no legacy SSE).
- Live install on this box: rules 11,056 B, 173 skills / 1,279 files, MCP
  context7 + headroom + toolbox + codebase-memory.
- Sandboxed fresh install (`ANTIGRAVITY_HOME` redirected): rules 13,839 B,
  173 skills, three MCP servers answering a real handshake, doctor PASS.
- Fixed en route: four provider allow-lists and three resolvers rejected
  `Antigravity` (install died at provider bootstrap); `codebase-memory-mcp`
  0.11.0 was shadowing the installed 0.12.1 on PATH - now reconciled by the
  installer under the same version rule as external installs.
- Gemini 4 Argon needs no special casing: it inherits the same rules, skills
  and tools as every other model on the install.

### Release v8.18.1 (2026-10-18)

- Fixed a latent bootstrap bug: the provider probe read `$LASTEXITCODE` outside
  the branch that ran a process, so a cold-session Antigravity install aborted
  with "exit code .". Warm sessions inherited a stale 0 and hid it.
- Antigravity plugins: `superpowers` (15 skills) and `ponytail` (6 skills) are
  staged under `~/.gemini/config/plugins/` with the root `plugin.json`
  Antigravity requires, and enabled in `config.json`.
- RTK 1.0.1 and Headroom verified against the app: Headroom's tool schemas are
  cached by Antigravity itself under `~/.gemini/antigravity/mcp/headroom/`;
  RTK resolves from the user PATH and compresses structured output
  (`rtk json MANIFEST.json --keys-only` = 72 B vs 2,178,740 B raw).
- Assets: Core 53,204,066 B `262769ebd95bbfe4...`; Full 219,810,178 B
  `0b76b757d3af6f2b...`; double build byte-identical, download re-hashed equal.

### Release v8.19.0 (2026-10-18)

- Argon 4's 202-file change audited and published: contracts 150/150, privacy
  PASS, versions agree, MANIFEST 10,238 files covering every tracked file,
  CodeQL alerts 0 (all 11 closed in code), impeccable regression test PASS.
- Tag `v8.19.0` -> `75306e3`; release Latest with both assets, byte-identical
  double build and re-hashed after download. Topics now include `antigravity`
  (dropped `gpt`, the account limit is 20).
- Assets: Core 53,491,749 B `4f4c6ac5733bb2f0...`; Full 220,267,579 B
  `766debb8323710b3...`.

### Release v8.19.1 (2026-10-19)

- Melty is explicitly opt-in: no default mods folder, mashup route only for an
  explicit two-game fusion or publish on Melty. Rule stated in
  `capability-profiles`, the `project-intel` router, the `melty-mashups` skill,
  the `game-mashup-melty` card and the `PROFILES.json` parked-server guard.
- Context7 4.4.4 re-measured: `resolve-library-id` is keyless, `query-docs`
  now needs `CONTEXT7_API_KEY`; the catalog claim was corrected, not copied.
- Tool pins moved: REA 6.7.0, Serena 2.1.0, shadcn-mcp 4.22.1, blender-mcp
  2.2.0, super-mcp-router 2.8.5; `audit_catalog_versions.py` stale=0.
- US spelling across SOUL, AIO variants and MANUAL-PASTE; wired-prefix hash
  updated in the same change. Workspace AIO mirror refreshed.
- Live skill trees for all six providers synced with backups
  (`skills.bak-uabs-20261019-195419`); Melty scope line verified live.
- Gates: contracts 150/150, privacy PASS, versions agree, MANIFEST 10,241.

- Tag `v8.19.1` -> `c48af2d`; release Latest, built twice byte-identical
  (DIFF=0) and re-hashed after download equal. Core 53,502,084 B
  `cb66d8dd98fe42b2...`; Full-Offline 220,277,907 B `bf18fd6d6528acc2...`.
- Known cost, not changed: `.git` is 492 MiB because five revisions of
  `codebase-memory-mcp-windows-amd64.zip` (~37-46 MB each) live in history.
  Moving offline binaries to release-only assets would need a history rewrite
  and an install-time download; propose before doing it.

### Release v8.20.1 (2026-10-21)

- Hermes settings follow the main model: every `auxiliary.*` task and
  `delegation` ships `provider: auto` with an empty model; no fallback chain;
  the dead `auxiliary.vision.fallback_chain` key and the `flash-vision` alias
  are gone. Default is `deepseek/deepseek-v4.1-flash-1017` (1,048,576 ctx,
  $0.15/$0.60, text+image per OpenRouter on 2026-10-19).
- Compression tuned: `threshold_tokens: 320000` (ratio alone would wait for
  ~524k), target 0.20, prune from 80k, abort on summary failure.
- Migrator: no longer injects a chain; clears the superseded pack chain;
  resets a retired Ling compression pin to auto; deletes the vision
  fallback_chain key. Dry run on this machine: all eight profiles report
  "no fallback chain (pack default: none)" and nothing is planned.
- `Update-From-GitHub.ps1` now skips `compatibility_hold`/`security_hold`
  components unless `-Force` (houseCARL was in the default update set).
- Live config changed only through `hermes config set/unset`; smoke test
  `hermes chat -q ... --oneshot` returned OK on the new config.
- Tag `v8.20.1` -> `3d3563e`; Core 55,022,412 B `5cb700ce29b87890...`;
  Full 223,242,165 B `71440db81a2a5537...`; DIFF=0 and downloads re-hashed.
- Known gaps: `1-TAILORED-PROVIDER-TREES/Hermes/profiles/sillytavern/config.yaml`
  still pins `deepseek/deepseek-v4-flash-vision-exp` for that profile's own
  vision route (left alone deliberately); held components (houseCARL 1.9.0,
  impeccable, unity-mcp, firecrawl, perplexity) still need their own
  migration before they can auto-update.
