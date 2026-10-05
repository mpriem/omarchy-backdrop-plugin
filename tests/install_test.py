import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
STUB = '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['FIXTURE'])
state = json.loads((root / 'state').read_text())
args = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
fail = os.environ.get('FAIL', '')
marker = root / 'failed'
def failure(point):
    if fail == point and not marker.exists():
        marker.touch()
        sys.exit(1)
if name == 'omarchy-plugin-validate':
    failure('validate')
    payload = pathlib.Path(args[0])
    assert not (payload / '.env').exists()
    assert not (payload / 'docs').exists()
    assert not (payload / 'tests').exists()
    json.loads((payload / 'manifest.json').read_text())
elif name == 'omarchy-shell':
    if args == ['background', 'status']:
        if fail == 'start': sys.exit(1)
        print(json.dumps({'mode': 'workspace', 'screens': [], 'images': []}))
    else:
        failure('rescan')
else:
    if args[1] == 'list':
        print(json.dumps([{'id': k, 'enabled': v} for k,v in state.items()]))
    else:
        failure(args[1])
        state[args[2]] = args[1] == 'enable'
        (root / 'state').write_text(json.dumps(state))
'''


class InstallTests(unittest.TestCase):
    def fixture(self, failure='', previous_enabled=False, invalid=False):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = base / 'source'
            source.mkdir()
            for file in ROOT.iterdir():
                if file.is_file():
                    shutil.copy2(file, source / file.name)
            (source / '.env').write_text('synthetic private file')
            (source / 'docs').mkdir()
            if invalid:
                (source / 'manifest.json').write_text('invalid')
            home = base / 'home'
            dst = home / '.config/omarchy/plugins/backgrounds'
            dst.mkdir(parents=True)
            (dst / 'previous').write_text('working install')
            initial = {'omarchy.background': not previous_enabled, 'backgrounds': previous_enabled}
            (base / 'state').write_text(json.dumps(initial))
            bins = base / 'bin'
            bins.mkdir()
            for name in ('omarchy', 'omarchy-shell', 'omarchy-plugin-validate'):
                script = bins / name
                script.write_text(STUB)
                script.chmod(0o755)
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'), FIXTURE=tmp,
                       FAIL=failure, PATH=str(bins) + ':' + os.environ['PATH'])
            result = subprocess.run(['bash', str(source / 'install.sh')], env=env, capture_output=True, text=True)
            state = json.loads((base / 'state').read_text())
            if failure or invalid:
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((dst / 'previous').read_text(), 'working install')
                self.assertEqual(state, initial, result.stdout + result.stderr)
                self.assertNotIn('installed and enabled', result.stdout)
            else:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse((dst / '.env').exists())
                self.assertFalse((dst / 'previous').exists())
                self.assertTrue((dst / 'BackgroundCatalog.qml').exists())
                self.assertEqual(state, {'omarchy.background': False, 'backgrounds': True})

    def test_success(self):
        self.fixture()

    def test_invalid_manifest(self):
        self.fixture(invalid=True)

    def test_failure_rollback(self):
        for previous in (True, False):
            for failure in ('validate', 'disable', 'rescan', 'enable', 'start'):
                with self.subTest(previous=previous, failure=failure):
                    self.fixture(failure, previous)


if __name__ == '__main__':
    unittest.main()
