# Reverse-engineering routes, on demand

Pick the operation, not every tool with an RE label. All five providers use
these same CLIs; no RE MCP is registered globally by this recipe.

| Need | First choice |
| --- | --- |
| Identify an unfamiliar game, engine, loader and modding route | Installed `um scan "<verified game folder>" --json`; Universal Modder guide |
| Disassembly/decompilation, APK/resources, assets, debugging | Existing Reverse THIS! tool shims, selected for the actual format |
| Evidence-linked static JavaScript/Electron or managed-assembly analysis | REA CLI; use its subcommand help, then retain/filter JSON locally |
| Skyrim records, Papyrus or framework syntax | Skyrim specialist skills/Forge; REA is not a replacement |

## Reuse Reverse THIS!

Resolve `%LOCALAPPDATA%\ReverseThis\kit.json`, parse its `kit_root`, and verify
that root, `sandbox/installed.json` and the selected `sandbox/bin` shim exist.
An explicit verified conversation path is a fallback. Do not search entire
drives or reinstall another Ghidra/Java/.NET/tool suite. Run the selected shim's
help or the kit's `Install-Modkit.ps1 -Doctor` before relying on it.
The folder named sandbox is **not** process isolation.

## REA CLI

The optional `rea` catalog component pins `rea-agents@6.4.0` and npm integrity;
Node 22.19+/24.11+/26+ is required. If needed for the current authorized task,
install it through the bundle rather than upstream's provider-writing setup:

```powershell
INSTALL-AIO.ps1 -Components rea -CoreOnly -ToolsOnly -SkipSelfUpdate
rea --help
rea analyze-javascript-application "<owned extracted app or ASAR>" --json
```

Resolve the installed CLI from PATH. Other operations start with
`rea <subcommand> --help`; don't guess their arguments. Use an owned lab copy,
retain evidence/digests on disk and send only the fields the question needs to
the model. Static observations are not runtime behavior or recovered source.
Runtime capture, instrumentation and annotation are separate actions with side
effects; never run them merely to list capabilities.

Do not run `rea setup`, `rea update`, or an upstream skill installer over
bundle-managed provider trees. No extra REA skill collection is needed.
Windows native Ghidra support is experimental with specific Ghidra/JDK/format
requirements; discover the existing kit and check REA's provider doctor before
using that route. Only static JavaScript analysis was exercised in this audit.

The 6.4.0 stdio probe advertised **170 tools / 1,954,683 schema bytes** (compact
UTF-8 array, default full input-schema profile). That is not loaded/cached/billed
tokens. CLI-first avoids attaching that inventory to ordinary chats. A genuinely
needed MCP must be scoped and filtered using the current host's supported
features; compact input schemas reduce descriptions, not the tool count.

Sources: [REA](https://github.com/morluto/rea/tree/v6.4.0),
[MCP contract](https://github.com/morluto/rea/blob/v6.4.0/docs/mcp-contracts.md),
[Reverse THIS!](https://github.com/SenjuWoo/reverse-this).
