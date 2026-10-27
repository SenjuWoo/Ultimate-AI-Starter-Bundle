# Versioned workspace and rollback

## Ownership before the first edit; snapshots only for snapshot-based projects

Read/create WORKSPACE_OWNERSHIP.md through workspace-organization before substantive writes. Preserve the established owner and source layout across agents. Existing Git projects use commits/tags and their normal build directories; do not clone them into nested version folders. New work stays local until requested publication.

For an established snapshot-based project, every update creates a new sibling folder by fully copying the current snapshot. The following layout and snapshot scripts apply only to that workflow.

```text
<OwnerRoot>\<Mod Name>\
├── CHANGELOG.md
├── CURRENT.txt
├── WORKSPACE_OWNERSHIP.md
├── <Mod Name> 1.0.0\
│   └── VERSION.md
├── <Mod Name> 1.0.1\
│   └── VERSION.md
└── <Mod Name> 1.1.0\
    └── VERSION.md
```

Before changing a file:

1. Read `CURRENT.txt`, `CHANGELOG.md`, and `WORKSPACE_OWNERSHIP.md`.
2. Choose the semantic bump: patch, minor, or major.
3. Fully duplicate the current snapshot into the new version folder.
4. Update `CURRENT.txt`.
5. Create or update the new snapshot's `VERSION.md`.
6. Start the new changelog entry with the AI application, model, reasoning mode, task, parent version, and intended files.
7. Edit only the new version.
8. Never mark a partial or failed copy as current.

The previous version remains untouched for rollback and binary comparison.


## Completion report

```text
VERSION GATE
project=...
owner=...
parent=...
active=...
bump=patch|minor|major
copied_files=...
changelog_started=YES|NO
version_record=YES|NO
previous_snapshot_untouched=YES|NO
RESULT=PASS|FAIL
```

For snapshot-based projects only, use this reference folder's `new_version.py` to create the snapshot and `validate_project.py` to verify it. Keep changelogs, ownership and progress records outside runtime mod ZIPs; preserve required licences.
