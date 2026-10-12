"""Tests execute only our own hello or reject deliberately damaged copies."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[3]
LOADER=ROOT/os.environ.get('HELLO_LOADER','build/hello-loader')
HELLO=ROOT/'build/hello'

def run(path):
    return subprocess.run([str(LOADER),str(path)],capture_output=True,text=True,timeout=10)

class HelloLoaderTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=ROOT/'build')
        self.addCleanup(self.temp.cleanup)
        self.copy=Path(self.temp.name)/'hello-copy'
        shutil.copyfile(HELLO,self.copy)

    def sign(self):
        subprocess.run(['codesign','--force','--sign','-',str(self.copy)],check=True,capture_output=True)

    def image(self):
        return json.loads(subprocess.check_output([str(ROOT/'build/machprobe'),'inspect',str(HELLO),'--json'],text=True))

    def rejected(self, expected):
        p=run(self.copy)
        self.assertEqual(p.returncode,1,p.stdout+p.stderr)
        self.assertIn(expected,p.stderr)
        self.assertEqual(p.stdout,'')
        self.assertNotIn('Sanitizer',p.stderr)

    def test_fresh_signed_copy_runs_in_process_and_remains_unchanged(self):
        before=hashlib.sha256(self.copy.read_bytes()).hexdigest()
        p=run(self.copy)
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(p.stdout,'Hello from macOS ARM64\nTarget returned: 0\nMapped segments: 4; rebases: 1; binds: 2; puts calls: 1\n')
        self.assertEqual(before,hashlib.sha256(self.copy.read_bytes()).hexdigest())

    def test_bad_magic_and_truncation(self):
        for data in [b'',b'not Mach-O',bytes(32)]:
            self.copy.write_bytes(data)
            self.rejected('Loader failed')

    def test_missing_file(self):
        p=run(self.copy.parent/'absent')
        self.assertEqual(p.returncode,1)
        self.assertIn('open:',p.stderr)

    def test_wrong_platform(self):
        data=bytearray(self.copy.read_bytes())
        command=next(c for c in self.image()['load_commands'] if c['name']=='LC_BUILD_VERSION')
        struct.pack_into('<I',data,command['offset']+8,2)
        self.copy.write_bytes(data)
        self.rejected('controlled macOS hello contract')

    def test_bad_entrypoint(self):
        data=bytearray(self.copy.read_bytes())
        command=next(c for c in self.image()['load_commands'] if c['name']=='LC_MAIN')
        struct.pack_into('<Q',data,command['offset']+8,0)
        self.copy.write_bytes(data)
        self.rejected('controlled macOS hello contract')

    def test_unknown_import_is_not_called(self):
        data=bytearray(self.copy.read_bytes())
        stream=next(s for s in self.image()['linkedit'] if s.get('kind')=='lazy_bind')
        loc=data.index(b'_puts\0',stream['offset'],stream['offset']+stream['size'])
        data[loc:loc+5]=b'_nope'
        self.copy.write_bytes(data);self.sign()
        self.rejected('import outside hello whitelist')

    def test_unsupported_rebase_type(self):
        data=bytearray(self.copy.read_bytes())
        stream=next(s for s in self.image()['linkedit'] if s.get('kind')=='rebase')
        data[stream['offset']]=0x12
        self.copy.write_bytes(data);self.sign()
        self.rejected('unsupported rebase type')

    def test_other_sample_rejected(self):
        p=run(ROOT/'build/framework')
        self.assertEqual(p.returncode,1)
        self.assertIn('only libSystem fixture supported',p.stderr)
