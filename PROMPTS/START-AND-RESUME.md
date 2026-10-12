# Start or resume a task

Use one prompt, then describe the actual task. These work across providers;
the installed instructions already carry the detailed operating rules.
More emphatic text does not grant tools, permissions or extra capability.

## New chat

```text
Task: [what you want done, project/files, and what a successful result looks like].

Inspect the current project and relevant instructions first. Use the available
skills, plugins, MCPs and CLIs that materially improve this task; keep unrelated
capabilities unloaded. Before expensive work, ask a concise question if an
unresolved ambiguity would materially change the result. Otherwise make
reasonable assumptions and proceed.

Complete the work and its relevant tests, docs and handoff. Preserve personal
edits and settings. Save tokens by reusing verified evidence, batching independent
checks and keeping output focused, not by skipping validation or lowering quality.
Keep STATE.md current for handoffs. Finish with verified results and any remaining
blockers; never claim an unperformed check passed.
```

## After a usage limit

```text
My usage limit has reset. Resume the unfinished task from this chat. Read the
project's STATE.md and current Git status/diff first, if available; verify the
previous agent's claims against the files and recorded results. Preserve newer
edits and continue from the first unfinished step without repeating completed
research or passing checks whose inputs have not changed.

Use only the relevant available skills, plugins, MCPs and CLIs. Ask a concise
question only if missing context or a consequential ambiguity prevents correct
work. Otherwise finish the task, its validation and handoff; keep STATE.md current.
Save tokens through focused output and evidence reuse, not reduced quality.
Report verified results and exact remaining gaps.
```

If this is a different chat with no prior context, also provide the project
location, original goal and handoff file. A resume prompt cannot reconstruct a
missing conversation. Neither prompt overrides provider permissions or supplies
authorization for destructive actions, costs or public publication.
