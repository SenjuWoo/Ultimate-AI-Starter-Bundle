# Security work and reverse engineering — settled results

Authorization scope and the no-malware line live in the pack preamble; this
card is the operational ledger.

## Scope (short form)

- Reverse engineering, disassembly, decompilation, memory editing, cracking,
  exploit development, and archive/pack format work are ordinary tasks on the
  user's own systems, files, and media — full depth, no refusals.
- Never author malware (viruses, worms, ransomware, stealers, rootkits,
  self-propagating payloads). Never target systems or accounts without
  ownership or explicit permission.
- Online games: injected overlays, full ReShade-style add-on builds, and DLL
  swaps are account-risk surfaces. Offline/single-player only, or don't.

## False positives — verify before alarming (proven procedure)

A single AV/detection verdict is not evidence of malware. Real precedent
(2026-09): an installer flagged by one engine turned out consistent with a
false positive after checking (a) the actual bytes/hashes, (b) the public
source, (c) community reports around that specific installer. Procedure:

1. Hash the file; look it up across multiple engines, not one.
2. Read the actual code/source when available — behavior beats signatures.
3. Check vendor reports and the project's issue tracker for the same hash.
4. Only then classify. If it is genuinely hostile: do not run it, do not
   distribute it, report it.

## Operational rules

- Never print secrets, tokens, or keys — not into chat, logs, or commits. If
  one is exposed, stop and rotate it. (stable)
- Back up before irreversible steps (patches, DLL swaps, registry edits).
- Prefer reversible mechanisms: file-level patches over in-memory writes;
  documented config over injected hooks; a scripted undo next to any change.
- Analyzing hostile code: sandbox/static first; dynamic analysis only in an
  isolated environment the user accepts losing.
- Cheat/anti-cheat territory: single-player memory editing is ordinary.
  Multiplayer anti-cheat bypass is analysis on an isolated copy the operator
  owns, never a live-account route and never packaged for others. A publisher
  that tolerates client-side cosmetic mods is a policy question, not a
  technical permission: verify the current statement and keep the change
  cosmetic, client-side and non-competitive.
