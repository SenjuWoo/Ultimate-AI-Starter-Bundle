---
name: state-resumption
description: Use when resuming interrupted, long-running, multi-session, compacted, or partially completed work, including after a usage limit or another model's changes.
---

# State Resumption

## Core rule
Do not resume from conversational memory alone. **Reconstruct** the work from repository state, **actual files**, artifacts, logs, and tests.

## Resume ledger
Maintain a tiny **ledger** with:
- goal and current acceptance criteria;
- current branch/revision and dirty files;
- completed changes with proof;
- failing/remaining gates;
- generated artifacts and exact paths;
- external state already changed;
- next smallest safe action.

On resume, verify the ledger against disk/git before trusting it. If a claimed file or build no longer exists, treat it as lost work and rebuild rather than reporting it as present.

## Usage limits and switching models

Users hit limits mid-task and continue in another app or model. Write the
ledger to the project's `STATE.md` at every milestone, not only at the end, so
the next model can resume from it. On "continue", "usage reset" or "X made
changes":

1. Read `STATE.md`, then `git status`/`git diff` (or the versioned folder's
   CHANGELOG) to see what actually changed since the ledger.
2. Treat the previous model's summary as a claim: re-run its tests or open the
   files it says it changed before building on them.
3. Do not redo research the ledger records as verified; continue from the next
   smallest safe action.
4. Reconnect tools the work needs (MCP servers, editors) before relying on them.

## Handoff for what you build

Every project you create or change keeps a `STATE.md` in its owner folder, written at each milestone, not only at the end. Facts, not narrative:

- Goal and acceptance criteria; what is done (with the proof: command, test, hash).
- Next smallest safe action and its exact command; known blockers and dead ends.
- Last good version and where its copy lives; changelog location.
- Where the debug log is and how to toggle it; build/run/test commands.
- Files you touched this session and anything left half-done.

Another model or a fresh session must be able to continue from this file plus `git status` alone. Never put secrets or personal data in it.

## Compression discipline
Before context compaction or handoff, update the ledger with facts, not narrative. Keep volatile logs out; preserve only commands, outcomes, hashes, decisions, and blockers needed to continue deterministically.
