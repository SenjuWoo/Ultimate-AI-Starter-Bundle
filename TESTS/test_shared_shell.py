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
        # Hermes's interpreter has hermes_yaml and no PyYAML. This path must
        # append the shell file without requiring the PyYAML module.
        import builtins
        real_yaml = yaml
        saved_yaml_module = sys.modules.pop('yaml', None)
        saved_hermes_module = sys.modules.get('hermes_yaml')
        class Editor:
            def load(self, text):
                return real_yaml.safe_load(text)
            def dump(self, data, stream):
                stream.write(real_yaml.safe_dump(data, allow_unicode=True, sort_keys=False))
        class HermesYaml:
            def __init__(self):
                self.roundtrips = 0
            def roundtrip_yaml(self):
                self.roundtrips += 1
                return Editor()
            def safe_load(self, stream):
                return real_yaml.safe_load(stream)
        fake_yaml = HermesYaml()
        sys.modules['hermes_yaml'] = fake_yaml
        real_import = builtins.__import__
        def block_yaml(name, globals=None, locals=None, fromlist=(), level=0):
            if name == 'yaml' or (isinstance(name, str) and name.startswith('yaml.')):
                raise ModuleNotFoundError("No module named 'yaml'")
            return real_import(name, globals, locals, fromlist, level)
        builtins.__import__ = block_yaml
        try:
            os.environ['HERMES_HOME'] = str(root/'fallback-home')
            fb_root = Path(os.environ['HERMES_HOME'])
            fb_originals = {}
            for folder in (fb_root, fb_root/'profiles/custom'):
                folder.mkdir(parents=True, exist_ok=True)
                data = {'model': {'default': 'owner-choice'}, 'unknown': {'values': [1, False, None]},
                        'terminal': {'shell_init_files': ['owner-init.sh'], 'custom': 'keep'}}
                target = folder/'config.yaml'
                target.write_text(yaml.safe_dump(data, sort_keys=False), 'utf-8')
                fb_originals[target] = copy.deepcopy(data)
            exec(merge, {})
            assert fake_yaml.roundtrips == 2, 'Hermes YAML round-trip writer was not used'
            fb_first = {p: p.read_bytes() for p in fb_originals}
            for target, original in fb_originals.items():
                actual = yaml.safe_load(target.read_bytes())
                assert actual['terminal']['shell_init_files'].pop() == os.environ['UABS_SHARED_SHELL']
                assert actual == original, 'Hermes YAML fallback changed unrelated values'
            exec(merge, {})
            assert all(p.read_bytes() == data for p, data in fb_first.items()), 'Hermes YAML retry changed config bytes'
            fb_bad = fb_root/'profiles/malformed/config.yaml'
            fb_bad.parent.mkdir(parents=True)
            fb_bad.write_bytes(b'terminal: []\n')
            try:
                exec(merge, {})
                raise AssertionError('Malformed terminal config was accepted by the Hermes YAML path')
            except RuntimeError as exc:
                assert 'not a mapping' in str(exc)
            assert fb_bad.read_bytes() == b'terminal: []\n'
        finally:
            builtins.__import__ = real_import
            if saved_yaml_module is None:
                sys.modules.pop('yaml', None)
            else:
                sys.modules['yaml'] = saved_yaml_module
            if saved_hermes_module is None:
                sys.modules.pop('hermes_yaml', None)
            else:
                sys.modules['hermes_yaml'] = saved_hermes_module
finally:
    for key, value in saved.items():
        if value is None: os.environ.pop(key, None)
        else: os.environ[key] = value
    if previous_module is None: sys.modules.pop('hermes_constants', None)
    else: sys.modules['hermes_constants'] = previous_module
print('SHARED SHELL CONFIG GATE: PASS')
