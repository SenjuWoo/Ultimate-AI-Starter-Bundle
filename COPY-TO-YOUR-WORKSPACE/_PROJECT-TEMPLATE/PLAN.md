# Plan

Goal: one sentence describing the finished result.

Statuses: `pending`, `active`, `complete`, `failed`, `blocked`, `superseded`.
`Depends on` takes task IDs separated by commas, or `-`. `Verify` is the command
(or file) that proves the task is done; `Evidence` names what it produced.

| ID | Task | Status | Depends on | Verify | Evidence |
|---|---|---|---|---|---|
| T1 | Read the project rules and the current state | complete | - | `STATE.md` | - |
| T2 | Describe the first real deliverable | pending | T1 | - | - |

## Deferred

Work that is explicitly out of scope for now, with the reason. Nothing here is
counted as pending.
