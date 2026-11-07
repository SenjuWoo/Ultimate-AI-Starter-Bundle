# Hermes file guard: reproduced defect (2026-11-07)

Not a bundle component. `write_file`/`patch` staleness lives in the Hermes app at
`%LOCALAPPDATA%\hermes\hermes-agent\tools\file_state.py` and
`...\tools\file_tools.py`; the bundle ships none of it and cannot enforce it for
other writers.

## Repro

1. Create a 4-line file; `read_file` with `offset=2, limit=2` (returns lines 2-3,
   `truncated: true`).
2. `read_file` with `offset=4` (returns line 4, `truncated: false`). Together the
   two reads cover the file.
3. `write_file` with a full document -> refused: "was last read with offset/limit
   pagination (partial view). Read the remaining pages".
4. Read the whole file again from line 1 (`offset` default, nothing truncated).
5. `write_file` -> still refused with the same message.

## Cause

`_record_successful_read()` (`tools/file_tools.py`, ~line 533) only computes
coverage inside `if stable and version is not None and count < 4:`. Once the dedup
counter has seen a region four times, `complete` stays `False` for a read that is
plainly complete (offset 1, nothing truncated or redacted), so
`file_state.record_read(partial=True)` is stamped and the guard refuses forever.
The message tells the model to read the remaining pages, but the pages are already
read and re-reading cannot clear the stamp.

A windowed read that ends at EOF also fails to merge when that dedup branch is
skipped, which breaks the legitimate "one file, several pages" case.

## One-line fix (upstream)

In `_record_successful_read()`, before the dedup block:

```python
    if offset <= 1 and not partial and not redacted:
        complete = True
```

A full read always blesses the overwrite; partial and redacted reads keep
refusing exactly as today.

## Why it is not patched here

The app has no test interpreter in this checkout (`psutil` and friends are not
importable from the shared Python), so a source edit could not be validated
against its own suite. A patch was applied to the installed copy, the suite could
not run, and it was reverted byte-for-byte. A vendor update would overwrite it
anyway.

## What an agent must do meanwhile

Satisfy the guard - `patch` for small edits, or a full read for a rewrite - and
never force the write through `terminal`, `execute_code` or another tool. That
rule is now in the shared contract (WRITE REFUSALS ARE INFORMATION).
