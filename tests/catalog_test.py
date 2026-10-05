import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('catalog', ROOT / 'catalog.py')
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class CatalogTests(unittest.TestCase):
    def test_complete_snapshots_and_revisions(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            state = home / '.local/state/omarchy/current'
            state.mkdir(parents=True)
            (state / 'theme.name').write_text('one')
            first = home / 'first/backgrounds'
            second = home / 'second/backgrounds'
            first.mkdir(parents=True)
            second.mkdir(parents=True)
            (first / 'same.png').write_bytes(b'first')
            (second / 'same.png').write_bytes(b'other')
            (state / 'theme').symlink_to(first.parent)
            a = catalog.snapshot(home, [])
            path = a['images'][0]
            (first / 'same.png').rename(first / 'new.png')
            b = catalog.snapshot(home, [])
            self.assertEqual(len(a['images']), len(b['images']))
            self.assertNotEqual(a['images'], b['images'])
            (first / 'new.png').rename(first / 'same.png')
            (first / 'same.png').write_bytes(b'changed')
            self.assertNotEqual(a['revisions'][path], catalog.snapshot(home, [])['revisions'][path])
            (state / 'theme').unlink()
            (state / 'theme').symlink_to(second.parent)
            c = catalog.snapshot(home, [])
            self.assertEqual(a['images'], c['images'])
            self.assertNotEqual(a['revisions'][path], c['revisions'][path])
            (state / 'theme').unlink()
            self.assertEqual(catalog.snapshot(home, [])['images'], [])
            missing = str(home / 'outside.png')
            self.assertEqual(catalog.snapshot(home, [missing])['revisions'][missing], 'missing')
            Path(missing).write_bytes(b'repaired')
            self.assertNotEqual(catalog.snapshot(home, [missing])['revisions'][missing], 'missing')

    def test_user_first_sorting_and_unusual_filenames(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            state = home / '.local/state/omarchy/current'
            state.mkdir(parents=True)
            (state / 'theme.name').write_text('test')
            user = home / '.config/omarchy/backgrounds/test'
            theme = state / 'theme/backgrounds'
            for folder in (user, theme):
                folder.mkdir(parents=True)
            for name in ('z.png', 'A.png', 'space #\n.png', 'private.env', '.hidden.png', 'UPPER.PNG'):
                (user / name).touch()
            (theme / '0.png').touch()
            result = catalog.snapshot(home, [])
            self.assertEqual([Path(p).name for p in result['images']], ['A.png', 'space #\n.png', 'z.png', '0.png'])


if __name__ == '__main__':
    unittest.main()
