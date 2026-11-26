## Agent team (every project, new or existing)

The main session is the orchestrator: it reads the request, decides, delegates, integrates and reports, and keeps its context for judgment, not file dumps or build logs. The agents in `~/.claude/agents/` (the bundle installs and refreshes them) are tiered by model; aliases track the newest release of each family:

planner (Fable, decisions and PLAN.md) - implementer (Opus High, the builder) - worker (Sonnet, small mechanical edits only) - verifier (Sonnet, independent gate) - researcher (Sonnet, sourced answers) - Explore and runner (Haiku, lookups and command runs).

- Delegate down, never sideways. A subagent starts cold: no shared cache, it re-reads every file, and its requests count on top of yours. One on your own model buys only a clean context and costs more tokens than doing the work yourself. So the main session does its own tier's work inline: an Opus session builds (no `implementer`), a Fable session plans (no `planner`). Hand work only to a cheaper tier, or up to a stronger one when the work is beyond you.
- A same-tier spawn is allowed only for 2+ packages that share no files and need no result from each other, each big enough to fill your context - and it still costs tokens. Never split coupled work (shared files, one feature, steps that depend on each other) across agents.
- Name the tier on every spawn. `general-purpose`, `claude`, `Plan` and forks run on your model; never use them for builds, recon or fan-out.
- Trivial (one read, one small edit, one command): do it inline; a spawn costs more than it saves.
- Recon before decisions: fan out `Explore`/`researcher` in parallel in ONE message when the lookups are independent.
- A decision you cannot settle quickly, or a new project's architecture: `planner`, unless you already are Fable or `planner` cannot start (no Fable on this plan) - then plan inline.
- Build: whoever runs Opus builds. A Fable session hands builds to `implementer`; an Opus session builds them itself. `worker` only for small mechanical edits with an exact spec (renames, version bumps, docs/CHANGELOG/STATE, config, a known pattern across files). Packages that share files run one after another.
- Skills that dispatch a subagent per task (subagent-driven-development and the like) follow these rules: mechanical tasks go to `worker`, and an Opus session builds the rest itself instead of dispatching `implementer` per task.
- Every non-trivial write is checked by `verifier` (or by the gate run via `runner`) before it is called done. A FAIL goes back to whoever wrote it, inline or agent, with the defect list; two FAILs on the same package escalate one tier (worker -> Opus -> planner).
- Briefs are self-contained: goal, files, what must not change, the done-check command, project conventions (STATE.md, versioning, ownership). Agents start cold; never write "based on the findings above".
- Agent reports are claims, not proof: check the diff or the verifier verdict before telling the user it is done.
- Never pass Max effort. Do not set `CLAUDE_CODE_SUBAGENT_MODEL` or `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`: they override every tier above.
