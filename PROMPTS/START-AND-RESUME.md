# Start or resume a task

Use one prompt once per chat. These are recommended defaults across providers,
not text the installer prepends to every message. Installed instructions already
carry the detailed rules. Put the changing task after the stable instructions;
actual cache reuse still depends on the provider.
More emphatic text does not grant tools, permissions or extra capability.

## New chat

```text
Inspect the current project and instructions. Use relevant available skills,
plugins, MCPs and CLIs, inside or outside the workspace; keep unrelated tools
unloaded, and switch on a parked task tool for this project yourself. Tools such
as Python are installed and on PATH: use them or any other tool you need. If you
cannot find one, tell me so we can fix it properly instead of taking shortcuts
that cost more tokens to repair later. Ask before expensive work only when
ambiguity changes the outcome or risk; otherwise proceed with sensible
assumptions. Preserve personal edits and settings. Complete implementation,
tests, docs and handoff. Save usage through focused output, batching and
evidence reuse unless a better way is discovered, never weaker validation or
quality. Keep STATE.md current; report verified results and exact remaining gaps.

Task: [goal, project/files, and what success looks like].
```

## After a usage limit

```text
My usage limit has reset. Resume the unfinished task. Read STATE.md and current
Git status/diff first, where available. Verify the handoff against files and
recorded evidence; preserve newer edits after checking they are sound. Continue
from the first unfinished step without repeating research or checks whose inputs
and environment are unchanged. Use relevant available skills, plugins, MCPs and
CLIs; keep unrelated tools unloaded, and switch on a parked task tool for this
project yourself. Tools such as Python are installed and on PATH: use them or any
other tool you need. If you cannot find one, tell me so we can fix it properly
instead of taking shortcuts that cost more tokens to repair later. Ask only when
missing context or consequential ambiguity prevents correct work. Finish
implementation, validation and handoff; keep STATE.md current. Save usage through
focused output, batching and evidence reuse unless a better way is discovered,
never weaker validation or quality. Report verified results and exact gaps.
```

If this is a different chat with no prior context, also provide the project
location, original goal and handoff file. A resume prompt cannot reconstruct a
missing conversation. Neither prompt grants tools or permissions, or by itself
authorizes destructive actions, costs or public publication. Keep detailed private
history out of the prefix: use dated project evidence on demand instead.
