"""Validate the actual IPA and the saved VM observation, without booting a VM."""
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL_GUESTS = {'hello', 'interactive', 'file_io', 'framework', 'foundation',
          'metal_info', 'metal_compute'}
GUESTS = ORIGINAL_GUESTS | {'appkit_gui'}


class IOSPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ipa = zipfile.ZipFile(ROOT / 'build/phase3-ios/MachProbe.ipa')
        cls.prefix = 'Payload/MachProbe.app/'
        cls.manifest = json.loads(cls.ipa.read(cls.prefix + 'guests.json'))

    @classmethod
    def tearDownClass(cls):
        cls.ipa.close()

    def inspect_bytes(self, data):
        with tempfile.NamedTemporaryFile() as f:
            f.write(data)
            f.flush()
            return json.loads(subprocess.check_output([
                ROOT / 'build/machprobe', 'inspect', f.name, '--json']))

    def test_all_mac_guests_preserved_in_ipa(self):
        self.assertEqual(set(self.manifest), GUESTS)
        for name, item in self.manifest.items():
            with self.subTest(guest=name):
                data = base64.b64decode(self.ipa.read(self.prefix + name + '.b64'), validate=True)
                self.assertEqual(data, (ROOT / item['source']).read_bytes())
                self.assertEqual(len(data), item['size'])
                self.assertEqual(hashlib.sha256(data).hexdigest(), item['sha256'])
                parsed = self.inspect_bytes(data)
                self.assertEqual(parsed['build_versions'][0]['platform'], 'macOS')
                self.assertEqual(parsed['header']['architecture'], 'arm64')
                self.assertTrue(parsed['code_signing'])

    def test_no_raw_guest_macho_for_recursive_installer_to_resign(self):
        machos = []
        for name in self.ipa.namelist():
            if self.ipa.read(name)[:4] == b'\xcf\xfa\xed\xfe':
                machos.append(name)
        self.assertEqual(set(machos), {self.prefix + 'MachProbe'} |
                         {self.prefix + 'Frameworks/' + item['container']
                          for item in self.manifest.values()})

    def test_container_layout_and_original_nested_bytes(self):
        for name, item in self.manifest.items():
            with self.subTest(guest=name):
                data = self.ipa.read(self.prefix + 'Frameworks/' + item['container'])
                parsed = self.inspect_bytes(data)
                self.assertEqual(parsed['build_versions'][0]['platform'], 'iOS')
                segments = {s['name']: s for s in parsed['segments']}
                self.assertEqual(segments['__TEXT']['initprot'], 5)
                self.assertEqual(segments['__DATA']['initprot'], 3)
                text = next(s for s in segments['__TEXT']['sections'] if s['name'] == '__guest')
                tail = next(s for s in segments['__DATA']['sections'] if s['name'] == '__guest')
                self.assertEqual(text['offset'] % 16384, 0)
                self.assertEqual(text['offset'] + text['size'], tail['offset'])
                self.assertEqual(text['address'] + text['size'], tail['address'])
                self.assertEqual(text['size'] + tail['size'], item['size'])
                nested = data[text['offset']:text['offset'] + item['size']]
                self.assertEqual(nested, (ROOT / item['source']).read_bytes())
                self.assertEqual(hashlib.sha256(nested).hexdigest(), item['sha256'])

    def test_ios_host_and_signed_native_control(self):
        for name in ['MachProbe', 'hello-ios.b64']:
            data = self.ipa.read(self.prefix + name)
            if name.endswith('.b64'):
                data = base64.b64decode(data, validate=True)
            parsed = self.inspect_bytes(data)
            self.assertEqual(parsed['build_versions'][0]['platform'], 'iOS')
            self.assertEqual(parsed['build_versions'][0]['sdk'], '27.0.0')
            self.assertTrue(parsed['code_signing'])

    def test_scene_manifest(self):
        info = plistlib.loads(self.ipa.read(self.prefix + 'Info.plist'))
        scenes = info['UIApplicationSceneManifest']['UISceneConfigurations']
        self.assertEqual(scenes['UIWindowSceneSessionRoleApplication'][0]
                         ['UISceneDelegateClassName'], 'SceneDelegate')

    def test_recorded_vm_results_are_complete_and_hash_verified(self):
        # This validates saved evidence, not a new VM execution. Failure must
        # remain failure; future admitted guests must have execution assertions.
        report = json.loads((ROOT / 'docs/evidence/phase3/admission-probe.json').read_text())
        self.assertTrue(report['complete'])
        self.assertEqual(set(report['guests']), ORIGINAL_GUESTS)
        for name, result in report['guests'].items():
            self.assertEqual(result['sha256'], self.manifest[name]['sha256'])
            self.assertTrue(result['bytes_match_original'])
            if not result['loads']:
                self.assertEqual(result['stage'], 'load')
                self.assertTrue(result['error'])
                self.assertFalse(result.get('passed', False))
                self.assertFalse(result.get('input_passed', False))
            else:
                self.assertEqual(result['stage'], 'finished')
                self.assertTrue(result.get('passed', result.get('input_passed', False)))

    def test_verified_vm_evidence(self):
        # Saved observations are regression assertions, not a fresh VM run.
        report = json.loads((ROOT / 'docs/evidence/phase3/verified-run.json').read_text())
        recorded = json.loads((ROOT / 'docs/evidence/phase3/verified-guest-manifest.json').read_text())
        self.assertTrue(report['complete'])
        self.assertEqual(set(report['guests']), GUESTS)
        for name, result in report['guests'].items():
            with self.subTest(guest=name):
                self.assertTrue(result['loads'])
                self.assertEqual(result['stage'], 'finished')
                self.assertTrue(result.get('passed', result.get('input_passed', False)))
                self.assertTrue(result['embedded_bytes_match_original'])
                self.assertEqual(result['embedded_sha256'], recorded[name]['sha256'])
        gui = report['guests']['appkit_gui']
        self.assertEqual(gui['states'], [0, 1, 2, 1, 0])
        self.assertTrue(gui['metal_renderer']['passed'])
        self.assertEqual(gui['metal_renderer']['pixels_checked'], 4096)
        for audit in [report['stress'], report['stress']['resident_container_control']]:
            self.assertEqual(audit['cycles'], [True] * 20)
            self.assertEqual(audit['live_images_after'], 0)
            self.assertEqual(audit['fd_before'], audit['fd_after'])
            for case in ['duplicate', 'wrong_size', 'misaligned', 'truncated']:
                self.assertTrue(audit[case + '_rejected'])
        manual = json.loads((ROOT / 'docs/evidence/phase3/gui-manual-run.json').read_text())
        self.assertEqual(manual['gui_touch_states'][-5:], [0, 1, 2, 1, 0])


if __name__ == '__main__':
    unittest.main()
