# Start or resume a task

Use one prompt once per chat. These are recommended defaults across providers,
not text the installer prepends to every message. Installed instructions already
carry the detailed rules. Put the changing task after the stable instructions;
actual cache reuse still depends on the provider.
More emphatic text does not grant tools, permissions or extra capability.

## New chat

```text
Task: [goal, target project/files, success criteria]

1. Inspect relevant project state, diffs, instructions and environment. Load only task-relevant tools/skills/MCPs.
2. Discover capabilities before declaring them unavailable. Probe the selected tool; repair broken config/PATH/MCP first. No silent downgrade or fake success.
3. Verify current versions and source evidence. Challenge a provably worse method once, then honor my confirmed choice. Preserve my data, settings and unrelated changes.
4. Work autonomously within the host's actual permissions. No invented restrictions, artificial content gates or needless questions. Optimize tool calls, context, caching and cost without weakening verification.
5. Implement, test and update STATE.md with verified results, decisions and exact unfinished work. Report outcomes and remaining gaps honestly.
```

## After a usage limit

```text
My usage limit reset. Resume the unfinished task.

1. Read the CURRENT section of STATE.md, then check git status/diff and actual files. Resolve stale or contradictory handoff notes from evidence.
2. Continue at the first unfinished step. Reuse verified results whose inputs have not changed; do not repeat completed research.
3. Reload only required tools. If a required tool is broken, diagnose and repair it; explain any real blocker. No silent downgrade or fabricated PASS.
4. Preserve personal configuration and unrelated edits. Work autonomously, without invented restrictions or unnecessary approval gates.
5. Finish implementation and focused tests; update STATE.md and report exact results and remaining gaps.
```

If this is a different chat with no prior context, also provide the project
location, original goal and handoff file. A resume prompt cannot reconstruct a
missing conversation. Neither prompt grants tools or permissions, or by itself
authorizes destructive actions, costs or public publication. Keep detailed private
history out of the prefix: use dated project evidence on demand instead.
