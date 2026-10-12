"""Black-box integrity and generic runtime tests; never load target source."""
import hashlib,json,os,subprocess,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ENV=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
class Phase5Tests(unittest.TestCase):
    def test_official_executable_and_selected_slice(self):
        manifest=json.loads((ROOT/'docs/evidence/phase5/target.json').read_text())
        original=(ROOT/'build/phase5/original/extracted/Strataris.app/Contents/MacOS/Strataris').read_bytes()
        self.assertEqual(hashlib.sha256(original).hexdigest(),'de87d9b9b61e4969ecc634803174e2dcd3007c5d9762c928992634ab1f913e61')
        selected=(ROOT/'build/phase5/selected-arm64').read_bytes()
        self.assertEqual(selected,original[1015808:1015808+951360])
        self.assertEqual(hashlib.sha256(selected).hexdigest(),manifest['arm64_sha256'])
    def test_gpu_managed_texture_translation(self):
        output=ROOT/'build/phase5/metal-test'
        subprocess.run(['xcrun','clang','-arch','arm64','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-sanitize-recover=all','-I'+str(ROOT/'phase5/runtime'),str(ROOT/'phase5/runtime/MetalCompat.m'),str(ROOT/'phase5/tests/metal.m'),'-framework','Foundation','-framework','Metal','-o',str(output)],env=ENV,check=True,capture_output=True,text=True)
        result=subprocess.run([output],check=True,capture_output=True,text=True,timeout=30)
        self.assertIn('shared GPU bytes verified',result.stdout)
