# Nexus / release operations — settled results

## Proven

- **Nexus public API has a hard quota**; hitting it returns an explicit quota
  message, not a generic 429. Bulk tooling must treat quota exhaustion as a
  normal state, back off, and never retry-loop. (2026-07)
- **Durable archive-download route**: official Nexus API + browser extension
  (Manifest V3, `.crx` for Chromium/Opera GX) beats scraping; a
  Tampermonkey variant is the fallback for non-Chromium browsers. (2026-09)
- **Descriptions workflow:** short description + BBCode big description,
  written from the *actual current package contents* — check the shipped
  version and file list first; wrong version numbers in descriptions are the
  most common self-inflicted error. (2026-07, multiple)
- **Mod "not working" reports after an update:** verify the uploaded archive
  itself (FOMOD validity, file count, record types) before debugging the game.
  Installer-side faults masquerade as gameplay bugs. (2026-07)
- **Takedown/relations protocol:** fix the cause, re-check permissions, reply
  factually. Never organize or draft harassment of a reporter or another
  author — it converts a TOS problem into a worse one. (2026-08)
- Legitimate maintenance forks: keep the original credit, state the scope, and
  ship the fix upstream-shaped; "keep it, but do not leave it stale" is the
  right posture. (2026-07)

## Dead ends / traps

- Redistributing other authors' assets (even as dependencies in a pack) gets
  the release removed. Ship only your own work or explicit-permission
  dependencies. (2026-08)
- Do not write descriptions or announcements from memory of an older build;
  open the package. (2026-07)
- Scraping Nexus pages instead of using API/extension tooling breaks on every
  layout change. (2026-09)
