# Project memory — the contract

Five files, one job each. An agent should be able to open this folder and know
what is true, what was decided, what already failed, and what is still a guess,
without reading the whole repository.

| File | Holds | Updated when |
|---|---|---|
| `../STATE.md` | the task: goal, done, next, evidence, version | every milestone |
| `DECISIONS.md` | durable choices with the reason they won | a choice is made or reversed |
| `KNOWN-GOOD.md` | verified working configurations, commands, versions | something is proven to work |
| `FAILED-APPROACHES.md` | what was tried and why it failed | a real attempt fails |
| `CANDIDATES.md` | unverified ideas and hypotheses | an idea is worth recording but unproven |

## Rules

1. **One home per fact.** A fact lives in one file; others link to it. Two copies
   of the same statement are how a project starts disagreeing with itself.
2. **Evidence, not vibes.** Every entry in `KNOWN-GOOD.md` carries how it was
   verified (command, test, version, date). Every entry in
   `FAILED-APPROACHES.md` says what actually broke.
3. **Candidates are labelled.** Anything in `CANDIDATES.md` is unverified. Never
   cite a candidate as if it were established.
4. **Supersede, do not sprout.** When a decision changes, edit the entry and add
   `superseded-by: <entry>` with the date. Do not leave two active opposites.
5. **Project-private stays private.** Paths, credentials and machine detail do not
   leave the project. A lesson is promoted to a shared skill only when it is
   general and contains none of that.
6. **Retrieval is selective.** Read `STATE.md` first, then the file the task needs
   (`DECISIONS.md` for "why", `KNOWN-GOOD.md` for "how it worked",
   `FAILED-APPROACHES.md` before retrying, `CANDIDATES.md` for open ideas). Do not
   paste all five into a prompt.
7. **Rebuildable.** Every entry names files by path so a moved project can be
   re-indexed by searching for the paths it mentions. There is no hidden index to
   keep in sync.
8. **Reversible.** All of this is plain text the user can edit or delete.

## Handoff

`STATE.md` ends with what the next session must know: the goal, the next action,
the evidence, and any trap that cost time. A handoff that only says "done" is not
a handoff.
