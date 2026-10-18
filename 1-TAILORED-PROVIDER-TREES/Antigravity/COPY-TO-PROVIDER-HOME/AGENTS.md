# Antigravity instructions

Where this app keeps customizations (verified against Antigravity's own
`agy-customizations` guide and the docs at antigravity.google):

- Global rules: this file, `%USERPROFILE%\.gemini\config\AGENTS.md` (also
  read: `%USERPROFILE%\.gemini\AGENTS.md`).
- Workspace rules: `AGENTS.md` or `GEMINI.md` in any project directory, plus
  `.agents/AGENTS.md` and `.agents/rules/*.md`.
- Global skills: `%USERPROFILE%\.gemini\config\skills\<name>\SKILL.md`.
- Workspace skills: `<workspace>\.agents\skills\<name>\SKILL.md`.
- MCP servers: `%USERPROFILE%\.gemini\config\mcp_config.json` (global) or
  `<workspace>\.agents\mcp_config.json` (per project), both `mcpServers`.

Rules are truncated past 24,000 bytes per file and share a 20,000-token budget
across global and always-on rules, so keep this file terse and put detail in
skills. Do not copy these skills into another app's home: every provider owns
its own tree, and duplicate copies drift.

- Read the workspace's `AGENTS.md` / `.agents/rules` before editing: they
  override this file where they are more specific.
- Prefer the Antigravity browser and terminal tools for inspection; state what
  you verified instead of describing what you would do.
