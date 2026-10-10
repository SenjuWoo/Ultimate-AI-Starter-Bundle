# Base Object Swapper 3.4.1 authority

Re-verified 2026-10-10 against BOS 3.5.0 (`c0b9c093aa6260fd9b68beddea411db97f585ea2`):
section names, `|` and `,` splitting and property syntax are unchanged.
Conditional filters now resolve each non-dynamic form once (faster, same
matches). BOS is GPL-3.0 from 3.5.0 (MIT before).

Current documented sections are `[Forms]`, `[References]`, `[Transforms]`, and
`[Properties]`, including qualified variants.

Property functions use contiguous comma-separated arguments, for example:

```text
rotR(-90,0,0)
posR(10.0,5.0,50.0/100.0)
```

Whitespace inside a transform invocation is a known production failure shape in
the supplied runtime log. Both the general linter and the dedicated BOS auditor
must detect it.

Alphabetical priority determines the winning config, not whether its coordinates
or conditions are semantically correct.
