# Codex instructions

Skills live in `%USERPROFILE%\.agents\skills`, Codex's supported user-level root. Leave `%CODEX_HOME%\skills` to Codex's own `.system` cache; a second copy there is indexed twice.

- Follow the `AGENTS.md` hierarchy and the closest project override. Keep Codex-native memories under Codex control.
- Subagents only for independent exploration or review, each with a narrow written brief (paths, scope, forbidden actions, expected evidence); one owner writes coupled files. A subagent forked with the full history re-reads all of it.
- On "continue", after a usage-limit reset or in a new session on an existing project, read the project's STATE/handoff file and `git status` before acting; do not redo verified research.
- Compile the exact target against exact local dependencies before packaging.
