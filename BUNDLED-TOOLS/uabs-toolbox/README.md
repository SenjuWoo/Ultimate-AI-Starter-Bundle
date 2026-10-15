# UABS toolbox

One small MCP server that stays on in every AI chat and reaches the project
tools that are kept off to save tokens: game forges (RimWorld, Skyrim, Roblox,
Saints Row), AvatarForge, Melty, Blender, Unity, Godot, browser automation,
the code graph, GitHub and more.

The AI uses three tools:

| Tool | What it does |
|---|---|
| `find` | Matches a task ("build my RimWorld mod") to tool sets, starts the best one and lists its tools |
| `describe` | Returns the input schema of named tools (`set.tool`) |
| `call` | Runs one tool and returns that tool's own result |

A tool set starts on first use and stays up until the chat ends. Nothing is
written to any AI app's config, so nothing needs a restart.

Where tool sets come from (both written by the bundle installer into
`%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle`):

- `toolbox-profiles.json`: the bundle's own server catalog (`BUNDLED-TOOLS/PROFILES.json`)
- `parked-mcp.json`: exact copies of servers another installer had registered
  in every chat (`TOOLS/Set-McpProfile.ps1 -Park`); credentials in them are used
  to start the server and never printed

Diagnostics: `uabs-toolbox --list` prints what this PC can start. Set
`UABS_TOOLBOX_DEBUG=1` for a full log in `...\Ultimate-AI-Starter-Bundle\logs\toolbox.log`;
each started server's own stderr goes to `toolbox-<set>.log` beside it.

Gate: `TESTS/test_toolbox.py` (needs a Python with `mcp==1.30.0`).
