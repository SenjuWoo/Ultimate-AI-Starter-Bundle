---
name: artifact-proof
description: Use when producing a ZIP, installer, executable, wheel, package, release asset, or other built deliverable.
---

# Artifact Proof

## Core rule
Source-tree tests do not prove the **built artifact**. Test what the user receives.

## Contract
After building:
1. compute checksums and record the version/source revision;
2. open or **extract** the artifact into a fresh directory;
3. verify required files and forbidden-file hygiene;
4. run the real user **entrypoint** from the extracted artifact;
5. run the artifact’s doctor/self-test;
6. verify internal manifests/checksums and version surfaces;
7. repeat critical tests against the extracted copy, not the source tree.

For archives, validate CRCs and path round-trip. For binaries, execute a version/self-test. For installers, verify install and uninstall/repair behavior when applicable.

Stage a positive runtime payload; never ZIP the source/owner directory. Mod archives contain only the mod, its required installer/config/assets and legally required licensing files. Keep `CHANGELOG.txt`/`.md`, README/development notes, `STATE.md`, plans, ownership/validation records, publication pages/audits, tests, logs and backups outside that payload. Required licence/notice files stay; use product-specific paths when possible to avoid collisions with other mods. Textures, translations, runtime INI/JSON/TXT and FOMOD assets are product files, not documentation to strip by extension.

Toolkits may ship their actual installers, diagnostics, help, skills, references and templates; these are their product. A source/developer archive is a separately labelled deliverable, never the mod installation ZIP. Validate the final entry list and manifest after exclusions; do not silently remove a file the runtime or licence needs.

## Stop condition
Do not call a release ready because compilation, linting, or repository tests passed. If the artifact itself was not opened and exercised, mark artifact behavior unverified.
