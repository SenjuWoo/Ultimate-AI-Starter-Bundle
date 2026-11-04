# Claude Code instructions

Skills live in `%CLAUDE_CONFIG_DIR%\skills` (default `%USERPROFILE%\.claude\skills`). Do not copy them into another app's home or a shared folder.

- Keep this file short; procedural detail lives in skills. Load only the skills the current step needs.
- Treat auto memory as a candidate until evidence confirms it.
- On "continue", after a usage-limit reset or in a new session on an existing project, read the project's STATE/handoff file and `git status` before acting; do not redo verified research.
- After review-driven changes, rebuild or recompile the exact target.
