# Creative direction templates

Copy into the project's owner folder. Keep each under a page; a contract nobody reads
is worse than none.

## Vision Contract

```
Project / codename:
Core fantasy (one sentence, operator's words):
Audience and platform:
Experience (what the player/user feels and does):
Visual direction:
Audio direction:
References (links or local paths):
Required systems and relationships:
Hard constraints (must not change):
Explicit preferences:
Rejected ideas / corrections (dated):
Creative freedom (where the AI may decide):
Current approved direction:
```

## Feature ledger

```
ID      Requirement            Depends on   Priority   Status        Acceptance test            Evidence
F-001   core movement loop     -            must       done          run 60 s, no fall-through  clip + log
F-002   first enemy            F-001        must       building      spawn, chase, hit reacts   pending
F-003   save and reload        F-001        should     todo          save -> quit -> reload     pending
```

Status values only: todo / building / done / blocked. `done` requires evidence.

## Vertical slice brief

```
Slice name:
Proves (vision element):
Playable in __ minutes:
Systems included:
Explicitly excluded (until slice passes):
Quality bar: frame budget, look, feel, audio
Verification: screenshot, playtest script, benchmark
```

## Decision note

```
Decision:
Context:
Options considered:
Chosen because:
What would change our mind:
```
