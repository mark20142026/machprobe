"""Exercise runtime stream parsing with ASan/UBSan, without executable code."""
from pathlib import Path
import subprocess
import unittest
ROOT = Path(__file__).resolve().parents[2]
class FixupTests(unittest.TestCase):
    def test_appkit_opcodes_and_rejection_paths(self):
        output = ROOT / 'build/phase3/fixups-sanitize'
        output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['xcrun', 'clang', '-arch', 'arm64', '-Wall', '-Wextra',
                        '-fsanitize=address,undefined', '-fno-sanitize-recover=all',
                        '-g', '-I' + str(ROOT / 'runtime'),
                        str(ROOT / 'runtime/fixups.c'), str(ROOT / 'phase3/tests/fixups.c'),
                        '-o', str(output)], check=True)
        result = subprocess.run([output], check=True, capture_output=True, text=True)
        self.assertIn('cases passed', result.stdout)
