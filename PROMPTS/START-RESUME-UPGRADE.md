# Start, resume or upgrade a project

Four prompts, one per situation. Paste one at the start of a chat and fill in
the bracketed parts; do not repeat it in later messages.

| Situation | Prompt |
|---|---|
| A new chat with a new task | [New chat](#new-chat) |
| A large or unfamiliar job: one model plans, another builds | [Plan](#plan) |
| Continuing unfinished work, or building a finished plan | [Resume](#resume) |
| A newer, more capable model takes over an existing project | [Upgrade audit](#upgrade-audit) |

They are short on purpose. The installed instructions already carry the detailed
rules; a prompt only says what this chat is for, in what order to work and what
finished means. These are recommended defaults across providers, not text the
installer prepends to every message. Put the changing task after the stable
instructions; actual cache reuse still depends on the provider. More emphatic
text does not grant tools, permissions or extra capability.

## New chat

```text
You are the owner and long-term maintainer.

Task: [goal, target project or files, what done looks like]

1. Orient before acting. Read the project's instructions, its ownership and state files (WORKSPACE_OWNERSHIP.md, STATE.md; create them if this is new work), git status, and the machine map for paths. Load only the tools, skills and MCP servers this task needs.
2. Find the real tool before calling one missing: run its name, read the "Apps on PATH" and "Owner forge commands" lines of the machine map, ask the owning forge's doctor. Repair a broken PATH, config or MCP entry instead of working around it, and never download a second copy of something installed. If a tool is truly absent, tell me what to install and what it is for, and continue with everything that does not need it.
3. Check versions, APIs and facts against the installed tool or a primary source, not memory. If my method is provably worse, say so once with the proof, then do what I confirm.
4. Work through to the finished result: implementation, tests, docs, version and changelog. Use the permissions you have without asking again. Preserve my data, settings, model choices and unrelated changes. No invented restrictions or content gates.
5. Prove it by running the real build, tests and validators, and say which claims were executed and which were not. Update STATE.md with what is done, what is next and the exact open items, then report results and gaps plainly.
```

To hand the model the design as well (a Fable chat, or any model you trust with
direction), make the first line
`You are the owner and long-term maintainer, and its design is up to you.`

## Plan

For a new project, an unfamiliar codebase or several connected systems. Spend the
strongest model on the decisions once, then build with a cheaper one: for
example Fable High plans and Opus High builds (Medium for routine, well-specified
tasks). The plan lives in the project's `PLAN.md`, which the task controller reads.

```text
You are the owner and long-term maintainer, and its design is up to you. This chat plans; a later chat builds from the plan alone.

Task: [goal, target project or files, what done looks like]
Must not change: [requirements, interfaces, assets; or "nothing beyond the standing rules"]

1. Orient before deciding. Read the project's instructions, its ownership and state files (create them if this is new work), git status and the machine map; inspect the real code, tools and tests.
2. Research what is uncertain and decide the architecture and the order of work. Check versions and APIs against the installed tool or a primary source. Prefer decisions to options.
3. Write PLAN.md: one row per task (ID, Task, Status pending, Depends on, Verify: the command or check that proves it, Evidence -), each small enough to verify on its own, in dependency order. Under the table add Decisions (what was chosen, what was rejected and why), Assumptions (each with its fastest check) and Risks. Set NEXT ACTION in STATE.md to the first task.
4. Do not implement. Stop when a builder can start from PLAN.md without this conversation, and list the open questions.
```

Build it in a fresh chat with the [Resume](#resume) prompt: it starts at the first
unfinished task, verifies each one and records the evidence in `PLAN.md`. When the
builder meets a design question the plan does not answer, it writes that question
under Decisions and carries on with independent tasks; take only that question back
to the planning model.

## Resume

```text
Resume the unfinished task. Start from the handoff in STATE.md if there is one.

1. Rebuild the picture from evidence, in this order: STATE.md, git status, diff and recent log, the files themselves, background jobs that are running or finished, open pull requests and CI. If the project uses the bundle's task controller, run its resume command first (the machine map names it). Where the notes and the files disagree, the files win; correct the notes.
2. Do not redo finished work. Reuse results whose inputs have not changed. Re-check only what an interruption can break: a half-written file, a command that was cut off, an uncommitted change, a moved folder.
3. Continue at the first unfinished step, in the order the plan gave. If the plan no longer fits what you find, say what changed and adjust it; do not restart it.
4. Load only the tools this step needs. If a required tool is broken, diagnose and repair it, or name the exact blocker. No silent downgrade and no result reported as passed that was not run.
5. Finish the work and its tests, update STATE.md, and report what is done, what was verified by running it and what remains.
```

A resume prompt cannot reconstruct a missing conversation: in a chat with no
history, give the project location, the original goal and the handoff file.

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
