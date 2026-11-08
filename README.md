<!-- Ultimate AI Starter Bundle v8.37.21 -->
# Ultimate AI Starter Bundle v8.37.21

One installer that gives every AI coding app on Windows the same skills, tools and
project knowledge — so a fresh chat already knows how you work and where your
games, mods and tools live.

**What it is not:** another model, a hosted service, or a package manager for
other people's tools. It is the foundation those tools plug into.

## Install in three steps

1. Download **`…-Core.zip`** from the
   [latest release](https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/latest)
   and unzip it. On a slow or restricted network use **Full-Offline** instead.
2. Double-click **`START-HERE.bat`**. If Windows warns, choose *Run*; allow
   administrator rights if asked.
3. Wait for **INSTALL COMPLETE**, then close and reopen your AI apps.

Requires Windows 10/11, an internet connection and at least one supported app.
The default install also adds a compiler suite (several GB); `-SkipBuildTools`
skips it.

| File | Pick it when |
|---|---|
| `…-Core.zip` | Normal connected install (~34 MiB). Payloads are fetched during install; same result as Full-Offline. |
| `…-Full-Offline.zip` | One file for an unreliable network (~128 MiB). Payload snapshots only — inference still needs your provider or a local model. |
| everything else | Checksums, build receipt, SBOM, attestation. Not needed to install. |

## Supported apps

Claude Code · Codex · Grok · Kimi · Hermes · Google Antigravity. Each gets the
same skills and instructions in its own format; apps you do not have are skipped.

| You want to | Do this |
|---|---|
| Update | Run `START-HERE.bat` again; it installs a newer release and keeps your settings. |
| Only some apps | `START-HERE.bat -Providers Claude,Codex` |
| Check the install | Run `START-HERE.bat` again; the last step prints PASS or the exact problem. |
| Verify by hand | `powershell -File TOOLS/Test-Installed-State.ps1` |
| Undo leftovers | `powershell -File TOOLS/Clean-StaleState.ps1 -Apply` (dry run without `-Apply`) |

## What you get

| | |
|---|---|
| **81 general skills per AI** | planning, review, debugging, modding routes, publishing, research — loaded only when a task needs them |
| **Base MCPs** | `context7`, `headroom`, `toolbox` everywhere; code-intel in the code profile |
| **Compilers** | Go, Rust, GCC, .NET, CMake/Ninja, Xmake, MSVC and the Windows SDK |
| **Verification** | pack gate, installed-state doctor, RTK routing, evidence rules |
| **Project state** | `PLAN.md`/`STATE.md` templates plus a deterministic task controller |
| **Free routes** | local models, free tiers and local asset generators; no paid component is required |

## Add-ons stay independent

Forge families, Reverse THIS! and comfy-kit own their own code, releases and
doctors. The bundle only **discovers** them:

```
python TOOLS/companion_registry.py --verify     # NOT_FOUND / DISCOVERED / INSTALLED_UNVERIFIED
```

The base packs are `automatic when Skyrim or Forge is found` and
`automatic when its kit is found`; a missing owner is skipped. Nothing is installed twice,
and turning the pack off leaves the owner intact. Skyrim Forge and Reverse THIS!
install their own **latest release** through their own installers when detected;
the bundle pins no version and never reimplements an owner's tools.

## Projects, skills and private settings

- `TOOLS/Initialize-Workspace.ps1` seeds a project with `PLAN.md` (task table with IDs,
  dependencies, verification, evidence), `STATE.md` (goal, current task, next
  action, blockers), `MEMORY/`, `VISION.md` and `WORKSPACE_OWNERSHIP.md`.
- With a task table present, a small controller answers "what next" without a
  model call: `next`, `status`, `resume [--fix]`, `handoff`. Its absolute path is
  recorded in `MACHINE-MAP.md`, so it works from any project folder.
- Personal preferences live in `~/.uabs/profile/PROFILE.md`; generated paths live
  in `MACHINE-MAP.md`. Neither is published.
- Your model choices, instructions and configs are preserved; files are backed up
  before any change.

## Models

The starter ships one model: **`deepseek/deepseek-v4.1-flash-1017`** at high
reasoning effort. One strong worker finishes more work per dollar than a cheap
aggregator plus a planner; the MoA presets are defined but disabled. Routing sorts
by price with `require_parameters: true` and hardcodes no provider list.

```
python TOOLS/refresh-provider-routing.py          # today's cheapest cache-read providers
python TOOLS/refresh-provider-routing.py --write <config>   # pin them (backup + atomic write)
```

Existing model choices are never replaced on upgrade, and there is **no fallback chain**: a silent downgrade is worse than a clear error. Shipped aliases are kept
and documented but are not recommendations: `hermes model v4.1-flash`, `flash`,
`v4-pro`, `muse`, `gemini-flash`, `glm`, `grok`, `sol`, `opus`,
`nemotron-ultra`, `nemotron-ultra-nofree`; `local` is whatever your own LM Studio
serves, since the portable starter ships no machine-specific endpoint. Dated
prices and a worked cost example: [docs/HERMES-MODELS.md](docs/HERMES-MODELS.md).

## Verified, not claimed

A `PASS` means a command ran and its exit status was checked. The pack gate checks
skill trees, PowerShell parsing, offline hashes and upgrade fixtures; the doctor
re-hashes what each install receipt binds; the release pipeline builds twice and
requires identical bytes before publishing. `reviewer` claims from a model are not
evidence — `PLAN.md` evidence has to name a command, a revision and an exit code.

## Documentation

| Document | Contents |
|---|---|
| [Reference guide](docs/GUIDE.md) | every install switch, provider wiring, what gets installed, troubleshooting |
| [Hermes models](docs/HERMES-MODELS.md) | dated prices, aliases, compression, caching |
| [Tool evaluations](docs/TOOL-EVALUATIONS.md) | what was evaluated, what was rejected, why |
| [Decisions](docs/decisions/) | the architecture rules this repository is held to |
| [Changelog](CHANGELOG.md) · [history](docs/history/) | release notes |
| [Notices](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md) | licences and attribution |

## Known limitations

- A few skills exceed the body-size budget; `TOOLS/audit_skills.py` names them.
- The knowledge graph cannot read Papyrus; use source search for `.psc`.
- Compatibility holds are deliberate: newer upstream is not automatically tested.
- Free model availability and prices change; the live catalog outranks any snapshot.
- Full-Offline carries payload snapshots, not every runtime or dependency cache.
- Parsing, packaging and protocol handshakes do not prove gameplay or GPU
  performance.

<a id="ownership"></a>

## Third-party components

This list includes redistributed code, fetched packages and catalog-only candidates.
**A listing does not mean installed or connected.** Evaluated versions, source
commits and compatibility holds belong in [CATALOG.json](BUNDLED-TOOLS/CATALOG.json).

| Catalog ID | Upstream project | Integration |
|---|---|---|
| `universal-modder` | [Universal Modder](https://github.com/rehan-remade/universal-modder) | Vendored CLI/source and routed guides; default install |
| `uabs-toolbox` | [UABS Toolbox](https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle) | Bundle-owned; always-on find/describe/call, starts project tools on demand |
| `housecarl` | [houseCARL](https://github.com/Avick3110/houseCARL) | Offline payload; game/profile scope |
| `codebase-memory` | [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | Offline payload; code profile |
| `headroom` | [Headroom](https://github.com/headroomlabs-ai/headroom) | Wheel/source; core MCP |
| `superpowers` | [Superpowers](https://github.com/obra/superpowers) | Vendored skills and native plugins |
| `ponytail` | [Ponytail](https://github.com/DietrichGebert/ponytail) | Vendored skills and native plugins |
| `codeburn` | [CodeBurn](https://github.com/getagentseal/codeburn) | Default on-demand CLI |
| `impeccable` | [Impeccable](https://github.com/pbakaus/impeccable) | Vendored skill/detector; separately pinned CLI |
| `code-review-skill` | [Code Review Skill](https://github.com/awesome-skills/code-review-skill) | Vendored canonical skill |
| `obsidian-skills` | [Obsidian Skills](https://github.com/kepano/obsidian-skills) | Vendored canonical skills; no duplicate plugin needed |
| `claude-mem` | [claude-mem](https://github.com/thedotmack/claude-mem) | Explicit -WithClaudeMem only |
| `playwright-mcp` | [Playwright MCP](https://github.com/microsoft/playwright-mcp) | Scoped browser MCP |
| `firecrawl-mcp` | [Firecrawl MCP](https://github.com/firecrawl/firecrawl-mcp-server) | Security-held; not installed/registered |
| `perplexity-mcp` | [Perplexity MCP](https://github.com/perplexityai/modelcontextprotocol) | Credential-gated MCP |
| `context7` | [Context7](https://github.com/upstash/context7) | Core documentation MCP |
| `github-mcp-server` | [GitHub MCP Server](https://github.com/github/github-mcp-server) | Official offline binary; core MCP |
| `serena` | [Serena](https://github.com/oraios/serena) | Code-intel / Hermes code profile; LSP navigation and symbol edits |
| `chrome-devtools-mcp` | [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp) | Scoped browser inspection |
| `shadcn-mcp` | [shadcn MCP](https://github.com/shadcn-ui/ui) | Matching project registry profile |
| `blender-mcp` | [Blender MCP](https://github.com/ahujasid/mcp-for-blender) | Editor profile; Blender/addon prerequisite |
| `godot-mcp` | [Godot MCP](https://github.com/Coding-Solo/godot-mcp) | Editor profile; Godot prerequisite |
| `unity-mcp` | [Unity MCP](https://github.com/IvanMurzak/Unity-MCP) | Project package/generated executable prerequisite |
| `rtk` | [RTK](https://github.com/rtk-ai/rtk) | Default CLI; narrow routing |
| `omni` | [OMNI](https://github.com/fajarhide/omni) | Catalog/evaluation only; not installed |
| `windows-mcp` | [Windows MCP](https://github.com/CursorTouch/Windows-MCP) | Manual opt-in; OFF by default |
| `super-mcp-router` | [Super MCP Router](https://github.com/mindstone/Super-MCP) | Evaluated catalog entry; no default router wiring |
| `playwright-cli` | [Playwright CLI](https://github.com/microsoft/playwright-cli) | Default CLI; browser installation separate |
| `comfy-cli` | [ComfyUI CLI](https://github.com/Comfy-Org/comfy-cli) | Optional user-managed tool; not installed by default |
| `rea` | [REA](https://github.com/morluto/rea) | Optional pinned CLI; no global MCP or setup writes |
| `reverse-this` | [Reverse THIS!](https://github.com/SenjuWoo/reverse-this) | Optional standalone analysis workbench; source MIT, individual payload licenses apply |
| Reverse THIS! | [Reverse THIS!](https://github.com/SenjuWoo/reverse-this) | Reuses an existing discovered tool bench; no duplicate installation |
| CLI-Anything | [HKUDS/CLI-Anything](https://github.com/HKUDS/CLI-Anything) | Companion hub of per-app agent CLIs (Blender, FreeCAD, GIMP, Audacity, Godot, ComfyUI, browsers...). `pip install cli-anything-hub`, install the harnesses you need. Apache-2.0; v0.4.0 checked 2026-10-16. Not redistributed or installed by the pack. |
| anti-slop | [miqdadbadjuber/anti-slop](https://github.com/miqdadbadjuber/anti-slop) | MIT rules filter against generic AI UI, filler copy and AI-shaped code (`rules/antislop.md` plus a CLI). Overlaps the bundled `impeccable` and `humanizer` skills; use it as an extra filter. v3.2.21 checked 2026-10-16. |
| jevgrep | [dzhng/jevgrep](https://github.com/dzhng/jevgrep) | Hosted code-search CLI (`jg`) that answers repo questions through Jev and returns files plus verbatim excerpts; needs its own account. The bundled `codebase-memory-mcp` already answers that class of question locally. 0.8.0 checked 2026-10-16. |
| Caveman | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | Voice/input compression with its own multi-agent installer and an optional routing layer. **Conflicts with this bundle's wiring**: its installer writes the same `SOUL.md` / `AGENTS.md` / skills / hooks / `settings.json` files this pack owns, and its routing layers repoint `ANTHROPIC_BASE_URL`. Evaluated 4.0.1 (Apache-2.0) 2026-10-16 — documented, not installed; see [evaluations](docs/TOOL-EVALUATIONS.md). |
| OmniRoute | [diegosouzapw/OmniRoute](https://github.com/diegosouzapw/OmniRoute) | Local free-tier gateway for CLI agents (`localhost:20128/v1`, 13 `setup-*` commands, RTK + Caveman compression inside). **Conflicts with this bundle's invariants**: it takes over provider endpoints and depends on stacked third-party free tiers, which the bundled `token-efficiency` skill rules out as a default. Evaluated 3.8.51 (MIT) 2026-10-16 — documented, not installed. |

Additional canonical payloads without separate tool-catalog entries:

| Payload | Upstream | Integration |
|---|---|---|
| `img2threejs` | [img2threejs/img2threejs](https://github.com/img2threejs/img2threejs) | Pinned pointer skill (v1.5.1); the tool tree lives in its own repo |
| AssetForge | [SenjuWoo/AssetForge](https://github.com/SenjuWoo/AssetForge) | Owns 2D/3D asset production, validation and engine export (MIT). Detected by the companion registry; optional providers (Blender, glTF-Transform, comfy-kit) are discovered, never installed by the bundle |
| Ponytail | off by default through its own `defaultMode`; `python TOOLS/ponytail_mode.py lite|full|ultra|auto|off --apply` | no minimalism imposed on creative work; plugin and `/ponytail` stay available |
| `awesome-gamedev-agent-skills` | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | Optional engine pack (Apache-2.0, pinned `19d93f9`, 2026-10-28). Not vendored and never installed by the bundle: the detector reports it, routing picks the engine, and [the review](docs/RECOMMENDED-GAME-DEV-SKILLS.md) covers install, precedence and removal |
| `skill-creator`, `build-mcp-server`, `build-mcpb`, `build-mcp-app` | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | Selected cross-provider skills, not the entire marketplace |
| Hermes native Unity bridge | [CoplayDev/unity-mcp](https://github.com/CoplayDev/unity-mcp) | Existing Coplay editor backend, isolated in `unity`/`creative`; distinct from the IvanMurzak project route |

Skyrim Forge is the bundle author's product, released from
[SenjuWoo/SkyrimForge](https://github.com/SenjuWoo/SkyrimForge); the installer takes its latest release, verified by digest.
[Tool notices](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md) and
[skill notices](_CANONICAL-SKILLS/THIRD-PARTY-NOTICES.md) retain licenses,
credits and adaptation notes. The pack's MIT license does not relicense these
projects. Preserve upstream attribution when redistributing.

<a id="ownership"></a>

</details>

## Version

The version is in [VERSION.txt](VERSION.txt). Every release, with notes, checksums,
SBOM and attestation, is on the
[releases page](https://github.com/SenjuWoo/Ultimate-AI-Starter-Bundle/releases).

## Licence

Original code and docs are [MIT](LICENSE); third-party payloads keep their own
terms — see the [notices](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md).

Resuming after a break or a usage limit? Copy one of the
[short cross-provider prompts](PROMPTS/START-AND-RESUME.md) and add your task.
