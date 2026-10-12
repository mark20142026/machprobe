import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from test_parser import ROOT, TOOL, macho, dylib, rpath

class DependencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory(prefix='native-deps-', dir=ROOT / 'build')
        cls.addClassCleanup(cls.workspace.cleanup)
        cls.base = Path(cls.workspace.name)
        (cls.base / 'deps/nested').mkdir(parents=True)
        sdk = subprocess.check_output(['xcrun','--show-sdk-path'], text=True).strip()
        cc = ['xcrun','clang','-arch','arm64','-isysroot',sdk,'-mmacosx-version-min=11.0']
        fixture = ROOT / 'tests/fixtures'
        def build(args): subprocess.run(cc + args, check=True, capture_output=True)
        build(['-dynamiclib',str(fixture/'dep_b.c'),'-Wl,-install_name,@rpath/libprobe_b.dylib','-o',str(cls.base/'deps/nested/libprobe_b.dylib')])
        build(['-dynamiclib',str(fixture/'dep_a.c'),'-L'+str(cls.base/'deps/nested'),'-lprobe_b','-Wl,-install_name,@rpath/libprobe_a.dylib','-Wl,-rpath,@loader_path/nested','-o',str(cls.base/'deps/libprobe_a.dylib')])
        build([str(fixture/'dep_main.c'),'-L'+str(cls.base/'deps'),'-lprobe_a','-Wl,-rpath,@executable_path/deps','-o',str(cls.base/'entry')])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / 'build')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def report(self, path, *args):
        p = subprocess.run([str(TOOL),'deps',str(path),'--json',*args], capture_output=True, text=True, timeout=15)
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertNotIn('Sanitizer', p.stderr)
        return json.loads(p.stdout)

    def test_native_chain_executes_and_resolves(self):
        p = subprocess.run([str(self.base/'entry')], capture_output=True, text=True)
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(p.stdout,'dependency chain: 42\n')
        r = self.report(self.base/'entry')
        self.assertEqual(len(r['nodes']),3)
        for name in ['libprobe_a.dylib','libprobe_b.dylib']:
            edge = next(e for e in r['edges'] if e['install_name'].endswith(name))
            self.assertEqual(edge['status'],'inspected')
            self.assertIn('application-specific',edge['categories'])
        bnode = next(n for n in r['nodes'] if n['path'].endswith('libprobe_b.dylib'))
        self.assertEqual(bnode['depth'],2)
        # Export trie must independently identify our real dylib's exported API.
        parsed = subprocess.check_output([str(TOOL),'inspect',str(self.base/'deps/nested/libprobe_b.dylib'),'--json'], text=True)
        self.assertIn('_probe_b',{e['name'] for e in json.loads(parsed)['exports']})

    def test_depth_limit(self):
        r = self.report(self.base/'entry','--max-depth','0')
        self.assertEqual(len(r['nodes']),1)
        self.assertIn('depth-limit',{e['status'] for e in r['edges']})
        self.assertFalse(r['complete'])

    def test_cycle_and_missing_and_identity(self):
        a, b = self.directory/'a', self.directory/'b'
        a.write_bytes(macho([dylib('@loader_path/b'),dylib('@loader_path/missing'),dylib('@rpath/no_search_path')]))
        b.write_bytes(macho([dylib('@loader_path/a'),dylib('/ignored/install/name',0xD)]))
        r = self.report(a)
        self.assertEqual(len(r['nodes']),2)
        self.assertEqual({e['status'] for e in r['edges']},{'cycle','missing','unmodeled-path','inspected'})
        self.assertNotIn('/ignored/install/name',{e['install_name'] for e in r['edges']})

    def test_inherited_rpath_and_precedence(self):
        root, child = self.directory/'entry', self.directory/'child'
        (self.directory/'first').mkdir(); (self.directory/'second').mkdir()
        for d in ['first','second']: (self.directory/d/'libb').write_bytes(macho(filetype=6))
        root.write_bytes(macho([rpath('@executable_path/second'),dylib('@loader_path/child')]))
        child.write_bytes(macho([rpath('@loader_path/first'),dylib('@rpath/libb')],filetype=6))
        r = self.report(root)
        e = next(e for e in r['edges'] if e['install_name']=='@rpath/libb')
        self.assertEqual(Path(e['resolved_path']),self.directory/'first/libb')
        child.write_bytes(macho([dylib('@rpath/libb')],filetype=6))
        r = self.report(root)
        e = next(e for e in r['edges'] if e['install_name']=='@rpath/libb')
        self.assertEqual(Path(e['resolved_path']),self.directory/'second/libb')

    def test_same_library_different_runpath_context(self):
        root, a, b, shared = [self.directory/n for n in ['root','a','b','shared']]
        for d in ['a_dir','b_dir']:
            (self.directory/d).mkdir(); (self.directory/d/'leaf').write_bytes(macho(filetype=6))
        root.write_bytes(macho([dylib('@loader_path/a'),dylib('@loader_path/b')]))
        a.write_bytes(macho([rpath('@loader_path/a_dir'),dylib('@loader_path/shared')],filetype=6))
        b.write_bytes(macho([rpath('@loader_path/b_dir'),dylib('@loader_path/shared')],filetype=6))
        shared.write_bytes(macho([dylib('@rpath/leaf')],filetype=6))
        r = self.report(root)
        leaves = {e['resolved_path'] for e in r['edges'] if e['install_name']=='@rpath/leaf'}
        self.assertEqual(leaves,{str(self.directory/'a_dir/leaf'),str(self.directory/'b_dir/leaf')})

    def test_malformed_and_unsupported_dependencies(self):
        (self.directory/'bad').write_bytes(b'junk')
        other = bytearray(macho()); other[4:8] = (0x1000007).to_bytes(4,'little')
        (self.directory/'x86').write_bytes(other)
        root = self.directory/'entry'
        root.write_bytes(macho([dylib('@loader_path/bad'),dylib('@loader_path/x86')]))
        r = self.report(root)
        self.assertEqual({e['status'] for e in r['edges']},{'malformed','unsupported'})

    def test_relative_path_is_explicitly_unmodeled(self):
        root = self.directory/'entry'
        root.write_bytes(macho([rpath('relative'),dylib('relative.dylib')]))
        r = self.report(root)
        self.assertEqual(r['nodes'][0]['unmodeled_rpaths'],['relative'])
        self.assertEqual(r['edges'][0]['status'],'unmodeled-path')

    def test_node_limit(self):
        # A broad graph checks node limiting without relying on deep recursion.
        root = self.directory/'root'
        cmds = []
        for i in range(1025):
            name = 'leaf'+str(i)
            (self.directory/name).write_bytes(macho(filetype=6))
            cmds.append(dylib('@loader_path/'+name))
        root.write_bytes(macho(cmds))
        r = self.report(root)
        self.assertEqual(len(r['nodes']),1024)
        self.assertEqual(sum(e['status']=='node-limit' for e in r['edges']),2)
