# Integration report — owners, releases, and what is actually installed

Date: 2026-11-06. Author: bundle integration pass. Every number below came from this machine or from
the GitHub API during this session; nothing here is inferred from a README.

## 1. COMPANION-INVENTORY

Detected with `python TOOLS/companion_registry.py --verify`.

| Companion | Repo HEAD | Latest release | Assets | Install kind | State on this PC |
|---|---|---|---|---|---|
| Ultimate AI Starter Bundle | `cc6f1c1` | `v8.37.0` | 9 | — (foundation) | source |
| SkyrimForge | `7afa175` | `v6.11.4` | zip | release_zip | **INSTALLED** `%LOCALAPPDATA%\Skyrim-Tools\Skyrim-Forge` |
| Reverse THIS! | `fd26a39` | `v1.14.6` | zip | release_zip | **DISCOVERED** `%LOCALAPPDATA%\ReverseThis` (state only, app dir absent) |
| RobloxForge | `03b2741` | `v0.13.5` | zip | release_zip | **INSTALLED** `Z:\…\Tools\Ai tools\RobloxForge` |
| Risk of Rain 2 Forge | `399d1d8` | `v1.13.8` | zip | release_zip | **INSTALLED** `Z:\…\Tools\Ai tools\Risk-Of-Rain-2-Forge` |
| Minecraft Forge | `ad68171` | none | — | source_only | **INSTALLED** (source workbench, no release exists) |
| RimWorldForge | `5f5893a` | `v0.4.0` | zip | release_zip | **INSTALLED** `%LOCALAPPDATA%\RimWorldForge` |
| SaintsRowForge | `59777d8` | `packs-v1` (!) | zip | owner_installer | **NOT_FOUND** |
| AvatarForge | `f1e51e2` | `v0.2.8` | zip | release_zip | **NOT_FOUND** |
| FaceForge | `8e8b510` | `v0.24.3` | zip | gui_app | **NOT_FOUND** |
| FollowerForge | `8509f54` | `v3.7.4` | zip | gui_app | **NOT_FOUND** |
| comfy-kit | `f9c5314` | `v0.5.0` | **0** | source_only | **NOT_FOUND** |

`DISCOVERED` is never healthy: the folder exists, a marker does not.

## 2. INTEGRATION-STATUS

| Signal | Result |
|---|---|
| Registry validates (owner allowlist, install kinds, asset rules) | pass, 11 companions |
| Detection matches the machine's real layout | yes — the game folder (`Skyrim Special Edition`) and a Skyrim forge *backup* are both correctly ignored |
| Registry can execute a command | **no** — the module contains no `subprocess`/`os.system`; a test enforces it |
| Owner doctors invoked by the bundle | never; `--print-doctor <id>` prints the owner's own command |
| UABS-only operation | unaffected — the registry is read-only and additive |

## 3. TEST-EVIDENCE

| Command | Result |
|---|---|
| `python TESTS/test_companion_registry.py` | **0 failed** (8 cases) |
| `python TOOLS/companion_registry.py --verify` | `INSTALLED=5, DISCOVERED=1, NOT_FOUND=5` |
| `python TOOLS/generate_manifest.py` | 5,621 files, 162.2 MB (regenerated, then reverted — see issue 6) |
| RobloxForge `python tests/run_tests.py` | 88 passed, 0 failed (`03b2741`) |
| RobloxForge CI + CodeQL | **success** on `03b2741` |

Not run, and not claimed: any GUI application launch (AvatarForge, FaceForge, FollowerForge),
comfy-kit installation, multiplayer or published-place behaviour, and the DEADZONE: HAVEN project push.

## 4. RELEASE-MATRIX

| Owner | Source SHA | Release | CI | Installed version |
|---|---|---|---|---|
| UABS | `cc6f1c1` (+ pending 8.37.1 work in the tree) | `v8.37.0` | green | source |
| RobloxForge | `03b2741` | `v0.13.5` published, source says **0.13.6** | green | 0.13.6 source → release gap, issue 5 |
| SkyrimForge | `7afa175` | `v6.11.4` published | green per owner | installed copy predates `7afa175` |
| Reverse THIS! | `fd26a39` | `v1.14.6` | — | app not installed |
| RoR2 Forge | `399d1d8` | `v1.13.8` | — | source checkout |
| SaintsRowForge | `59777d8` | `packs-v1` is "latest" | — | not installed |
| comfy-kit | `f9c5314` | `v0.5.0`, no assets | — | not installed |

## 5. FINAL-ISSUES

1. **SaintsRowForge (P1, owner repo).** `/releases/latest` resolves to the `packs-v1` game-content
   pack, not the application. Its installer mirrors with `robocopy /MIR` and has no staging or
   rollback, and a failing doctor still prints completion. Not fixable from the bundle without
   becoming a second installer. Next step: owner publishes an application-tagged release, stages
   `Install.ps1`/`Update.ps1` with backup+rollback, and makes a failed doctor exit non-zero.
   The registry records `asset: "application release only - never packs-v1"` so no automation can
   mistake the content pack for the Forge.
2. **comfy-kit (P2).** `v0.5.0` has zero uploaded assets; only a tagged source checkout works today.
   Its documented Anima setup also needs several GB of models, so it stays a deliberate opt-in.
3. **GUI apps (P2).** AvatarForge, FaceForge and FollowerForge are not installed here. The
   FaceForge → RaceMenu head export → FollowerForge handoff is unverified end to end.
4. **Reverse THIS! (P2).** `%LOCALAPPDATA%\ReverseThis` holds `kit.json` plus four stale backups
   (`pre-1.14.4`, `pre-1.14.5`, `pre-1.14.6`, `stale-20261105`) but no application directory, so the
   state survives an uninstall. Reinstall through the owner installer before relying on it.
5. **RobloxForge release gap (P2).** `main` is at 0.13.6 with the adopted Roblox skill catalog and
   the 23 assistant briefs, but the newest published release is `v0.13.5`. The skills this owner now
   owns are not in the released artifact. Fix: tag and publish 0.13.6 from `03b2741`.
6. **UABS tree is mid-flight (P2).** `CHANGELOG.md`, `README.md` and 46 other paths carry another
   agent's unpublished 8.37.1 work. This pass committed only its own four paths and reverted the
   regenerated `MANIFEST.json` so it cannot describe files that are not committed. Regenerate the
   manifest once that work lands.

## 6. Registry contract

`BUNDLED-TOOLS/COMPANIONS.json` is the single list of supported owners. It deliberately contains
**no** install logic and **no** command runner: the bundle detects, reports and prints owner
entrypoints. Rules enforced by `validate()` and proven by tests:

- only `github.com/SenjuWoo/` repositories are trusted;
- `source_only` may not advertise a downloadable asset; `release_zip` must name one;
- a directory counts only when its name matches the owner's repository name, so a backup or an
  unrelated tool holding the same marker file cannot be reported as that companion;
- unknown install kinds and empty marker lists are rejected.
