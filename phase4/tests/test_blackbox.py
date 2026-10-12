"""Local package integrity and recorded observations, not a new VM execution."""
import base64,hashlib,json,unittest,zipfile,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'docs/evidence/phase4'; B=ROOT/'build/phase4'
def read(name):return json.loads((E/name).read_text())
def sha(data):return hashlib.sha256(data).hexdigest()
class BlackBoxTests(unittest.TestCase):
    def test_original_bundle_unchanged(self):
        hashes=read('original-hashes.json');app=B/'original/extracted/DashboardCalculator.app'
        self.assertEqual(sha((B/'original/DashboardCalculator.app.zip').read_bytes()),hashes['archive_sha256'])
        for name,r in hashes['files'].items():
            with self.subTest(path=name):self.assertEqual(sha((app/name).read_bytes()),r['sha256'])
    def test_slice_is_exact_original_byte_range(self):
        target=read('target.json');data=(B/'original/extracted/DashboardCalculator.app/Contents/MacOS/DashboardCalculator').read_bytes()
        selected=(B/'selected-arm64').read_bytes();o=target['slice_offset'];n=target['slice_size']
        self.assertEqual(selected,data[o:o+n]);self.assertEqual(sha(selected),target['arm64_sha256'])
        macho=read('macho-arm64.json');self.assertEqual(macho['header']['architecture'],'arm64')
        self.assertEqual(macho['build_versions'][0]['platform'],'macOS')
    def test_diagnostic_ipa_preserves_both_inputs(self):
        target=read('target.json')
        with zipfile.ZipFile(B/'Phase4Probe.ipa') as z:
            for name in ['original','arm64']:
                data=base64.b64decode(z.read('Payload/Phase4Probe.app/'+name+'.b64'),validate=True)
                self.assertEqual(sha(data),target[name+'_sha256'])
    def test_runtime_container_preserves_original_slice(self):
        app=ROOT/'build/phase4-runtime/Payload/MacGuest.app'
        container=app/'Frameworks/MPGuest.dylib'
        parsed=json.loads(subprocess.check_output([ROOT/'build/machprobe','inspect',container,'--json']))
        self.assertEqual(parsed['build_versions'][0]['platform'],'iOS')
        sections=[x for s in parsed['segments'] for x in s['sections'] if x['name']=='__guest']
        self.assertEqual(len(sections),2)
        sections.sort(key=lambda x:x['address'])
        self.assertEqual(sections[0]['address']+sections[0]['size'],sections[1]['address'])
        data=container.read_bytes()
        guest=b''.join(data[x['offset']:x['offset']+x['size']] for x in sections)
        self.assertEqual(guest,(B/'selected-arm64').read_bytes())
        self.assertEqual(sha(guest),read('runtime-success.json')['guest_sha256'])
        with zipfile.ZipFile(ROOT/'build/phase4-runtime/MacGuest.ipa') as z:
            self.assertEqual(z.read('Payload/MacGuest.app/Frameworks/MPGuest.dylib'),data)
    def test_extended_metadata_load(self):
        exe=B/'load-cli-test'
        subprocess.run(['xcrun','clang','-arch','arm64','-I'+str(ROOT/'runtime'),'-I'+str(ROOT/'phase4/runtime'),
            *[str(ROOT/'runtime'/n) for n in ['image.c','fixups.c','services.c','tls.c','group.c']],
            str(ROOT/'phase4/runtime/Extended.c'),str(ROOT/'phase4/host/LoadCLI.m'),
            '-framework','Foundation','-framework','AppKit','-framework','CoreFoundation','-framework','Metal','-lobjc','-o',str(exe)],check=True)
        result=subprocess.run([exe,B/'selected-arm64'],check=True,text=True,capture_output=True)
        self.assertIn('rebases=223 binds=244',result.stderr)
        self.assertIn('METADATA: registered',result.stderr)
    def test_asset_conversion_preserves_source_catalog(self):
        conversion=json.loads((ROOT/'build/phase4-runtime/asset-conversion.json').read_text())
        original=B/'original/extracted/DashboardCalculator.app/Contents/Resources/Assets.car'
        self.assertEqual(sha(original.read_bytes()),conversion['original_car_sha256'])
        self.assertGreater(conversion['asset_count'],0)
        self.assertNotEqual(sha(original.read_bytes()),sha((ROOT/'build/phase4-runtime/Payload/MacGuest.app/Assets.car').read_bytes()))
    def test_recorded_loader_failure_is_not_success(self):
        target=read('target.json')
        for name in ['mac-probe.json','ios-probe.json']:
            r=read(name);self.assertTrue(r['complete'])
            for kind,v in r['loader'].items():
                self.assertTrue(v['matches']);self.assertEqual(v['sha256'],target[kind+'_sha256'])
                self.assertFalse(v['loads']);self.assertFalse(v['entry_called']);self.assertTrue(v['error'])
            self.assertIn('class/category registration',r['loader']['arm64']['error'])
    def test_measured_platform_gap(self):
        r=read('comparison.json');rows=r['imports']
        nsimage=next(s for s in rows if 'SwiftUI.Image.init(nsImage:' in s['demangled'])
        self.assertTrue(nsimage['mac_available']);self.assertFalse(nsimage['available']);self.assertFalse(nsimage['weak'])
        for name in ['_swift_allocObject','_swift_retain','_swift_release','_swift_getWitnessTable']:
            s=next(s for s in rows if s['name']==name);self.assertTrue(s['available'])
        self.assertEqual(r['imports_total'],194);self.assertTrue(r['no_chained_fixups'])
if __name__=='__main__':unittest.main()
