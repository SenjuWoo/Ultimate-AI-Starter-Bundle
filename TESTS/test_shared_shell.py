"""Exercise the shipped Hermes shell-config merge against real YAML and disposable files.
Requires PyYAML; preserves unknown settings and proves retry and malformed-input behavior.
"""
import copy
import os
import re
import sys
import tempfile
import types
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'TOOLS/Set-HermesSharedPython.ps1').read_text('utf-8-sig')
match = re.search(r"  \$code = '(.+?)'\n  Invoke-UabsHermesPython", source, re.S)
assert match, 'Shipped config merger was not found'
merge = compile(match.group(1).replace("''", "'"), 'shipped shared-shell merger', 'exec')
keys = ('HERMES_HOME', 'UABS_SHARED_SHELL', 'UABS_SHARED_BACKUP')
saved = {k: os.environ.get(k) for k in keys}
previous_module = sys.modules.get('hermes_constants')
try:
    with tempfile.TemporaryDirectory(prefix='uabs shared shell ') as tmp:
        root = Path(tmp)
        os.environ.update(HERMES_HOME=str(root), UABS_SHARED_SHELL=str(root/'shared.sh'), UABS_SHARED_BACKUP=str(root/'backups'))
        constants = types.ModuleType('hermes_constants')
        constants.get_default_hermes_root = lambda: root
        sys.modules['hermes_constants'] = constants
        originals = {}
        for folder in (root, root/'profiles/custom'):
            folder.mkdir(parents=True, exist_ok=True)
            data = {'model': {'default': 'owner-choice'}, 'unknown': {'values': [1, False, None]},
                    'terminal': {'shell_init_files': ['owner-init.sh'], 'custom': 'keep'}}
            target = folder/'config.yaml'
            target.write_text(yaml.safe_dump(data, sort_keys=False), 'utf-8')
            originals[target] = copy.deepcopy(data)
        exec(merge, {})
        first = {p: p.read_bytes() for p in originals}
        for target, original in originals.items():
            actual = yaml.safe_load(target.read_bytes())
            assert actual['terminal']['shell_init_files'].pop() == os.environ['UABS_SHARED_SHELL']
            assert actual == original, 'Unrelated YAML values changed'
        assert len(list((root/'backups').glob('*.yaml'))) == 2
        exec(merge, {})
        assert all(p.read_bytes() == data for p, data in first.items()), 'Retry changed config bytes'
        bad = root/'profiles/malformed/config.yaml'
        bad.parent.mkdir(parents=True)
        bad.write_bytes(b'terminal: []\n')
        try:
            exec(merge, {})
            raise AssertionError('Malformed terminal config was accepted')
        except RuntimeError as exc:
            assert 'not a mapping' in str(exc)
        assert bad.read_bytes() == b'terminal: []\n'
finally:
    for key, value in saved.items():
        if value is None: os.environ.pop(key, None)
        else: os.environ[key] = value
    if previous_module is None: sys.modules.pop('hermes_constants', None)
    else: sys.modules['hermes_constants'] = previous_module
print('SHARED SHELL CONFIG GATE: PASS')
