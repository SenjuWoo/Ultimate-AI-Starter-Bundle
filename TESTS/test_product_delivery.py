"""Exercise real product archives, including their boundary against source/private files."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('builder', ROOT/'TOOLS/build_release.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ProductTests(unittest.TestCase):
    def test_fanout_does_not_copy_interpreter_cache(self):
        spec = importlib.util.spec_from_file_location('fanout', ROOT/'TOOLS/fanout_providers.py')
        fanout = importlib.util.module_from_spec(spec); spec.loader.exec_module(fanout)
        with tempfile.TemporaryDirectory() as td:
            source=Path(td)/'canonical'; target=Path(td)/'provider'
            (source/'skill/__pycache__').mkdir(parents=True)
            (source/'skill/__pycache__/module.pyc').write_bytes(b'private cache')
            (source/'skill/module.py').write_text('# product')
            count,_=fanout.deploy(str(source),str(target),'codex','Codex')
            self.assertEqual(count,1)
            self.assertFalse((target/'skill/__pycache__').exists())

    def test_runtime_inventory_is_reproducible_and_excludes_development_and_unrecorded_files(self):
        with tempfile.TemporaryDirectory(prefix='Product Ω ! ') as td:
            root = Path(td)
            data = {'VERSION.txt':b'v9.0.0', 'START-HERE.bat':b'@exit /b 0',
                    'TOOLS/example.ps1':b'# runtime', 'LICENSE':b'MIT',
                    'STATE.md':b'private progress', 'CHANGELOG.txt':b'old history',
                    'TESTS/test.py':b'development', '.github/workflows/ci.yml':b'CI',
                    'COPY-TO-YOUR-WORKSPACE/_PROJECT-TEMPLATE/CHANGELOG.txt':b'template input',
                    'BUNDLED-TOOLS/OFFLINE-MANIFEST.json':b'{"assets":[]}'}
            rows=[]
            for name, content in data.items():
                target=root/name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(content)
                rows.append({'path':name,'size':len(content),'sha256':hashlib.sha256(content).hexdigest()})
            (root/'MANIFEST.json').write_text(json.dumps(rows))
            (root/'TOOLS/private.txt').write_text('unrecorded personal file')
            for core in (False,True):
                a=root/f'{core}-a.zip'; b=root/f'{core}-b.zip'
                builder.build(root,a,core); builder.build(root,b,core)
                self.assertEqual(a.read_bytes(),b.read_bytes())
                with zipfile.ZipFile(a) as archive:
                    self.assertIsNone(archive.testzip())
                    prefix=builder._prefix(root)+'/'
                    names={n.removeprefix(prefix) for n in archive.namelist()}
                    self.assertFalse({'STATE.md','CHANGELOG.txt','TESTS/test.py','.github/workflows/ci.yml','TOOLS/private.txt'} & names)
                    self.assertIn('LICENSE',names)
                    self.assertIn('COPY-TO-YOUR-WORKSPACE/_PROJECT-TEMPLATE/CHANGELOG.txt',names)
                    delivered=json.loads(archive.read(prefix+'MANIFEST.json'))
                    self.assertEqual(names,{row['path'] for row in delivered}|{'MANIFEST.json'})
                    for row in delivered:
                        self.assertEqual(row['sha256'],hashlib.sha256(archive.read(prefix+row['path'])).hexdigest())


if __name__ == '__main__':
    unittest.main()
