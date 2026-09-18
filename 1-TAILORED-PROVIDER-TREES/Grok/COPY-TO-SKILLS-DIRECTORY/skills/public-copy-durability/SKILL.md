---
name: public-copy-durability
description: Use when writing public-facing copy that outlives a release - mod pages, store listings, README hero text, gallery captions, forum posts, release notes - so it stays true without an edit.
---

# Public copy that survives releases

Public copy splits by one question: **can an agent edit it later?**

| surface | editable later | what belongs there |
|---|---|---|
| Platform-locked pages: Nexus Mods, Steam, itch, CurseForge, forum posts, store listings, app descriptions | No - a human re-types it in a web form | Durable prose only. No version numbers, dates, counts, or "latest". |
| Agent-editable surfaces: GitHub README, CHANGELOG, docs, release bodies, wikis | Yes | Anything, including per-release facts |
| The platform's structured fields: version field, changelog section, release title | Yes, per release | The version number, once |

A locked page cannot be fixed by the agent that notices the staleness. Every volatile fact
written there is a manual edit someone will forget, a re-upload, or a wrong number aging in
public. GitHub is forgiving because an edit is one tool call; treat that as the exception, not
as permission to scatter versions everywhere.

## The rule

Write locked copy so it is still true after ten releases:

- No version numbers in the title, summary, description body, or alt text. "Version 1.4.2 fixes
  the crash" is changelog text, not description text.
- No "latest", "newest", "as of <date>", "updated <month>", file counts, tool counts, download
  sizes, or line counts. All of them rot on the next release.
- No baked version or date inside screenshots, thumbnails, or their captions: on a locked page,
  changing pixels costs a media re-upload.
- Name the thing, not the build. "The installer ships a repair mode" stays true; "the 1.4.2
  installer ships a repair mode" does not.
- Prefer stable phrasing for freshness: "current release", "recent versions".

## One volatile fact, one home

When a version genuinely must appear, put it in exactly one editable place per release - the
platform's version field plus its changelog section. Two places is one edit you may forget;
four is a page that contradicts itself.

## Where the version still goes

- The platform's structured version field and changelog section.
- Agent-editable release notes (GitHub release body, `docs/history/` entries).
- An archive or asset filename when the platform or an installer requires it.
- A dependency cell (for example "requires SKSE 2.2.6") - that names what the reader must
  install, not this project's own version.

## Before publishing

List every volatile fact in the draft, then move each one to the field that owns it. If a
sentence only makes sense for one release, it is changelog text.

Never invent a version, date, or count to fill a stability gap - leave a placeholder and say so.
The page-shape contract lives in `skyrim-nexus-publishing`; the release gate that checks the
public surface lives in `release-checklist`.
