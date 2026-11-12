# ADR-0008: Cheap hooks, and discovery that follows a moved folder

Status: accepted
Date: 2026-11-12

## Context

An architecture review measured where the bundle costs an agent time or gives it
a wrong answer. Four findings were large enough to need a decision.

1. Every shell call spawned four hook processes. Each one started Python, loaded
   `json`, `re`, `subprocess` and `pathlib`, and then decided the command was not
   its business. Measured on Windows with Python 3.14: 258 ms of process time per
   shell call, for hooks that act on a handful of commands a day.
2. A companion that exists twice on purpose, as the git checkout it is developed
   in and the runtime its installer produced, was reported `AMBIGUOUS`. The
   registry then gave the agent no path at all.
3. Moving a project folder left its code graph answering from the old location,
   and nothing reported it. The same move left stale entries on `PATH`.
4. A batch launcher started from a folder whose name contains `!` could not find
   its installer when delayed expansion was on, and one `cmd /c` call lost its
   quotes for a path containing parentheses.

## Options considered

- Hooks: one dispatcher per event that imports each gate as a module; or keep one
  registration per gate and make each leave before its imports.
- Source and runtime: require an explicit environment variable for every owner; or
  classify the candidates.
- Moved folders: keep a registry of previous locations; or look at what is on disk
  now.

## Decision

Hooks keep one registration per gate, and each pre-tool gate begins with a
prefilter that runs before any import beyond `os` and `sys`. The prefilter tests
the raw payload bytes, starting at the tool input, for the few substrings without
which that gate cannot act. It is a superset test: it may pass an irrelevant
payload on to the real check and never drops a relevant one, and a payload
carrying a real JSON unicode escape is always passed on. A dispatcher was
rejected: it would rewrite the per-provider wiring and its migration for every
existing install, while hosts that run hooks in parallel gain almost nothing
beyond what the prefilter already gives.

Among several folders that carry an owner's markers, the one without `.git` is
the runtime and is the copy to use; a single git checkout is reported beside it
as `source_path`. Two runtimes, or several checkouts and no runtime, stay
ambiguous. The registry still runs nothing: `--print-doctor ID --json` returns
the doctor as argv plus working directory so no shell string is built from an
owner path.

Nothing records where a folder used to be. `TOOLS/graph_roots.py` asks the graph
store which roots it has, reports the ones that are gone and names the single
same-named checkout found under the declared tool roots. The installed-state
doctor reports stale graph roots and dead `PATH` entries as warnings and repairs
neither.

Batch files disable delayed expansion, every `cmd /c` the bundle builds passes
`/v:off`, and the wired instruction text is unchanged: it is the operator's own
wording and stays byte-identical.

The forge quality bar is a reference file inside `ai-tooling-stack`, not a new
skill. A provider with a fixed skill-index budget shortens every description
when a skill is added, so knowledge that is needed for one kind of task is
loaded on demand.

## Evidence

- Pre-tool hook cost for an ordinary command, four gates, host-shaped payload:
  258 ms before, 113 ms after. The remaining time is four interpreter starts.
- `TESTS/test_audit_regressions.py`: relevant payloads still reach the real
  check, host paths outside the tool input do not trigger a gate, an escaped
  needle is not skipped, and the prefilter is identical in all four hooks.
- `TESTS/test_companion_registry.py`: checkout plus runtime resolves to the
  runtime with the source reported; two checkouts stay ambiguous; a moved source
  is found at its new path.
- `TESTS/test_awkward_paths.py` crosses real process boundaries through a folder
  named with `!`, a space, parentheses and a non-ASCII letter: `START-HERE.bat`
  under `cmd /v:on`, an MCP handshake by argv and by shell command, a PowerShell
  script and argument, and a TOML entry read back by a real parser. The delayed
  expansion case fails against the previous launcher.

## Consequences

- A new gate needs a correct needle list. A needle that is too narrow silently
  disables the gate, so each gate's self-test must include a payload that fires.
- `source_path` is a hint for development work; tools that run an owner keep
  using `path`.
- The doctor prints more warnings on a machine with history. They are
  informational and do not fail the install.

## Revisit when

- A supported host runs hooks strictly in sequence and four interpreter starts
  become visible: then the dispatcher is worth its migration.
- An owner ships a runtime that contains a `.git` directory.
- The graph store exposes a rename or re-root operation, which would let the
  doctor offer the repair instead of describing it.
