# Shell output compression: the bundle's RTK policy

RTK is a local CLI, not an MCP server. The catalog currently pins **0.47.0**.
Use the pack's `TOOLS/hooks/rtk_safe_hook.py` policy, not upstream's broad
rewrite hook. The installer registers the supported native adapter; other
hosts receive concise manual guidance. Do not run `rtk init` over that setup.

The safe set is standalone `git status` and human-facing pytest/cargo/go test
commands accepted by the hook's parser. Arguments matter: exact output,
machine-readable modes, shell operators and ambiguous commands pass through.
Consult the installed hook and its regression tests for the actual supported
grammar; never infer coverage from this abbreviated list.

Keep `diff`, `show`, `log`, `find`, search, file reads, `curl`, `gh`, mutating
Git, pipelines and redirection raw. Native Read/Grep/Glob tools do not pass
through a shell hook. Never filter input intended for a parser or hash check.

Earlier measurements in this repository included a 97% reduction for one
large Git diff. That was **output bytes on one corpus**, not proof that review
quality, task reliability, or billed tokens were unchanged. The corpus used
moving `HEAD~` refs, and subsequent RTK versions changed some results. Those
numbers do not justify enabling diff compression today. Compound `find` and
other non-Git cases also demonstrated correctness failures.

Inspect `rtk gain` for recorded command reductions, but compare the raw and
filtered result on a representative task before broadening the allowlist.
Check failed as well as successful commands. Preserve a route to full output
and verify the exit status. Keep RTK telemetry disabled unless requested.

The installer validates a candidate version before replacement, retains a
rollback copy, and fetches the catalog tag even in OnlineLatest mode. A newer
upstream release is a benchmark candidate, not automatic approval to change
the executable or its rewrite policy.
