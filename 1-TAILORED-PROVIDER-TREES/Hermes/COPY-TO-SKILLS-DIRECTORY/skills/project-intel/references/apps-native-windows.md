# Native Windows apps, extensions, packaging — settled results

## Win32 / native

- `DrawTextA` lives in **USER32**, not GDI32 — wrong import library shows as a
  load/link fault, not a compile error in dynamically-resolved cases. Verify
  the import table when a native build "runs but does nothing". (2026-09)
- A prototype is not the deliverable: "done" means the actual target artifact
  (native exe, installable package) exists and was run. (2026-09)

## PowerShell 5.1 (the host shell on Windows boxes)

- `'a' + '1', 'b' + '2'` collapses to ONE space-joined string — never build
  arrays as comma lists of concatenations. Use `$t = @()` then `$t += ...` per
  line, or explicit calls. This bug skips files silently while later appends
  still report success. (2026-10)
- `"$name:"` inside a double-quoted string interpolates as a scoped-variable
  error path — brace it: `"${name}:"`. (2026-07)
- PS 5.1 scripts that write files: keep BOM for `.ps1`/`.bat` or stay pure
  ASCII; UTF-8-no-BOM is for markdown/YAML. (stable)

## Python on Windows desktops

- App-exported `PYTHONPATH` (venv site-packages) breaks other Python installs'
  compiled deps — strip it for child processes; install with
  `env -u PYTHONPATH <python> -m pip ...` unless a venv is active. (stable)
- One interpreter per tool; do not mix 3.11/3.12 user-site packages.

## Browser extensions (Opera GX / Chromium)

- Manifest V3, minimal permissions; ship a `.crx` for one-click Chromium/Opera
  install and keep a Tampermonkey variant as fallback. (2026-09)
- When the site is Cloudflare-challenged, server-side fetch fails by design —
  drive a real installed browser (Playwright/CDP) instead of retrying fetch.
  (2026-07)

## App architecture (from real builds)

- Web/PWA first for shareability; native exe only when the user must ship a
  binary. Keep both from one codebase when possible. (2026-08)
- Data-driven apps (wardrobes, catalogs, companions): a retrieval corpus +
  cached images beats live fetching; cache invalidation and "wrong image"
  bugs are the recurring failure class. (2026-07/08)
- Ship a debug log (version at startup, resolved config, state changes,
  failures with cause) — quiet by default, toggleable. Tell the user where it
  is. (stable, also a pack rule: `observability-first`)

## Packaging / releases (apps)

- Version bump + changelog + one owner folder + restorable last-known-good
  copy. Zip the payload only (no dev scripts). (stable)
- Verify published asset bytes after upload, every time. (stable)
