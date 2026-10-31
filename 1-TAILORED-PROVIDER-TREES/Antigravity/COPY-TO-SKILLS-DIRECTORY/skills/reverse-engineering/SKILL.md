---
name: reverse-engineering
description: Use when analyzing an owned game or app binary, choosing a hook, proxy or injection route, or driving the Reverse THIS! workbench (Ghidra, Frida, AOB, decompilers) - routes to the encyclopedia first and enforces downstream-sink proof, narrow module-scoped hooks and hardware-gated provenance.
---

# Reverse engineering an owned target

This skill is the route and the guardrails, not a tool manual. Reverse THIS!
owns its tools, install and diagnostics; the encyclopedia owns engine
fingerprints, IPC/shader blueprints and the error registry. Read those before
writing code.

## Resolve the workbench first

1. Read `%LOCALAPPDATA%\ReverseThis\kit.json` (`kit_root`, `bin`,
   `installed_json`). An explicit `REVERSE_THIS_ROOT` wins when you set it for
   one task.
2. Read `<kit_root>\sandbox\installed.json`; call only the shims it names under
   `sandbox\bin`. Do not scan drives, reinstall a second Ghidra/.NET/Java stack,
   or run an upstream setup command.
3. Run the chosen shim's help (or the kit's `Install-Modkit.ps1 -Doctor`)
   before relying on it. `sandbox` is a folder, not process isolation.

| Need | Shim under `sandbox\bin` |
|---|---|
| Native decompile | `ghidra.cmd` or `analyzeHeadless.cmd` |
| .NET decompile / debug | `ilspycmd.cmd`, `dnspy.cmd` |
| PE triage / hex / strings | `pe-bear.cmd`, `diec.cmd`, `imhex.cmd`, `floss.cmd` |
| Dynamic trace | `frida.cmd` |
| Scripted / rule analysis | `rizin.cmd`, `rz-bin.cmd`, `yara.cmd`, `capa.cmd` |
| Debugger / handles | `x64dbg.cmd`, `systeminformer.cmd` |
| PE fingerprint / AOB / Ghidra MCP | `pe-recon.cmd`, `aob-gen.cmd`, `ghidra-mcp-up.cmd` |
| Game/engine extract | `assetripper.cmd`, `fmodel.cmd`, `repak.cmd`, `retoc.cmd`, `uassetgui.cmd` |
| Capture | `renderdoccmd.cmd` |
| Android | `jadx.cmd` |
| REA evidence workflow | `rea.cmd` |

`AGENTS.md` carries the full catalog (Source, REDengine, FromSoftware,
GameMaker, Total War and the rest). `installed.json` decides which of these are
actually present; call only what it names. Universal Modder (`um scan`) owns
game and engine recon; Skyrim records belong to the Skyrim skills and Forge.

## Look up before you build

Query Context7 for `/senjuwoo/reverse-this` (max 3 calls per turn) when the
host has that library. If it returns "not found", read the local fallback at
`%ENCYCLOPEDIA_ROOT%` (default `<kit_root>\encyclopedia`):

- `ROUTING.md` - the 6-tier ladder, stop rules and downstream-sink protocol.
- `CLAIMS.md` - scope every limit to the named tool, version and mechanism.
- `anticheat-risk.md` - publisher policy, injection vs cosmetic, account risk.
- `engines/` - axes, units, depth conventions and proxy DLLs.
- `blueprints/` - IPC seqlock and offline harness sources.
- `games/` - version-pinned field notes, when present.
- `re-recipes/` - worked routes and their evidence.
- `ERROR-REGISTRY.json` - error signature to cause.

If neither source is available, say so and use the target's own documentation;
do not invent a route, offset or signature.

## Law 1 - installation is not execution

A copied DLL, a compiled plugin or a successful attach proves nothing. Put a
canary on a verified downstream sink before claiming the hook works:
`IDXGISwapChain::Present`, `EndScene`, a UI text setter, a file write, or a
frame counter in a log. If the canary is silent, walk the stack backward from
the sink (debugger or Frida `Thread.backtrace()`) and find the producer that
should have called you. Wrapper and constructor hooks commonly miss the real
leaf call; hook the function the sink actually uses.

## Law 2 - narrow predicates, real budgets

- Scope IAT and inline hooks to the target module only (for example
  `SkyrimSE.exe`), excluding third-party DLLs and overlays.
- Add path, extension and flag predicates before the hook body; a hook that
  fires on every `CreateFileW` is a bug even when it appears to work.
- Never strip `FILE_FLAG_NO_BUFFERING`. Hook for path redirection and preserve
  the flags and alignment in any replacement handle.
- Anti-cheat is a risk boundary, not a blanket ban. Never bypass, disable,
  spoof or evade it, and never inject into a protected multiplayer process to
  gain an advantage. Some multiplayer titles leave room for client-side
  cosmetic mods even with anti-cheat running (Marvel Rivals' October 2026
  policy preserves customization while banning memory injection and
  fairness-altering mods; Monster Hunter Wilds' warning targets modified
  quests/data, and cosmetic mods are community-tolerated, not guaranteed).
  The policy is the publisher's, changes by patch, and usually turns on how the
  mod works: memory injection and patched game files are what trigger
  detection, while an official loader or a purely visual asset swap may not.
  Verify the current official statement and the mod's method, keep the change
  client-side and cosmetic, and tell the user the account risk before they run
  it. If the policy is unknown or the mod affects gameplay, progression,
  economy, matchmaking or other players, do not ship it.
- Measure the tool's RAM and cache cost before a scan or decompile; a full-disk
  Ghidra import is not a recon step.

## Law 3 - hardware gate and provenance

- Gate a graphics or neural wrapper by executable bitness, API (D3D9/11/12,
  Vulkan) and GPU architecture. A shader that reads depth cannot write depth.
- Dry-run the change and write a SHA256 recovery manifest before touching a
  game folder. Back up saves first.
- Ship Windows tools as one-folder builds; a single-file packer trips Defender
  heuristics.
- Record the target build hash, loader/framework version and the exact shim
  version. Static analysis is a hypothesis until it runs under a debugger or
  tracer; a pattern match is a candidate until it resolves in two builds.

## Ghidra MCP, when you use it

The Ghidra-side HTTP server defaults to `127.0.0.1:8080`; the MCP bridge is a
separate process and defaults to `127.0.0.1:8081/mcp` (streamable-http). Probe
both and confirm the bridge is running before configuring a client. The kit's
`sandbox\bin\ghidra-mcp-up.cmd` starts or checks it when that tool is selected;
do not assume the kit installed or started it.

## Handoff

Record the route tier, the sink, the evidence (log excerpt, frame numbers,
hashes) and what was not tested in the project's `STATE.md`. At ship, update the
encyclopedia field note and error registry as `game-modding`'s ship gate
requires.
