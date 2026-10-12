"""Integration checks for the native samples and machprobe's JSON reports."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PROBE = Path(os.environ.get("MACHPROBE", ROOT / "build/machprobe"))
SAMPLES = {
    "hello": ROOT / "build/hello",
    "file_io": ROOT / "build/file_io",
    "framework": ROOT / "build/framework",
    "metal_info": ROOT / "build/metal_info",
}


def command(argv):
    return subprocess.run([str(a) for a in argv], text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          check=False)


def report_for(sample):
    result = command([PROBE, "inspect", sample, "--arch", "arm64", "--json"])
    if result.returncode:
        raise AssertionError(f"inspector failed for {sample}: {result.stderr}")
    return json.loads(result.stdout)


def tool_output(argv):
    result = command(argv)
    if result.returncode:
        raise AssertionError(f"{argv[0]} failed: {result.stderr}")
    return result.stdout + result.stderr


def normalized_version(version):
    parts = version.strip().split(".")
    parts = (parts + ["0", "0", "0"])[:3]
    return ".".join(str(int(part)) for part in parts)


class SampleIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not PROBE.is_file():
            raise RuntimeError(f"machprobe binary not found: {PROBE}; run make all")
        for sample in SAMPLES.values():
            if not sample.is_file():
                raise RuntimeError(f"sample executable not found: {sample}; run make samples")
        sdk = command(["xcrun", "--sdk", "macosx", "--show-sdk-version"])
        if sdk.returncode:
            raise RuntimeError(f"cannot query macOS SDK version: {sdk.stderr}")
        cls.sdk_version = normalized_version(sdk.stdout)

    def test_samples_run_and_file_io_cleans_up(self):
        expected = {
            "hello": "Hello from macOS ARM64\n",
            "framework": "CoreFoundation string length: 11\n",
        }
        for name in ("hello", "framework"):
            with self.subTest(sample=name):
                result = command([SAMPLES[name]])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(expected[name], result.stdout)

        with tempfile.TemporaryDirectory(prefix="machprobe-sample-") as temporary:
            directory = Path(temporary)
            result = command([SAMPLES["file_io"], directory])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual("File I/O round trip OK\n", result.stdout)
            self.assertEqual(list(directory.iterdir()), [])
        self.assertFalse(directory.exists())

        with tempfile.TemporaryDirectory(prefix="machprobe-missing-") as temporary:
            missing = Path(temporary) / "does-not-exist"
            result = command([SAMPLES["file_io"], missing])
            self.assertNotEqual(result.returncode, 0)

    def test_metal_sample_reports_device_properties(self):
        result = command([SAMPLES["metal_info"]])
        self.assertEqual(result.returncode, 0, result.stderr)
        match = re.search(r"(?m)^Metal device: (.+)$", result.stdout)
        self.assertIsNotNone(match, result.stdout)
        self.assertTrue(match.group(1).strip())
        registry = re.search(r"(?m)^Registry ID: (\d+)$", result.stdout)
        self.assertIsNotNone(registry, result.stdout)
        self.assertGreater(int(registry.group(1)), 0)
        self.assertRegex(result.stdout, r"(?m)^Unified memory: (yes|no)$")

    def test_inspection_matches_system_tools(self):
        for name, path in SAMPLES.items():
            with self.subTest(sample=name):
                report = report_for(path)
                self.assertEqual(report["header"]["architecture"], "arm64")
                self.assertEqual(report["header"]["file_type"], "MH_EXECUTE")
                self.assertTrue(report["build_versions"])
                build = report["build_versions"][0]
                self.assertEqual(build["platform"], "macOS")
                self.assertEqual(build["minimum_os"], "11.0.0")
                self.assertEqual(build["sdk"], self.sdk_version)
                self.assertEqual(report["header"]["ncmds"], len(report["load_commands"]))

                otool = tool_output(["otool", "-l", path])
                uuid_match = re.search(r"(?mi)^\s*uuid\s+([0-9a-f-]{36})\s*$", otool)
                self.assertIsNotNone(uuid_match, otool)
                self.assertIn(uuid_match.group(1).lower(),
                              {u.lower() for u in report["uuids"]})
                entry_match = re.search(r"(?ms)^\s*cmd LC_MAIN\s+.*?^\s*entryoff (\d+)\s*$", otool)
                self.assertIsNotNone(entry_match, otool)
                entryoff = int(entry_match.group(1))
                entry = next(e for e in report["entry_points"] if e["source"] == "LC_MAIN")
                self.assertEqual(entry["entryoff"], entryoff)
                text_block = re.search(
                    r"(?ms)^Load command \d+\s+cmd LC_SEGMENT_64\s+.*?^\s*segname __TEXT\s*$"
                    r"(?P<fields>.*?)(?=^Load command|\Z)", otool)
                self.assertIsNotNone(text_block, otool)
                fields = text_block.group("fields")
                vm_match = re.search(r"(?m)^\s*vmaddr (\S+)", fields)
                file_match = re.search(r"(?m)^\s*fileoff (\S+)", fields)
                size_match = re.search(r"(?m)^\s*filesize (\S+)", fields)
                self.assertTrue(vm_match and file_match and size_match, fields)
                parse_number = lambda value: int(value, 16) if value.startswith("0x") else int(value)
                vmaddr, fileoff, filesize = (parse_number(m.group(1))
                                             for m in (vm_match, file_match, size_match))
                self.assertGreaterEqual(entryoff, fileoff)
                self.assertLess(entryoff - fileoff, filesize)
                self.assertEqual(entry["virtual_address"], vmaddr + entryoff - fileoff)

                self.assertIn("arm64", tool_output(["lipo", "-archs", path]).split())
                vtool = tool_output(["vtool", "-show-build", path])
                self.assertRegex(vtool.lower(), r"platform\s+macos")
                self.assertEqual(report["build_versions"][0]["platform"], "macOS")

                codesign = command(["codesign", "--verify", "--strict", "--verbose=2", path])
                self.assertEqual(codesign.returncode, 0, codesign.stderr)
                self.assertTrue(any(c["name"] == "LC_CODE_SIGNATURE"
                                    for c in report["load_commands"]))
                self.assertFalse(any(c["name"] in ("LC_ENCRYPTION_INFO", "LC_ENCRYPTION_INFO_64")
                                     for c in report["load_commands"]))

                otool_libs = tool_output(["otool", "-L", path]).splitlines()[1:]
                system_libs = {line.strip().split(" (", 1)[0] for line in otool_libs}
                report_libs = {d["name"] for d in report["dylibs"]
                               if d["kind"] != "LC_ID_DYLIB"}
                self.assertEqual(report_libs, system_libs)

                nm = tool_output(["nm", "-u", path])
                nm_symbols = set()
                for line in nm.splitlines():
                    fields = line.split()
                    if fields:
                        # Apple nm may print only the symbol with -u, while other
                        # releases include a type column or an undefined label.
                        symbol = fields[-1]
                        if symbol not in ("external", "undefined"):
                            nm_symbols.add(symbol)
                report_symbols = {s["name"] for s in report["undefined_symbols"]}
                self.assertEqual(report_symbols, nm_symbols)

    def test_expected_external_symbols(self):
        hello = {s["name"] for s in report_for(SAMPLES["hello"])["undefined_symbols"]}
        framework = {s["name"] for s in report_for(SAMPLES["framework"])["undefined_symbols"]}
        metal = {s["name"] for s in report_for(SAMPLES["metal_info"])["undefined_symbols"]}
        self.assertIn("_puts", hello)
        self.assertTrue({"_CFStringCreateWithCString", "_CFStringGetLength"}.issubset(framework))
        self.assertIn("_MTLCreateSystemDefaultDevice", metal)

    def test_dependency_report_classifies_system_and_metal(self):
        for name, path in SAMPLES.items():
            with self.subTest(sample=name):
                result = command([PROBE, "deps", path, "--arch", "arm64", "--json"])
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads(result.stdout)
                edges = report["edges"]
                system = [edge for edge in edges if "libSystem" in edge["install_name"]]
                self.assertTrue(system, edges)
                if system:
                    self.assertTrue(any("Darwin/system" in edge["categories"] for edge in system))
                    self.assertTrue(any(edge["status"] in ("inspected", "cache-only")
                                        for edge in system))
                if name == "metal_info":
                    metal = [edge for edge in edges if "Metal" in edge["install_name"]]
                    self.assertTrue(metal, edges)
                    self.assertTrue(all("graphics/Metal" in edge["categories"] for edge in metal))


if __name__ == "__main__":
    unittest.main()
