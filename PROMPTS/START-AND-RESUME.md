# Start or resume a task

Use one prompt once per chat. These are recommended defaults across providers,
not text the installer prepends to every message. Installed instructions already
carry the detailed rules. Put the changing task after the stable instructions;
actual cache reuse still depends on the provider.
More emphatic text does not grant tools, permissions or extra capability.

## New chat

```text
Task: [goal, target project/files if known, and what "done" looks like]

### Operating Contract
1. Selective Discovery: Inspect the project, instructions, and environment. Load only relevant skills, plugins, MCPs, and system CLIs on PATH (e.g., Python, Git, build tools); keep unrelated tools unloaded to save context.
2. Tooling & MCP Self-Healing (NO SILENT FALLBACKS): Use the proper tool or MCP for the job. If a required MCP, plugin, CLI, or skill is broken, disconnected, or missing:
   - DO NOT silently fall back to inferior local workarounds or hacky scripts.
   - Diagnose and repair the tool, config, or PATH issue first. If it requires my action, STOP and tell me how to fix it before spending tokens on the main task.
3. Future-Proof Critical Thinking (Question Stale Patterns): Do not blindly copy legacy project patterns or obey bundled skills if they are outdated, wrong, or inefficient for no good reason.
   - Verify skill instructions and existing code against current tool versions, runtime capabilities, and modern best practices.
   - If a bundled skill or touched code path is stale or over-engineered, modernize or fix it directly (while preserving my intentional personal configs, data, and preferences).
4. Smart Autonomy & Efficiency: Figure out the implementation details yourself. Ask before expensive work ONLY when consequential ambiguity or a major architectural shift changes the outcome or risk. Save usage via batching, evidence reuse, and concise output—never by weakening validation or code quality.
5. State & Verified Handoff: Maintain `STATE.md` as the live source of truth (decisions, verified evidence, remaining steps). Complete implementation, tests, and docs, then report verified results and exact remaining gaps.
```

## After a usage limit

```text
My usage limit has reset. Resume the unfinished task using `STATE.md`.

### Resume Protocol
1. Verify State & Diffs First: Read `STATE.md` and current `git status` / `git diff` where available. Cross-check the recorded handoff against actual files on disk, and validate any newer or uncommitted edits before keeping them.
2. Zero Redundant Work: Continue from the first unfinished step. Do not repeat research, reads, or checks whose inputs and environment haven't changed.
3. Tooling & Skill Integrity (NO SILENT FALLBACKS): Load only the relevant skills, plugins, MCPs, and CLIs on PATH needed for the remaining work; keep others unloaded.
   - If an MCP or tool is offline or broken after the reset, repair it first—never bypass it with manual workarounds. Stop and advise me if my input is needed.
   - If a bundled skill or existing project pattern is outdated, wrong, or needlessly inefficient, update or supersede it with the cleanest current approach while preserving my personal settings.
4. Finish & Validate: Ask only when missing context or high-risk ambiguity blocks correct work. Save usage through batching, focused output, and evidence reuse—never weaker validation. Finish implementation, tests, and `STATE.md`, then report verified results and exact remaining gaps.
```

If this is a different chat with no prior context, also provide the project
location, original goal and handoff file. A resume prompt cannot reconstruct a
missing conversation. Neither prompt grants tools or permissions, or by itself
authorizes destructive actions, costs or public publication. Keep detailed private
history out of the prefix: use dated project evidence on demand instead.
