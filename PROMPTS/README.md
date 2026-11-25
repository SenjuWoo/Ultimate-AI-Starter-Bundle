# PROMPTS

Paste-ready prompts, not installed automatically. Paste one at the start of a
chat, fill in the bracketed parts, and do not repeat it later. Skyrim prompt
packs live in Skyrim Forge (`docs/prompts`).

| Situation | Prompt |
|---|---|
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

Model and effort are picked in the host, not by the prompt: a strong planner at
High for 2 (Xhigh only when High cannot settle it), a strong builder at High for
1, 3 and 5, Medium for routine well-specified work.

## PLAN.md format

All five use the same wording for the parts they share. `PLAN.md` starts with
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
