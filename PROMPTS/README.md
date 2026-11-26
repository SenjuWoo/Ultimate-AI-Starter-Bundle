# PROMPTS

Paste-ready prompts, not installed automatically. Paste one at the start of a
chat, fill in the bracketed parts, and do not repeat it later. Skyrim prompt
packs live in Skyrim Forge (`docs/prompts`).

| Situation | Prompt |
|---|---|
| Claude Code: check and repair the installed agent team (after an install, update or new model) | [GENERAL-0-AGENT-TEAM.txt](GENERAL-0-AGENT-TEAM.txt) |
| A new chat with a new task, start to finish | [GENERAL-1-START-AND-FINISH.txt](GENERAL-1-START-AND-FINISH.txt) |
| A large or unfamiliar job: a strong model plans, a cheaper one builds | [GENERAL-2-ARCHITECT-PLAN.txt](GENERAL-2-ARCHITECT-PLAN.txt) |
| Build a finished plan, or continue unfinished work | [GENERAL-3-WORKER-EXECUTE.txt](GENERAL-3-WORKER-EXECUTE.txt) |
| A usage limit cut the last chat short | [GENERAL-4-USAGE-LIMIT-RESUME.txt](GENERAL-4-USAGE-LIMIT-RESUME.txt) |
| A newer model takes over, or a project went unchecked: audit and upgrade | [GENERAL-5-UPGRADE.txt](GENERAL-5-UPGRADE.txt) |

They are short on purpose: the installed instructions carry the detailed rules,
so a prompt only says what this chat is for, in what order to work and what
finished means. None grants tools or permissions, or by itself authorizes
destructive actions, costs or public publication. A resume prompt cannot
rebuild a missing conversation: in a chat with no history, give the project
location, the goal and the handoff file.

Model and effort are picked in the host, not by the prompt: the strongest model
at High plans and orchestrates (Xhigh only when High cannot settle it); Opus at
High builds; Sonnet only for small mechanical edits, research and verification;
Haiku for lookups and command runs. Where the host has subagents, each prompt's
`Team:` line says how to delegate - in Claude Code the installer adds the agent
team (`planner`, `implementer`, `worker`, `verifier`, `researcher`, `Explore`,
`runner`) and its routing block to `CLAUDE.md`, so no project needs its own setup.
Delegation goes down a tier, never sideways: a chat already on Opus builds
inline instead of handing work to the Opus `implementer`, because a subagent on
the same model starts cold and only adds tokens.

## Which model to start a chat on (Claude Code)

The installer sets up the helper agents and their routing; the one thing left
to you is the model of the chat itself. Quality first, then cost:

| The chat is for | Start on | Why |
|---|---|---|
| Hard, new, architectural, creative or bug-hunting work; planning (prompt 2) | Fable, High | Highest measured quality; it does the hard part itself and hands only self-contained packages down |
| Building from a finished plan (prompt 3), everyday fixes and features | Opus, High | Close to Fable on routine builds at a fraction of the cost; it builds inline |
| Anything | not Sonnet or Haiku as the main chat | They are the helpers: exact edits, research, checks, lookups |

A weaker chat does ask a stronger model by itself: an Opus chat hands a
decision it cannot settle to the Fable `planner`, and with the advisor set to
Fable it can consult it mid-task. Published tests show cheaper models rarely
make that call on their own, so for work you already know is hard, start on
Fable instead of relying on it. An advisor must rank at or above the chat's
model: with a Fable chat only Fable qualifies, and it adds little there.

## PLAN.md format

All of them use the same wording for the parts they share. `PLAN.md` starts with
`goal:` and has one table `| ID | Task | Status | Depends on | Verify | Evidence |`.
Status is `pending`, `active`, `complete`, `failed`, `blocked` or `superseded`;
Verify is `cmd:<command>` or `file:<path>`; Evidence for a command is
`cmd:<the Verify command> @ <short SHA> exit=0`. That is what the task
controller (`task_state.py`) parses; any other column name, status word or
prose evidence reads as unverified.

The operating contract does not live here: the default is
`../0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md`, installed by `INSTALL-AIO.ps1`, with
smaller opt-in variants beside it (`AIO-INSTRUCTION — Compact.md`,
`AIO-INSTRUCTION — Web.md`).
