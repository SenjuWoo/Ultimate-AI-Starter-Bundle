# KID 4.0.6 parser authority

Pinned source commit: `895df224d4964dc9723460038eb533bfff06d860`.

Re-verified 2026-10-10 against KID 4.1.0 (`99adaaa1d8cefe320524802b57e91723f66b1c7c`):
the row grammar, type lookup, `|` sections, `,`/`+` filter separators and
chance parsing are unchanged (regex library and CommonLib refactor only).
Behaviour differences: chance rolls use a new RNG, so which items a percentage
row picks can differ from 4.0.x; the MGEF trait also reads a book's spell and
an armor/weapon enchantment. KID is GPL-3.0 from 4.1.0 (MIT before).

An ordinary row is split into:

```text
Keyword target | Type | Filters | Traits | Chance
```

The parser reads only present positions, but it returns without registering the
row when `Type` remains `kNone`. `GetType` performs an exact lookup against the
human-readable type array. Consequently:

```text
Weapon       valid
Magic Effect valid
WEAP         invalid ordinary type
MGEF         invalid ordinary type
blank field  invalid ordinary type
```

KID `ExclusiveGroup` is a separate key with `GroupName|KeywordFormFilters`; it
must not be forced through ordinary Keyword-row validation.
