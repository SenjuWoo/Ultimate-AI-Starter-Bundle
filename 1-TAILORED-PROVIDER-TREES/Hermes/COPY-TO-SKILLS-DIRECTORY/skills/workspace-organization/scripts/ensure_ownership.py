"""Create the canonical project ownership note without changing existing files or Git state.

Needs Python 3.11+. Normal output is one JSON result; --debug explains decisions
on stderr. The note is project metadata, never a runtime release payload.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

NAME = 'WORKSPACE_OWNERSHIP.md'
ALIASES = ('OWNERSHIP.md', 'PROJECT_OWNERSHIP.md')


def ensure(root: Path, *, check: bool = False) -> dict:
    # Inspect lexical ancestors before resolving links; an installed/reference root is not a source workspace.
    root = Path(os.path.abspath(root))
    if not root.is_dir():
        raise ValueError('Select an existing source project directory first.')
    for parent in (root, *root.parents):
        # The Windows reparse flag also detects junctions on Python 3.11.
        if parent.is_symlink() or getattr(parent.lstat(), 'st_file_attributes', 0) & 0x400:
            raise ValueError(f'Linked project ancestry requires explicit ownership resolution: {parent}')
        if (parent / 'SkyrimSE.exe').is_file() or (parent / 'INSTALLATION.json').is_file():
            raise ValueError(f'Installed/game inputs are read-only; select the source owner instead: {parent}')
    target = root / NAME
    # An established human record is authoritative; never rewrite it into a new schema.
    if target.exists() or target.is_symlink():
        if target.is_symlink() or not target.is_file() or not target.read_text(encoding='utf-8-sig').strip():
            raise ValueError('Existing ownership record is linked, empty or not a regular file; preserve and resolve it.')
        return {'result': 'PASS', 'created': False, 'ownership': str(target)}
    for parent in root.parents:
        if (parent / NAME).exists():
            raise ValueError(f'An ancestor already owns this project; reuse its record: {parent / NAME}')
        if (parent / '.git').exists():
            raise ValueError(f'Existing repository root is {parent}; resolve the project boundary before creating another owner.')
    if check:
        raise ValueError(f'Missing {NAME}; run ensure_ownership.py with the settled project root before editing.')
    aliases = [p for name in ALIASES if (p := root / name).is_file() and not p.is_symlink()]
    prior = '\n'.join(f'- Existing ownership evidence: `{p.name}` (read and preserve it).' for p in aliases)
    repository = 'existing repository; preserve its remote and visibility' if (root / '.git').exists() else 'local files; do not create a remote automatically'
    text = f'''# Workspace ownership

- Project root: `.` (this file's directory; one owner shared by every agent).
- Active source: `.` until existing CURRENT/version metadata identifies a snapshot.
- Versioning: preserve the established layout; Git tags for Git projects, explicit snapshots only when already appropriate.
- Repository: {repository}.
- Publication intent: local/private by default. A build or release candidate is not permission to publish.
- Explicit GitHub publication: public and MIT for original work by default, subject to rights/platform terms; preserve existing licences. Generic publication uses the appropriate destination (Nexus for Skyrim); do not create duplicate source hosting for mods needing no compilation.
- Existing-repository maintenance: preserve its remote/visibility and follow the requested update, documentation, push and release scope.
- Read-only inputs: installed products, game Data/staging/saves and supplied references.
- Release staging: separate runtime payload from source, ownership notes, STATE/PLAN/validation, changelogs, logs and backups. Keep required licences.
- Recovery: read STATE.md and version/build/run metadata before continuing; keep the last known-good artifact.
{prior}

Read the existing evidence and update the active-source/version fields before substantive edits. Do not create another owner or move files merely to match a template.
'''
    # Exclusive creation makes concurrent agents converge without replacing another agent's record.
    try:
        with target.open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(text)
    except FileExistsError:
        return ensure(root, check=True)
    return {'result': 'PASS', 'created': True, 'ownership': str(target)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project_root', type=Path)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--debug', action='store_true')
    args = parser.parse_args()
    try:
        result = ensure(args.project_root, check=args.check)
        if args.debug:
            print('Existing metadata preserved; no repository, remote or publication was created.', file=sys.stderr)
        print(json.dumps(result))
        return 0
    except (OSError, ValueError) as error:
        print(f'OWNERSHIP: FAIL: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
