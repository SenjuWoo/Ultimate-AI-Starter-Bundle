# Recommended installs

Run `START-HERE.bat`. It configures the AI providers already installed on this
machine; explicit provider selections remain supported.

The common compiler suite is installed by default: Go, Rust/Cargo, GCC,
CMake/Ninja, Xmake, .NET SDK, MSVC C++ and the Windows SDK. Python, Node, Git and
GitHub CLI support the shared agent tools. Existing working toolchains and
project version pins are reused. Fresh setup may require several GB/elevation.
Use `-SkipBuildTools` to skip compiler provisioning; `-SkipRuntimes` skips all
runtime/compiler provisioning. `TOOLS/Install-BuildTools.ps1 -CheckOnly` compiles
and runs small programs; it never installs or changes user PATH.

General skills, codebase-memory, Headroom, Superpowers, Ponytail, CodeBurn,
RTK, Universal Modder and the on-demand toolbox belong to this bundle.

[Skyrim Forge](https://github.com/SenjuWoo/SkyrimForge) owns Skyrim-only tools,
houseCARL and 48 specialist skills. AIO installs the pinned release and proves
`forge doctor` when Skyrim integration is enabled. `SKYRIM_FORGE_ROOT` and
skill descriptors are generated automatically; no manual extraction is part
of a fresh install. The deployed directory has a stable name, while Git source
checkouts retain their chosen names and edits. Newer installations are preserved.

[Reverse THIS!](https://github.com/SenjuWoo/reverse-this) owns decompilers,
debuggers and REA. Reuse its kit pointer/installed manifest and invoke its
installer for specialist tools. It never changes provider settings.

Use `START-HERE.bat -Packs skyrim,reverse` for all three. Existing registered
companions are reused; their owners update supported older tools with retained
backups. Project pins, personal edits and newer compatible versions remain.
All three projects cooperate and update independently. Disabling bundle
integration does not remove another owner's content or personal edits.

Update common tools with `TOOLS/Update-From-GitHub.ps1` or
`TOOLS/Ensure-Tools.ps1`. Diagnostics are under
`%LOCALAPPDATA%/Ultimate-AI-Starter-Bundle/logs` (compiler log: build-tools.log).

Optional add-ons that stay user-owned (not installed by the bundle; evaluation in
`docs/TOOL-EVALUATIONS.md`): taste-skill for research-driven landing-page design
(`npx skills add https://github.com/Leonxlnx/taste-skill --skill "design-taste-frontend"`),
replica-skill for app-cloning projects (copy its `replica-*` folders into that project's `.claude/skills/`), and ECC alone, never stacked with another harness (`npx ecc-universal@2.2.3 install --profile minimal`).
