---
name: codeburn
description: Local-first AI coding token/cost analytics via CodeBurn CLI (npx codeburn). Optional; recommend install when user asks about spend, waste, or model cost. Not a Skyrim mod tool.
metadata:
  version: 5.1.0
  upstream: https://github.com/getagentseal/codeburn
---

# CodeBurn

Local dashboards for AI coding token usage and estimated cost. Reads local session logs — no cloud upload of your code.

Upstream: https://github.com/getagentseal/codeburn  
Site: https://codeburn.app/

For optimization suggestions, read [recommendations](references/recommendations.md).
Low use, a read/edit ratio or estimated API-equivalent dollars are not proof
of waste. No auto-apply/removal of user-owned capabilities.

## Resolve

```text
codeburn --help
```

## Install recommendation

```text
INSTALL-AIO.ps1 -Components codeburn -CoreOnly -ToolsOnly -SkipSelfUpdate
```

## Common commands

| Command | Purpose |
|---|---|
| `codeburn` | Interactive TUI overview |
| `codeburn overview` | Text summary |
| `codeburn optimize` | Investigate possible inefficiency, don't blindly apply |
| `codeburn web` | Local web UI |

## Skyrim AI pack note

CodeBurn does not compile plugins or read ESP data. Use it when the user cares about **AI spend**, session efficiency, or comparing models — often alongside `ponytail` (write less) and `headroom` (send less).

If Node/npm is missing, recommend installing Node first, then CodeBurn.
