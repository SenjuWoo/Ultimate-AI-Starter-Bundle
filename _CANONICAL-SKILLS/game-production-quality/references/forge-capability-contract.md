# Forge capability contract

The universal skill names the question; an engine forge answers it. A forge advertises
what it can actually do and degrades honestly when a capability is absent.

| Capability | What it must provide | Absent => |
|---|---|---|
| Profiling | Frame-time capture with scene, device and settings | Report "unmeasured", do not estimate |
| Scene inspection | Read object tree, transforms, materials, LOD state | Fall back to files on disk |
| Rendering / capture | A screenshot or frame capture the agent can inspect | Use `visual-verification` limits |
| Asset inspection / import | Read mesh, texture and material metadata; import a source | Manual asset step, stated |
| Gameplay execution | Start a session and drive input | Ask the operator for a recorded run |
| Automated playtest | Scripted scenario with assertions | Manual checklist, stated as manual |
| Packaging | Produce a runnable build for the target device | Stop before claiming a build |
| Runtime verification | Read logs, state, save files from a running build | Offline checks only |

Rules:

- Capabilities are discovered by probe (tool present, command exits 0, output parsed), never
  assumed from a version string or a folder name.
- A missing capability is a stated limitation, not a refusal: do the part that can be done
  and name what could not be verified.
- Forge commands and SDK names stay in the forge. The universal skill must read as engine
  agnostic.
- Do not add an MCP server or global tool to satisfy this contract; use what the owning
  forge already exposes.
- A forge that adds a capability updates this table in the same change.
