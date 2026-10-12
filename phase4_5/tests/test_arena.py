"""Package/ABI evidence and executable GPU checks; no substitute renderer."""
import hashlib,json,os,plistlib,subprocess,unittest,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/phase4.5';E=ROOT/'docs/evidence/phase4.5'
def inspect(path):return json.loads(subprocess.check_output([ROOT/'build/machprobe','inspect',path,'--json']))
def sha(data):return hashlib.sha256(data).hexdigest()
class ArenaTests(unittest.TestCase):
    def test_guest_is_macos_with_normal_frameworks(self):
        p=inspect(OUT/'Arena.app/Contents/MacOS/Arena')
        self.assertEqual(p['header']['architecture'],'arm64');self.assertEqual(p['build_versions'][0]['platform'],'macOS')
        names=str(p['dylibs'])
        for name in ['AppKit','MetalKit','Metal']:self.assertIn(name,names)
        self.assertNotIn('UIKit',names)
        self.assertNotIn('__objc_classlist',str(p['segments']))
    def test_unchanged_guest_inside_signed_ios_container(self):
        path=OUT/'Payload/ArenaHost.app/Frameworks/ArenaGuest.dylib';r=inspect(path);self.assertEqual(r['build_versions'][0]['platform'],'iOS')
        sections=[s for seg in r['segments'] for s in seg['sections'] if s['name']=='__guest'];sections.sort(key=lambda x:x['address']);self.assertEqual(len(sections),2)
        self.assertEqual(sections[0]['address']+sections[0]['size'],sections[1]['address'])
        b=path.read_bytes();guest=b''.join(b[s['offset']:s['offset']+s['size']] for s in sections)
        self.assertEqual(guest,(OUT/'Arena.app/Contents/MacOS/Arena').read_bytes())
        m=json.loads((OUT/'guest.json').read_text());self.assertEqual(sha(guest),m['sha256'])
        with zipfile.ZipFile(OUT/'ArenaHost.ipa') as z:self.assertEqual(z.read('Payload/ArenaHost.app/Frameworks/ArenaGuest.dylib'),b)
        subprocess.run(['codesign','--verify','--strict',OUT/'Payload/ArenaHost.app'],check=True,capture_output=True)
    def test_external_resources_identical(self):
        m=json.loads((OUT/'guest.json').read_text())
        for name,expected in m['resources'].items():
            original=(ROOT/'phase4_5/guest'/name).read_bytes()
            self.assertEqual(sha(original),expected)
            self.assertEqual(original,(OUT/'Arena.app/Contents/Resources'/name).read_bytes())
            self.assertEqual(original,(OUT/'Payload/ArenaHost.app'/name).read_bytes())
    def test_native_gpu_depth_and_texture(self):
        r=subprocess.run([OUT/'Arena.app/Contents/MacOS/Arena','--verify'],capture_output=True,text=True,check=True,env=dict(os.environ,MTL_DEBUG_LAYER='1'),timeout=30)
        result=json.loads(r.stdout);self.assertTrue(result['passed']);self.assertIn('Metal API Validation Enabled',r.stderr)
        self.assertGreater(result['depth_on_rgb'][0],result['depth_on_rgb'][2]*3)
        self.assertGreater(result['depth_off_rgb'][2],result['depth_off_rgb'][0]*3)
        self.assertGreater(result['texture_ranges'][1][1]-result['texture_ranges'][1][0],20)
    def test_recorded_ios_input_and_gpu_evidence(self):
        r=json.loads((E/'input.json').read_text());self.assertEqual(len(r['input']),3)
        move,look,pause=r['input'];self.assertLess(move['after']['camera_z'],move['before']['camera_z']-.5)
        self.assertGreater(abs(look['after']['yaw']-look['before']['yaw']),.1)
        self.assertFalse(pause['after']['spinning']);self.assertEqual(pause['after']['angle'],pause['later']['angle'])
        self.assertGreater(pause['later']['frames'],pause['after']['frames'])
    def test_recorded_sustained_and_lifetimes(self):
        r=json.loads((E/'sustained.json').read_text());g=r['guest'];self.assertGreater(g['elapsed'],180);self.assertGreater(g['frames'],2700);self.assertEqual(g['gpu_errors'],0);self.assertTrue(r['verification']['passed'])
        self.assertEqual(g['device_class'],'MTLDebugDevice')
        for k in ['library_compiles','pipeline_creations','asset_textures']:self.assertEqual(g[k],1)
        self.assertEqual(g['sync_waits'],2)
        r=json.loads((E/'reloads.json').read_text());self.assertEqual(len(r['cycles']),5)
        for c in r['cycles']:
            self.assertEqual(c['live_images_after'],0);self.assertFalse(c['bridge_after']['monitor_alive']);self.assertFalse(c['bridge_after']['surface_alive']);self.assertFalse(c['after_stop']['running']);self.assertEqual(c['after_stop']['frames'],c['after_stop']['completed'])
        fresh=json.loads((E/'relaunch.json').read_text());self.assertNotEqual(r['pid'],fresh['pid']);self.assertGreater(fresh['guest']['frames'],10)
if __name__=='__main__':unittest.main()
