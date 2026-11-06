# Integration report — owners, releases, and what is actually installed

> Historical snapshot from 2026-11-06. Versions and SHAs here are frozen at
> that moment; the current truth is the release tags and `VERSION.txt`.

Date: 2026-11-06. Author: bundle integration pass. Every number below came from this machine or from
the GitHub API during this session; nothing here is inferred from a README.

## 1. COMPANION-INVENTORY

Detected with `python TOOLS/companion_registry.py --verify`.

| Companion | Repo HEAD | Latest release | Assets | Install kind | State on this PC |
|---|---|---|---|---|---|
| Ultimate AI Starter Bundle | `cc6f1c1` | `v8.37.0` | 9 | — (foundation) | source |
| SkyrimForge | `7afa175` | `v6.11.4` | zip | release_zip | **INSTALLED** `%LOCALAPPDATA%\Skyrim-Tools\Skyrim-Forge` |
| Reverse THIS! | `fd26a39` | `v1.14.6` | zip | release_zip | **INSTALLED** `Tools\Github\reverse-this` (state dir also present) |
| RobloxForge | `03b2741` | `v0.13.6` | zip | release_zip | **INSTALLED** `Tools\Ai tools\RobloxForge` (0.13.6, checksum verified) |
| Risk of Rain 2 Forge | `399d1d8` | `v1.13.8` | zip | release_zip | **INSTALLED** `Z:\…\Tools\Ai tools\Risk-Of-Rain-2-Forge` |
| Minecraft Forge | `ad68171` | none | — | source_only | **INSTALLED** (source workbench, no release exists) |
| RimWorldForge | `5f5893a` | `v0.4.0` | zip | release_zip | **INSTALLED** `%LOCALAPPDATA%\RimWorldForge` |
| SaintsRowForge | `68a361b` | `v0.2.3` | zip + sha256 | owner_installer | **NOT_FOUND** (release now correct; not installed here) |
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
| `python TOOLS/companion_registry.py --verify` | `INSTALLED=6, NOT_FOUND=5` |
| `python TOOLS/generate_manifest.py` | 5,621 files, 162.2 MB (regenerated, then reverted — see issue 6) |
| RobloxForge `python tests/run_tests.py` | 88 passed, 0 failed (`03b2741`) |
| RobloxForge CI + CodeQL | **success** on `03b2741` |

Not run, and not claimed: any GUI application launch (AvatarForge, FaceForge, FollowerForge),
comfy-kit installation, multiplayer or published-place behaviour, and the DEADZONE: HAVEN project push.

## 4. RELEASE-MATRIX

| Owner | Source SHA | Release | CI | Installed version |
|---|---|---|---|---|
| UABS | `e19752e` | `v8.37.1` (this pass) | see run | source |
| RobloxForge | `03b2741` | **`v0.13.6`**, zip + sha256 verified | green | 0.13.6 |
| SaintsRowForge | `68a361b` | **`v0.2.3`**, zip + sha256 verified; `packs-v1` now prerelease | green | not installed here |
| SkyrimForge | `7afa175` | `v6.11.4` | owner CI | installed copy predates `7afa175` |
| Reverse THIS! | `fd26a39` | `v1.14.6` | — | installed at `Tools\Github\reverse-this` |
| RoR2 Forge | `399d1d8` | `v1.13.8` | — | source checkout |
| Minecraft Forge | `ad68171` | none (source-only) | — | source workbench |
| RimWorldForge | `5f5893a` | `v0.4.0` | — | `%LOCALAPPDATA%\RimWorldForge` |
| comfy-kit | `f9c5314` | `v0.5.0`, no assets | — | not installed |

## 5. FINAL-ISSUES

1. **comfy-kit (P2).** `v0.5.0` has no uploaded assets, so only the tagged source checkout works. Its
   Anima setup also needs several GB of models, so it stays a deliberate opt-in.
2. **GUI apps (P2).** AvatarForge, FaceForge and FollowerForge are not installed here. The
   FaceForge → RaceMenu head export → FollowerForge handoff is unverified end to end.
3. **SkyrimForge installed copy (P2).** The release is `v6.11.4`; the installed tree at
   `%LOCALAPPDATA%\Skyrim-Tools\Skyrim-Forge` predates `7afa175`. Re-run the owner updater before
   relying on the newest source.
4. **Reverse THIS! state (P3).** `%LOCALAPPDATA%\ReverseThis` still carries four stale backups
   (`pre-1.14.4`, `pre-1.14.5`, `pre-1.14.6`, `stale-20261105`) beside the live `kit.json`. Harmless,
   but they predate the installed app and can confuse a future restore.
5. **DEADZONE: HAVEN (P2, separate work).** The Forge is verified; the game is not. Its real project
   push, gameplay smoke, multiplayer and published-place behaviour were not exercised in this pass.
6. **Cross-host integration (P2).** Only Hermes was exercised. Claude Code, Codex, Grok, Kimi and
   Antigravity were not connected or handshaked here, and no claim is made about them.

## 6. Registry contract


`BUNDLED-TOOLS/COMPANIONS.json` is the single list of supported owners. It deliberately contains
**no** install logic and **no** command runner: the bundle detects, reports and prints owner
entrypoints. Rules enforced by `validate()` and proven by tests:

- only `github.com/SenjuWoo/` repositories are trusted;
- `source_only` may not advertise a downloadable asset; `release_zip` must name one;
- a directory counts only when its name matches the owner's repository name, so a backup or an
  unrelated tool holding the same marker file cannot be reported as that companion;
- unknown install kinds and empty marker lists are rejected.
