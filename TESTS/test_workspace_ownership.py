"""Exercise real ownership-file creation, preservation and refusal without touching provider homes."""
from pathlib import Path
import importlib.util
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('ownership', ROOT / '_CANONICAL-SKILLS/workspace-organization/scripts/ensure_ownership.py')
ownership = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ownership)


class OwnershipTests(unittest.TestCase):
    @unittest.skipUnless(os.name=='nt','Windows junction boundary')
    def test_linked_project_ancestry_is_never_adopted(self):
        with tempfile.TemporaryDirectory() as td:
            base=Path(td); source=base/'source'; source.mkdir(); link=base/'linked'
            env=dict(os.environ,OWNERSHIP_TEST_SOURCE=str(source),OWNERSHIP_TEST_LINK=str(link))
            subprocess.run(['powershell.exe','-NoProfile','-Command',
                '$null=New-Item -ItemType Junction -Path $env:OWNERSHIP_TEST_LINK -Target $env:OWNERSHIP_TEST_SOURCE'],
                env=env,check=True,capture_output=True)
            with self.assertRaisesRegex(ValueError,'Linked'):
                ownership.ensure(link)
            self.assertFalse((source/ownership.NAME).exists())

    def test_publication_defaults_are_explicit_and_contextual(self):
        for rel in ('workspace-organization/SKILL.md','one-shot-completion/SKILL.md',
                    'github-fleet-maintenance/SKILL.md'):
            text=(ROOT/'_CANONICAL-SKILLS'/rel).read_text(encoding='utf-8')
            for term in ('local/private','MIT','Nexus','no compilation'):
                self.assertIn(term,text,rel)
            self.assertNotIn('remote defaults to private',text)

    def test_new_project_stays_local_and_second_agent_preserves_record(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / 'main.py').write_text('personal source')
            result = ownership.ensure(root)
            self.assertTrue(result['created'])
            note = root / ownership.NAME
            before = note.read_bytes()
            self.assertIn(b'local/private by default', before)
            self.assertFalse((root / '.git').exists())
            self.assertFalse(ownership.ensure(root)['created'])
            self.assertEqual(note.read_bytes(), before)
            self.assertEqual((root / 'main.py').read_text(), 'personal source')

    def test_map_and_legacy_ownership_are_preserved_not_mistaken_for_canonical_file(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            for name in ('WORKSPACE.md', 'OWNERSHIP.md'):
                (root / name).write_text('personal record')
            ownership.ensure(root)
            self.assertIn('OWNERSHIP.md', (root / ownership.NAME).read_text())
            for name in ('WORKSPACE.md', 'OWNERSHIP.md'):
                self.assertEqual((root / name).read_text(), 'personal record')

    def test_existing_repo_record_is_preserved_and_no_child_owner_is_created(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); (root / '.git').mkdir()
            ownership.ensure(root)
            note = root / ownership.NAME
            note.write_text('Existing human ownership and release policy')
            self.assertFalse(ownership.ensure(root)['created'])
            child = root / 'src'; child.mkdir()
            with self.assertRaisesRegex(ValueError, 'already owns'):
                ownership.ensure(child)
            self.assertFalse((child / ownership.NAME).exists())
            self.assertEqual(note.read_text(), 'Existing human ownership and release policy')

    def test_check_and_read_only_realms_do_not_write(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            with self.assertRaisesRegex(ValueError, 'Missing'):
                ownership.ensure(root, check=True)
            (root / 'SkyrimSE.exe').write_bytes(b'game marker')
            with self.assertRaisesRegex(ValueError, 'read-only'):
                ownership.ensure(root)
            self.assertFalse((root / ownership.NAME).exists())

    def test_existing_independent_child_record_is_preserved(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); ownership.ensure(root)
            child = root / 'established-project'; child.mkdir()
            (child / ownership.NAME).write_text('Explicit separate project')
            self.assertFalse(ownership.ensure(child)['created'])
            self.assertEqual((child / ownership.NAME).read_text(), 'Explicit separate project')


if __name__ == '__main__':
    unittest.main()
