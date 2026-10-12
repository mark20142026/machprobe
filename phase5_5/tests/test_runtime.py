import os
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/phase5.5'
class RuntimeTests(unittest.TestCase):
    def invoke(self,path,limit):
        return subprocess.run([OUT/'load-cli',path],env=dict(os.environ,MP_IMAGE_LIMIT=str(limit)),capture_output=True,text=True,timeout=30)
    def test_keyboard_matches_native_us_layout(self):
        env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
        binary=OUT/'keyboard-test'
        subprocess.run(['xcrun','clang','-fobjc-arc','-fsanitize=address,undefined','-framework','Foundation','-framework','Carbon',ROOT/'phase5_5/runtime/Keyboard.m',ROOT/'phase5_5/tests/keyboard.m','-o',binary],env=env,check=True,capture_output=True)
        run=subprocess.run([binary],capture_output=True,text=True,timeout=30)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('1600 native US layout comparisons, 0 failures',run.stdout)
    def test_size_policy(self):
        with tempfile.NamedTemporaryFile() as f:
            f.truncate(64*1024*1024+1)
            self.assertIn('oversized',self.invoke(f.name,0).stderr)
            self.assertIn('requires thin ordinary ARM64',self.invoke(f.name,128*1024*1024).stderr)
            self.assertIn('512 MiB ceiling',self.invoke(f.name,513*1024*1024).stderr)
    def test_tls_thread_isolation_and_teardown(self):
        run=subprocess.run([OUT/'tls-test',OUT/'tls-guest'],capture_output=True,text=True,timeout=60)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('288 workers',run.stdout)
    def test_embedded_bss_gap_and_restore(self):
        guest=OUT/'tls-guest'; data=guest.read_bytes()
        parsed=json.loads(subprocess.check_output([ROOT/'build/machprobe','inspect',guest,'--json']))
        segments=[s for s in parsed['segments'] if s['name']!='__PAGEZERO']
        text=next(s['filesize'] for s in segments if s['name']=='__TEXT')
        low=min(s['vmaddr'] for s in segments)
        span=max(s['vmaddr']+s['vmsize'] for s in segments)-low
        self.assertGreater(span,len(data))
        (OUT/'test-text.bin').write_bytes(data[:text])
        (OUT/'test-data.bin').write_bytes(data[text:]+bytes(span-len(data)))
        source=OUT/'empty.s';source.write_text('.section __TEXT,__text,regular,pure_instructions\n')
        env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
        sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],env=env,text=True).strip()
        subprocess.run(['xcrun','clang','-arch','arm64','-c',source,'-o',OUT/'empty.o'],env=env,check=True,capture_output=True)
        container=OUT/'test-container.dylib'
        subprocess.run(['xcrun','ld','-dylib',OUT/'empty.o','-arch','arm64','-platform_version','macos','11.0','27.0','-syslibroot',sdk,'-lSystem','-sectcreate','__TEXT','__guest',OUT/'test-text.bin','-sectcreate','__DATA','__guest',OUT/'test-data.bin','-sectalign','__TEXT','__guest','4000','-sectalign','__DATA','__guest','4000','-o',container],env=env,check=True,capture_output=True)
        subprocess.run(['codesign','--force','--sign','-',container],check=True,capture_output=True)
        result=subprocess.run([OUT/'tls-test',guest],env=dict(env,MP_CONTAINER=str(container)),capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('12 unloads',result.stdout)
if __name__=='__main__':unittest.main()
