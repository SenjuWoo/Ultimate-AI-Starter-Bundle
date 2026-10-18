---
name: scratch-hygiene
description: Use when creating temporary files, scripts or folders, or when finishing a task or version whose byproducts are still on disk. Scratch lives in temp and dies at done.
---

# Scratch hygiene

Temporary work is not a delivery. Every scratch item has a lifetime, and a task
is not finished while its byproducts are still on disk.

## Where scratch goes

- Scratch lives under the operating system's temp directory, in one folder per
  task (`%LOCALAPPDATA%\Temp\<task>` on Windows, `$TMPDIR/<task>` elsewhere) -
  never inside the repository, the workspace root, or the user profile root.
- Name the folder after the task so a later sweep can tell whose it is and
  whether anything still needs it.
- A script that turned out reusable is no longer scratch: move it into the
  project's `tools/` or the skill's `scripts/`, delete the temp copy, and say
  where it went.
- Review payloads, extracted archives and copied checkouts belong in the temp
  folder of the task that needed them, not in the project tree.

## Cleanup is part of done

Before reporting a task, version or release finished:

- delete the temp folder created for it - scripts, downloads, extractions,
  generated comparison data;
- delete superseded backups (`.bak`, `.old`, dated copies): keep the newest
  one, not the pile;
- confirm build outputs sit where the workspace expects them
  (`workspace-organization`), not next to the source;
- report what was removed. Deleting anything you did not create needs a
  question first.

## Bloat sweep

When a workspace, repository or backup drive grows without explanation, check
the usual suspects before recommending hardware: stale staging folders,
duplicate extracted archives, orphaned caches, superseded backups, and build
directories that restart from zero every time. Every verdict is "keep the
newest, remove the rest", reported with the count and the bytes reclaimed.

A version bump is the natural moment: the previous version's scratch, staging
and superseded backups are exactly what should not survive into the next
release.
