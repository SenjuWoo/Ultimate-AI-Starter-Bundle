# Private preferences, public defaults

The bundle's portable working defaults and your private operator profile have
different owners. Improving one must not leak or overwrite the other.

| Content | Authoritative location | Sent on every request? |
|---|---|---|
| Shared operating rules | Bundle SOUL/AIO sources and task skills | Managed instruction layer; skills load as needed |
| Stable personal preferences and chosen roots | Your profile root's `PROFILE.md` | Yes, in one marked private block |
| Discovered game/tool paths | Generated `MACHINE-MAP.md`; detailed `GAMES.md` | Compact map only; games list on demand |
| Project-specific successes, failures, versions and next step | Project `STATE.md` and dated evidence | Read when that project needs it |

The profile root defaults to `%USERPROFILE%/.uabs/profile`; `UABS_PROFILE_ROOT`
or installer `-ProfileRoot` can redirect it. These files stay outside the public
repository. Never copy a live provider instruction file into the bundle: it can
contain the assembled private profile and machine map.

## Tune without growing context

- Record the user's explicit stable choices, not guesses about their personality.
- A lesson needs a dated observation and scope: what failed, what worked, and
  how it was verified. A model's name is not evidence.
- Prefer correcting one existing rule over stacking contradictory paragraphs.
- Keep changing versions, whole logs, chat histories and detailed inventories
  out of the always-loaded profile. Resolve actual paths before writing.
- Promote only broadly useful, verified rules into public defaults. Remove all
  personal names, machine paths, account details and credentials first.
- Never silently remove third-party/user memories or reset models, plugins,
  trust or roleplay personas while tuning a profile.

## Apply

`-ProfileTemplate autonomous-builder` seeds a missing profile; it deliberately
does not overwrite an existing one. Edit your private `PROFILE.md` directly for
personal preferences. Re-run the ownership-aware installer to refresh the marked
block; a skills-only refresh can leave tools and native settings alone:

```powershell
.\INSTALL-AIO.ps1 -SkillsOnly -SkipNativePlugins -SkipStarterSettings -SkipSelfUpdate
```

Use the installer's `-Providers` option when targeting a subset. Bundle-managed
Hermes profiles receive the same private preferences; custom roleplay profiles
retain their own persona. `-SkipProfile` leaves installed profile blocks unchanged.
An empty combined profile/map removes the block; deleting `PROFILE.md` alone
still leaves the generated machine map. Unreadable or oversized input preserves
the last installed block with a warning. The combined cap is 6,000 characters,
not a measured token count.
