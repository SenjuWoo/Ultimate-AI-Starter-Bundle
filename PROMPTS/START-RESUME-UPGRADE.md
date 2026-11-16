# Start, resume or upgrade a project

Four situations, one prompt each. Paste one at the start of a chat and fill in
the bracketed parts; do not repeat it in later messages.

| Situation | Prompt |
|---|---|
| A new chat with a new task | [GENERAL-1-START-AND-FINISH.txt](GENERAL-1-START-AND-FINISH.txt) ([why](#new-chat)) |
| A large or unfamiliar job: one model plans, another builds | [GENERAL-2-ARCHITECT-PLAN.txt](GENERAL-2-ARCHITECT-PLAN.txt) ([why](#plan)) |
| Continuing unfinished work, or building a finished plan | [GENERAL-3-WORKER-EXECUTE.txt](GENERAL-3-WORKER-EXECUTE.txt) ([why](#resume)) |
| A usage limit was hit and you have to resume | [GENERAL-4-USAGE-LIMIT-RESUME.txt](GENERAL-4-USAGE-LIMIT-RESUME.txt) ([why](#usage-limit)) |
| A newer, more capable model takes over an existing project | [Upgrade audit](#upgrade-audit) |

The four files are the paste-ready prompts and the only home of that text;
this guide explains when to use each and carries the one prompt that has no
file (Upgrade audit).

They are short on purpose. The installed instructions already carry the detailed
rules; a prompt only says what this chat is for, in what order to work and what
finished means. These are recommended defaults across providers, not text the
installer prepends to every message. Put the changing task after the stable
instructions; actual cache reuse still depends on the provider. More emphatic
text does not grant tools, permissions or extra capability.

## New chat

Use this for any ordinary task in a fresh chat: it orients on the project's
instructions and state files, reads the machine map before searching any drive,
finds the real tool instead of calling one missing, checks facts against the
installed tool, works through to a finished and verified result (planning in
PLAN.md first for large jobs), and updates STATE.md. The whole prompt is in
`GENERAL-1-START-AND-FINISH.txt`.

To hand the model the design as well (a Fable chat, or any model you trust with
direction), make the first line of the file
`You are the owner and long-term maintainer, and its design is up to you.`

## Plan

For a new project, an unfamiliar codebase or several connected systems. Spend the
strongest model on the decisions once, then build with a cheaper one: for
example Fable High plans and Opus High builds (Medium for routine, well-specified
tasks). The plan lives in the project's `PLAN.md`, which the task controller reads.

Paste-ready text: `GENERAL-2-ARCHITECT-PLAN.txt`

Build it in a fresh chat with the [Resume](#resume) prompt: it starts at the first
unfinished task, verifies each one and records the evidence in `PLAN.md`. When the
builder meets a design question the plan does not answer, it writes that question
under Decisions and carries on with independent tasks; take only that question back
to the planning model.

## Resume

Use this to continue unfinished work, or to build a finished plan - the builder
starts at the first unfinished task, verifies each one and records the evidence in
`PLAN.md`. Paste-ready text: `GENERAL-3-WORKER-EXECUTE.txt` (if the plan hits a
design question it does not answer, it writes the question under Decisions and
carries on with independent tasks; take only that question back to the planner).

A resume prompt cannot reconstruct a missing conversation: in a chat with no
history, give the project location, the original goal and the handoff file.

## Usage limit

A previous chat hit a provider usage limit mid-task. Paste-ready text:
`GENERAL-4-USAGE-LIMIT-RESUME.txt`. Use it after a cut in any of the other three:
it works out whether the cut chat was planning, building or doing a one-chat job
and continues in that role (a cut planner keeps planning and implements nothing; a
small job with no PLAN.md continues from STATE.md and the diff). It reads as little
as possible (STATE.md, git status/diff, PLAN.md - never the whole tree), reuses
recorded evidence and re-checks only what an interrupted command can break. To
start building a finished plan in a fresh chat, use Resume instead.

## Shared conventions

All four files use the same wording for the parts they share, so they cannot
contradict each other. `PLAN.md` (exactly that name) starts with `goal:` and has
one table `| ID | Task | Status | Depends on | Verify | Evidence |`; Status is one
of `pending`, `active`, `complete`, `failed`, `blocked`, `superseded`; Verify is
`cmd:<command>` or `file:<path>`; Evidence for a command is
`cmd:<the Verify command> @ <short SHA> exit=0`. That is the format the task
controller (`task_state.py`) parses; any other column name, status word or prose
evidence makes it report the task as unverified.

Model and effort are chosen in the host, not by the prompt: a strong planner at
High for Plan (Xhigh only when High cannot settle it), a strong builder at High
for Resume and New chat, Medium for routine well-specified work.

## Upgrade audit

For the day a stronger model arrives, or when a project has not been looked at
for a long time. It asks for a full audit and the fixes, not a review document.

```text
You are the new owner and long-term maintainer of [project path]; its design and direction are up to you. Audit all of it and upgrade it.
Purpose of the project: [one line, or "read it from the README and STATE.md"].
Must not change: [public API, file formats, my content and prompts, ...; or "nothing beyond the standing rules"].

1. Learn it before judging it. Read the instructions, ownership and state files, README, changelog, recorded decisions, tests, CI and the release process. Map the structure (use the code graph if the project is indexed). Run the existing build, tests and doctor and record that baseline; a red baseline is the first finding.
2. Audit all of it, not a sample: wrong results, silent failures and swallowed errors, claims that no code or test backs, dead or duplicated code, patterns a newer tool or API version made obsolete, risky code without tests, slow or fragile paths, security and data-loss risks, install, update and uninstall on a clean machine, and docs that no longer match. Check every suspicion against the code and the current tool version before calling it a defect. Notes and workarounds left by earlier models are evidence, not truth; they can be wrong in either direction.
3. Rank the findings by what they cost the user: broken or untrue first, then fragile, then slow, then untidy. Show me the ranked list with its evidence (file and line, command and output) and the plan. Then proceed without waiting, unless a change is destructive, public, costly or alters the direction of the project.
4. Fix in small verified steps: a failing test or reproducer first where one is possible, the smallest change that fully fixes the cause, the whole suite after each group. Keep behaviour, formats, names and my settings unless changing them is the fix. Do not rewrite working code for taste. Do not remove content, features or personal rules because you would have written them differently. Where you only suspect something is better, say so instead of changing it.
5. Carry the rest with it: tests, docs, version and changelog, STATE.md, and a release through the project's own path (gate, push, checks on the exact commit, release, install, doctor). End with what was wrong and is fixed, what was proven by running it, what is still unverified or deliberately left, and what you would do next.
```

None of these prompts grants tools or permissions, or by itself authorizes
destructive actions, costs or public publication. Keep detailed private history
out of the prompt: point at dated project evidence instead.
