# ADR-0007: discovery supplies evidence; the agent owns the workflow

Status: accepted

## Context

An installed tool, a configured server and a successful call are different
states. Keyword routing also cannot establish user intent, project complexity
or authorization. Treating either as certainty causes repeated discovery,
unnecessary workflow steps and reduced creative scope.

## Decision

Keep the existing owners. `companion_registry.py` locates companion installations;
the toolbox activates task tools; native provider mechanisms own their configuration;
`task_route.py` offers workflow suggestions. None selects a model or reduces the
user's requested result. Use a relevant skill when its instructions add value,
without stacking competing methodologies for the same phase.

Companion discovery prefers a valid explicit environment root or owner receipt,
then checks bounded declared roots. It skips dependency and asset trees, shares
one directory inventory per report, and reports multiple matching owners as
ambiguous. Marker matches remain unverified until an actual operation succeeds.
Missing or ambiguous optional companions do not prevent unrelated work.

The installed-state doctor checks active MCP launch paths separately from
registration. A missing absolute executable or script disproves launchability;
an existing path does not prove connection, authentication or tool execution.
The path check covers global entries, recorded project entries and named Hermes
profiles. It examines launch fields, excluding environment values and headers.

Keep frequently loaded instructions short. Full machine inventories remain local
and can be read on demand. Exact copies of bundle-owned paragraphs may be
consolidated; distinct user rules and model choices must survive unchanged.
Two stable `UABS-PREAMBLE` comment markers delimit the managed section. Their
small fixed overhead replaces fragile matching against an ever-growing history
of full instruction text. Legacy exact copies are migrated with backups.

## Memory and recovery

`STATE.md` records task progress. `MEMORY.md` is a deterministic source index,
including hooks, companion owners and profiles. `verify_docs.py` checks it in
the local gate and CI. Regenerate with `python TOOLS/update_memory_index.py`;
restore an older file through Git history, then regenerate against that revision.
Machine maps and graph snapshots stay outside the public artifact.

For moved indexed projects, back up the existing graph store consistently,
verify source ownership and exclusions, and re-index under the same project
name. Check both the new path and a source query. Never delete first.

## Evidence

Regression tests cover moved and renamed roots, ambiguous copies, excluded
directories, creative prompts, preserved foreign hooks, profile overflow and
launch-path diagnostics. They establish these contracts, not guaranteed one-shot
success. Paid model evaluations remain opt-in. Host reload requirements and
unsupported hook surfaces must be reported precisely.

## Consequences

Mandatory keyword-selected workflows were rejected because words in a prompt
cannot establish intent or authorization. Global recursive scanning was rejected
because declared roots and owner receipts give a smaller, repeatable search.
Removing ownership markers saved a few prompt tokens but made future replacements
depend on complete historical text; short fixed markers avoid that tradeoff.

Ambiguous installations require additional owner evidence before automatic
selection. This does not block use of a verified explicit path. Prompt-hook
installation and removal must honor provider selection and check-only mode;
same-basename personal scripts are outside the bundle's ownership.

## Revisit when

A provider exposes native intent routing, owner installation receipts
change, or measured prompt behavior demonstrates a better default. Reproduce
the affected workflow before replacing these contracts.
