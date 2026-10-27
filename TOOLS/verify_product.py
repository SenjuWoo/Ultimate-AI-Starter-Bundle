"""Verify an extracted product's payload and offline entrypoint without touching provider homes.

Uses the shipped manifest, skill audit and PowerShell parser. Full development
regressions run from the source checkout; installed-state checks have their own doctor.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from build_release import product_path
from verify_manifest import main as verify_manifest

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    if verify_manifest():
        return 1
    rows = json.loads((ROOT / 'MANIFEST.json').read_text(encoding='utf-8'))
    rows = rows.get('files', []) if isinstance(rows, dict) else rows
    paths = {row['path'] for row in rows}
    if any(not product_path(Path(p)) for p in paths):
        raise ValueError('Source/development file in product inventory')
    required = {'START-HERE.bat', 'INSTALL-AIO.ps1', 'TOOLS/UABS-Common.ps1',
                'TOOLS/Test-Installed-State.ps1', 'TOOLS/verify_product.py', 'LICENSE'}
    if not required <= paths:
        raise ValueError(f'Missing runtime files: {sorted(required-paths)}')
    version = (ROOT / 'VERSION.txt').read_text(encoding='utf-8-sig').strip().lstrip('vV')
    catalog = json.loads((ROOT / 'BUNDLED-TOOLS/CATALOG.json').read_text(encoding='utf-8-sig'))
    if catalog.get('pack_version') != version:
        raise ValueError('Product version/catalog mismatch')
    # Skill trees are the product; inspect their metadata using the real shipped audit.
    trees = [ROOT / '_CANONICAL-SKILLS', *(ROOT / '1-TAILORED-PROVIDER-TREES').glob('*/COPY-TO-SKILLS-DIRECTORY/skills')]
    if len(trees) != 7:
        raise ValueError('Product must contain canonical skills and all six provider trees')
    for tree in trees:
        result = subprocess.run([sys.executable, str(ROOT/'TOOLS/audit_skills.py'), str(tree)], capture_output=True, text=True)
        if result.returncode:
            raise ValueError(result.stdout + result.stderr)
    if os.name == 'nt':
        # -? is handled before the installer body, so this actual entrypoint cannot rewrite live settings.
        result = subprocess.run(['cmd.exe','/d','/c','call',str(ROOT/'START-HERE.bat'),'-?'], capture_output=True, text=True, timeout=45)
        if result.returncode:
            raise ValueError('Extracted installer help failed: '+result.stdout+result.stderr)
    print(f'PRODUCT GATE: PASS version={version} files={len(paths)} skill_trees={len(trees)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
