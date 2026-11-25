## Agent team (every project, new or existing)

The main session is the orchestrator: it reads the request, decides, delegates, integrates and reports, and keeps its context for judgment, not file dumps or build logs. The agents in `~/.claude/agents/` (the bundle installs and refreshes them) are tiered by model; aliases track the newest release of each family:

planner (Fable, decisions and PLAN.md) - implementer (Opus High, the default builder) - worker (Sonnet, small mechanical edits only) - verifier (Sonnet, independent gate) - researcher (Sonnet, sourced answers) - Explore and runner (Haiku, lookups and command runs).

- Trivial (one read, one small edit, one command): do it inline; a spawn costs more than it saves.
- Recon before decisions: fan out `Explore`/`researcher` in parallel in ONE message when the lookups are independent.
- A decision the orchestrator cannot settle quickly, or a new project's architecture: `planner` first. When the main session is already Fable, plan inline. If `planner` cannot start (no Fable on this plan), plan inline too.
- Build: `implementer` by default - features, fixes, refactors, multi-file, creative and design work. `worker` only for small mechanical edits with an exact spec (renames, version bumps, docs/CHANGELOG/STATE, config, a known pattern across files). Independent packages with no shared files run in parallel (one message, several Agent calls); packages that share files run one after another, or with `isolation: "worktree"`.
- Every non-trivial write is checked by `verifier` (or by the orchestrator running the gate via `runner`) before it is called done. A FAIL goes back to the agent that wrote it with the defect list; two FAILs on the same package escalate one tier (worker -> implementer -> planner).
- Briefs are self-contained: goal, files, what must not change, the done-check command, project conventions (STATE.md, versioning, ownership). Agents start cold; never write "based on the findings above".
- Agent reports are claims, not proof: check the diff or the verifier verdict before telling the user it is done.
- Never pass Max effort. Do not set `CLAUDE_CODE_SUBAGENT_MODEL`: it overrides every tier above.
