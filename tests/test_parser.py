"""Independently encoded fixtures exercise structures absent from tiny real binaries.
These are parser inputs, not runnable binaries or evidence of platform acceptance.
"""
import json
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = (ROOT / os.environ.get('MACHPROBE', 'build/machprobe')).resolve()
ARM64 = 0x0100000C

def pack(fmt, *args):
    return struct.pack('<' + fmt, *args)

def command(kind, body=b''):
    size = (8 + len(body) + 7) & ~7
    return pack('II', kind, size) + body + bytes(size - 8 - len(body))

def macho(commands=(), payload=b'', subtype=0, filetype=2):
    cmds = b''.join(commands)
    return pack('8I', 0xFEEDFACF, ARM64, subtype, filetype, len(commands), len(cmds), 0, 0) + cmds + payload

def dylib(name, kind=0xC):
    return command(kind, pack('4I', 24, 0, 0x10000, 0x10000) + os.fsencode(name) + b'\0')

def rpath(name):
    return command(0x8000001C, pack('I', 12) + os.fsencode(name) + b'\0')

def export_image(trie, legacy=False):
    if legacy:
        return macho([command(0x80000022, pack('10I', 0,0,0,0,0,0,0,0,80,len(trie)))], trie)
    return macho([command(0x80000033, pack('II', 48, len(trie)))], trie)

class ParserTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / 'build')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def invoke(self, data, ok=True, mode='inspect', args=()):
        path = self.directory / 'fixture'
        path.write_bytes(data)
        p = subprocess.run([str(TOOL), mode, str(path), '--json', *args], capture_output=True, text=True, timeout=15)
        self.assertEqual(p.returncode, 0 if ok else 1, p.stderr + p.stdout)
        self.assertNotIn('Sanitizer', p.stderr)
        result = json.loads(p.stdout)
        if not ok:
            self.assertIn('error', result)
        return result

    def test_build_versions_and_unknown_commands(self):
        commands = [command(0x32, pack('6I', 2, 0x100200, 0x110100, 1, 3, 0x12345)),
                    command(0x80000077), command(0x1B, bytes(range(16)))]
        r = self.invoke(macho(commands))
        self.assertEqual(r['build_versions'][0]['platform'], 'iOS')
        self.assertEqual(r['build_versions'][0]['minimum_os'], '16.2.0')
        self.assertEqual(r['build_versions'][0]['tools'][0]['tool'], 3)
        self.assertEqual(r['load_commands'][1]['name'], 'UNKNOWN')
        self.assertTrue(r['load_commands'][1]['required_by_dyld'])
        self.assertEqual(r['uuids'], ['00010203-0405-0607-0809-0a0b0c0d0e0f'])

    def test_legacy_platforms(self):
        for cmd, platform in [(0x24, 'macOS'), (0x25, 'iOS'), (0x2F, 'tvOS'), (0x30, 'watchOS')]:
            with self.subTest(cmd=cmd):
                r = self.invoke(macho([command(cmd, pack('II', 0xB0102, 0xC0304))]))
                self.assertEqual(r['build_versions'][0]['platform'], platform)
                self.assertEqual(r['build_versions'][0]['minimum_os'], '11.1.2')
                self.assertEqual(r['build_versions'][0]['sdk'], '12.3.4')

    def test_dylib_variants_and_rpath(self):
        kinds = [0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20, 0xD]
        r = self.invoke(macho([dylib('/fixture/lib.dylib', k) for k in kinds] + [rpath('@loader_path/lib')]))
        self.assertEqual(len(r['dylibs']), 6)
        self.assertEqual(r['rpaths'], ['@loader_path/lib'])
        self.assertEqual(r['dylibs'][1]['kind'], 'LC_LOAD_WEAK_DYLIB')
        self.assertEqual(self.invoke(macho())['rpaths'], [])

    def test_signing_encryption_and_fixup_ranges(self):
        cmds = [command(0x1D, pack('II', 120, 4)), command(0x2B, pack('II', 124, 4)),
                command(0x2C, pack('4I', 128, 4, 1, 0)), command(0x80000034, pack('II', 132, 4))]
        # Four commands total 72 bytes, placing data immediately after the 104-byte header area.
        data = macho(cmds, bytes(32))
        r = self.invoke(data)
        self.assertEqual(len(r['code_signing']), 2)
        self.assertTrue(r['encryption'][0]['encrypted'])
        self.assertEqual(r['encryption'][0]['cryptid'], 1)
        self.assertEqual(r['linkedit'][-1]['command'], 'LC_DYLD_CHAINED_FIXUPS')
        self.assertEqual(self.invoke(macho())['encryption'], [])
        self.invoke(data[:-1], ok=False)

    def test_thread_entry(self):
        state = [0] * 34
        state[32] = 0x100001234  # ARM_THREAD_STATE64 PC follows x[29], fp, lr, sp.
        thread = command(0x5, pack('II', 6, 68) + pack('34Q', *state))
        r = self.invoke(macho([thread]))
        self.assertEqual(r['entry_points'][0]['virtual_address'], 0x100001234)

    def test_symtab_imports_and_definitions(self):
        strings = b'\0_hello\0_import\0'
        symbols = pack('IBBHQ', 1, 0x0F, 1, 0, 0x1000) + pack('IBBHQ', 8, 1, 0, 0x140, 0)
        lib = dylib('/tmp/libexample.dylib')
        offset = 32 + len(lib) + 24
        cmd = command(2, pack('4I', offset, 2, offset + len(symbols), len(strings)))
        r = self.invoke(macho([lib, cmd], symbols + strings))
        self.assertEqual(r['defined_external_symbols'][0]['name'], '_hello')
        self.assertEqual(r['undefined_symbols'][0]['name'], '_import')
        self.assertTrue(r['undefined_symbols'][0]['weak_import'])
        self.assertEqual(r['undefined_symbols'][0]['library'], '/tmp/libexample.dylib')
        bad = pack('IBBHQ', 999, 1, 0, 0, 0) + symbols[16:]
        self.invoke(macho([lib, cmd], bad + strings), ok=False)

    def test_export_trie_and_legacy_export(self):
        # Root: empty terminal, one '_foo' edge pointing to offset 8.
        trie = b'\0\1_foo\0\x08' + b'\x03\0\x80\x20\0'
        for legacy in [False, True]:
            r = self.invoke(export_image(trie, legacy))
            self.assertEqual(r['exports'][0]['name'], '_foo')
            self.assertEqual(r['exports'][0]['address_or_offset'], 4096)

    def test_export_reexport(self):
        trie = b'\0\1_x\0\x06' + b'\x08\x08\x01_real\0\0'
        r = self.invoke(export_image(trie))
        self.assertEqual(r['exports'][0]['library_ordinal'], 1)
        self.assertEqual(r['exports'][0]['import_name'], '_real')

    def test_export_malformed(self):
        for trie in [b'\x80', b'\xff'*11, b'\0\1x\0\0', b'\0\1x\0\x7f', b'\x02\0', b'\0\1x']:
            with self.subTest(trie=trie):
                self.invoke(export_image(trie), ok=False)

    def test_universal_containers(self):
        for wide in (False, True):
            thin = macho([command(0x1B, bytes(range(16)))])
            other = macho(subtype=2)
            header = struct.pack('>II', 0xCAFEBABF if wide else 0xCAFEBABE, 2)
            def entry(sub, off, size):
                return struct.pack('>IIQQII', ARM64, sub, off, size, 12, 0) if wide else struct.pack('>IIIII', ARM64, sub, off, size, 12)
            header += entry(0, 4096, len(thin)) + entry(2, 8192, len(other))
            data = header + bytes(4096-len(header)) + thin
            data += bytes(8192-len(data)) + other
            r = self.invoke(data)
            self.assertEqual(r['slice_offset'], 4096)
            self.assertEqual(len(r['slices']), 2)
            r = self.invoke(data, args=['--arch', 'arm64e'])
            self.assertEqual(r['slice_offset'], 8192)
            self.assertEqual(r['header']['architecture'], 'arm64e')
            self.invoke(data[:-1], ok=False)

    def test_subtype_capabilities(self):
        r = self.invoke(macho(subtype=0x80000002))
        self.assertEqual(r['header']['subtype_base'], 2)
        self.assertEqual(r['header']['subtype_capabilities'], 0x80000000)
        self.invoke(macho(), args=['--arch','arm64e'], ok=False)

    def test_malformed_commands(self):
        valid = macho([command(0x1B, bytes(16))])
        cases = [b'', b'not macho', valid[:31], valid[:-1],
                 macho([pack('II', 0x1B, 0)]), macho([pack('II', 0x1B, 9) + b'x']),
                 macho([pack('II', 0x1B, 0xFFFFFFF8)]), macho([command(0x1B)]),
                 macho([command(0x32, pack('4I', 1, 0, 0, 0xFFFFFFFF))]),
                 macho([command(0x8000001C, pack('I', 4))]),
                 macho([command(0x8000001C, pack('I', 12) + b'xxxx')]),
                 macho([command(2, pack('4I', 0xFFFFFFF0, 0xFFFFFFFF, 0, 0))])]
        for i, data in enumerate(cases):
            with self.subTest(case=i): self.invoke(data, ok=False)

    def test_json_byte_escaping_and_terminal_safety(self):
        data = macho([dylib('/tmp/quo"te\\tab\tline\n\x1b.dylib')])
        r = self.invoke(data)
        self.assertEqual(r['dylibs'][0]['name'], '/tmp/quo"te\\tab\tline\n\x1b.dylib')
        p = subprocess.run([str(TOOL), 'inspect', str(self.directory / 'fixture')], capture_output=True, text=True)
        self.assertNotIn('\x1b', p.stdout)
        self.assertIn('\\x1b', p.stdout)

    def test_mutation_smoke(self):
        # Deterministic corruption corpus; successful parses are allowed, crashes are not.
        rng = random.Random(20261001)
        seed = (ROOT / 'build/hello').read_bytes()
        for _ in range(40):
            data = bytearray(seed)
            index = rng.randrange(min(1024, len(data)))
            data[index] ^= 1 << rng.randrange(8)
            path = self.directory / 'mutant'
            path.write_bytes(data)
            p = subprocess.run([str(TOOL),'inspect',str(path),'--json'], capture_output=True, text=True, timeout=15)
            self.assertIn(p.returncode, (0,1), p.stderr)
            self.assertNotIn('Sanitizer', p.stderr)
            json.loads(p.stdout)

    def test_real_modern_linkedit(self):
        path = self.directory / 'hello-modern'
        sdk = subprocess.check_output(['xcrun','--show-sdk-path'], text=True).strip()
        subprocess.run(['xcrun','clang','-arch','arm64','-isysroot',sdk,'-mmacosx-version-min=13.0',
                        '-Wl,-fixup_chains',str(ROOT/'samples/hello.c'),'-o',str(path)], check=True, capture_output=True)
        parsed = json.loads(subprocess.check_output([str(TOOL),'inspect',str(path),'--json'],text=True))
        otool = subprocess.check_output(['otool','-l',str(path)],text=True)
        self.assertIn('LC_DYLD_CHAINED_FIXUPS',otool)
        self.assertIn('LC_DYLD_EXPORTS_TRIE',otool)
        self.assertTrue({'LC_DYLD_CHAINED_FIXUPS','LC_DYLD_EXPORTS_TRIE'}.issubset({c['name'] for c in parsed['load_commands']}))
        self.assertIn('_main',{s['name'] for s in parsed['exports']})
        self.assertIn('_puts',{s['name'] for s in parsed['undefined_symbols']})
        self.assertEqual(subprocess.check_output([str(path)],text=True),'Hello from macOS ARM64\n')

    def test_bad_universal_metadata(self):
        thin = macho()
        entry = struct.pack('>IIIII', ARM64, 0, 4096, len(thin), 12)
        prefix = struct.pack('>II', 0xCAFEBABE, 2) + entry + entry
        self.invoke(prefix + bytes(4096-len(prefix)) + thin, ok=False)
        prefix = struct.pack('>II', 0xCAFEBABE, 1) + struct.pack('>IIIII', ARM64, 2, 4096, len(thin), 12)
        self.invoke(prefix + bytes(4096-len(prefix)) + thin, ok=False)
        self.invoke(struct.pack('>II', 0xCAFEBABE, 0xFFFFFFFF), ok=False)

    def test_usage_errors(self):
        path = self.directory/'fixture'; path.write_bytes(macho())
        for args in [('deps',str(path),'--max-depth','-1'),('inspect',str(path),'--arch','x86_64'),
                     ('deps',str(path),'--max-depth','129'),('inspect',str(path),'--nonsense')]:
            p = subprocess.run([str(TOOL),*args],capture_output=True,text=True)
            self.assertEqual(p.returncode,1)
            self.assertTrue(p.stderr)
