#!/usr/bin/env python3
"""Check distribution validation against real, deliberately damaged app bundles."""
import os, pathlib, plistlib, shutil, subprocess, tempfile, unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
class ReleaseValidation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.app = pathlib.Path(self.tmp.name) / 'TidyFolder.app'
        shutil.copytree(ROOT / 'dist/TidyFolder.app', self.app)
        self.env = dict(os.environ, EXPECTED_ARCH=os.environ.get('EXPECTED_ARCH', 'arm64'), EXPECTED_VERSION='0.1.1', SIGNING_MODE='ad-hoc')
    def tearDown(self): self.tmp.cleanup()
    def run_check(self):
        return subprocess.run([str(ROOT / 'scripts/verify-release.sh'), str(self.app)], env=self.env, capture_output=True, text=True)
    def rejected(self, message):
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stdout + result.stderr)
    def plist(self, key, value):
        path = self.app / 'Contents/Info.plist'
        data = plistlib.loads(path.read_bytes()); data[key] = value
        path.write_bytes(plistlib.dumps(data))
    def test_valid_bundle(self): self.assertEqual(self.run_check().returncode, 0)
    def test_missing_executable(self):
        (self.app / 'Contents/MacOS/TidyFolder').unlink(); self.rejected('executable')
    def test_missing_icon(self):
        (self.app / "Contents/Resources/AppIcon.icns").unlink(missing_ok=True); self.rejected("icon")
    def test_missing_localization(self):
        shutil.rmtree(self.app / 'Contents/Resources/ru.lproj'); self.rejected('localization')
    def test_wrong_identifier(self): self.plist('CFBundleIdentifier', 'wrong'); self.rejected('identifier')
    def test_wrong_version(self): self.plist('CFBundleShortVersionString', '9.9.9'); self.rejected('version')
    def test_wrong_minimum(self): self.plist('LSMinimumSystemVersion', '15.0'); self.rejected('minimum')
    def test_wrong_architecture(self):
        self.env['EXPECTED_ARCH'] = 'ppc'; self.rejected('architecture')
    def test_invalid_signature(self):
        with (self.app / 'Contents/MacOS/TidyFolder').open('ab') as f: f.write(b'damage')
        self.rejected('signature')
    def test_signed_mode_requires_credentials(self):
        env = dict(self.env, SIGNING_MODE='developer-id'); env.pop('SIGNING_IDENTITY', None)
        result = subprocess.run([str(ROOT/'scripts/build-app.sh'), 'arm64'],env=env,capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0); self.assertIn('SIGNING_IDENTITY',result.stdout+result.stderr)

if __name__ == '__main__': unittest.main()
