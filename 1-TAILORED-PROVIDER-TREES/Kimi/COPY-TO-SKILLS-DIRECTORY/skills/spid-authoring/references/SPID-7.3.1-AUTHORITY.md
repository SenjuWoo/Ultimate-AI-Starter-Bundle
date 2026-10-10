# SPID 7.3.1 parser authority

Pinned source commit: `e5ef32b99ecb277778644f4deae0ac04851ca614`.

Re-verified 2026-10-10 against SPID 7.3.3 (`a6f2177eb6dc8dd48c8377e30f868854c99f629e`):
the config grammar is unchanged (one VR build-macro rename in
`LookupConfigs.cpp`). 7.3.2-7.3.3 fix outfit restore for recycled actors,
consecutive summons and templated NPCs after reload, disable on-death
distribution for summons, and fix 1.6.1130 hooks. Still MIT.

## Ordinary type names

`Form`, `Spell`, `Perk`, `Item`, `Shout`, `LevSpell`, `Package`, `Outfit`,
`Keyword`, `Faction`, `SleepOutfit`, and `Skin`.

## Pre-parsers

Before ordinary parsing, the runtime checks:

1. `ExclusiveGroup`, with `Name|FormFilters`;
2. linked keys using `[Global]Linked[Final][Death]<Type>`, with
   `Form|ParentFormFilters|IndexOrCount|Chance`;
3. on-death keys using `[Final]Death<Type>`, with the normal seven-field layout.

Therefore a flat allowlist containing only ordinary type names is incomplete.

## Field facts

- normal rows have up to seven components;
- linked rows have up to four;
- omitted trailing components are filled empty;
- TraitFilters split on `/`;
- `D` and `-D` are valid;
- deterministic Chance may end with one `!`;
- actor-level ranges need both slash endpoints;
- `Weapon` is not a distributable type key.

Offline validators must normalize the same runtime-accepted INI comment behavior
before splitting fields.
