"""Integration tests for the deliberately narrow in-process macOS guest runtime."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / os.environ.get("MP_RUNNER", "build/phase2/runner")
ABI_TEST = ROOT / os.environ.get("MP_ABI_TEST", "build/phase2/abi-test")
INSPECTOR = ROOT / os.environ.get("MACHPROBE", "build/machprobe")
SAMPLES = {
    "hello": ROOT / "build/hello",
    "file_io": ROOT / "build/file_io",
    "framework": ROOT / "build/framework",
    "metal_info": ROOT / "build/metal_info",
}
PHASE2_GUESTS = [ROOT / "build/phase2/foundation", ROOT / "build/phase2/metal_compute"]


def invoke(argv, timeout=20, cwd=None):
    result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True,
                            timeout=timeout)
    combined = result.stdout + result.stderr
    for marker in ("AddressSanitizer", "UndefinedBehaviorSanitizer", "runtime error:"):
        if marker in combined:
            raise AssertionError(f"sanitizer diagnostic in {argv!r}:\n{combined}")
    return result


class RuntimeIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for path in [RUNNER, ABI_TEST, INSPECTOR, *SAMPLES.values(), *PHASE2_GUESTS,
                     ROOT / "build/phase2/interactive"]:
            if not path.is_file():
                raise RuntimeError(f"required build output missing: {path}; run make -f phase2/Makefile all")
        cls.baseline = json.loads((ROOT / "docs/evidence/phase2/baseline.json").read_text())
        cls.initial_guest_hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in PHASE2_GUESTS}

    def run_guest(self, image, *args, timeout=20, cwd=None):
        return invoke([str(RUNNER), str(image), *map(str, args)], timeout=timeout, cwd=cwd)

    def assert_guest_rejected(self, image, expected):
        result = self.run_guest(image)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("LOAD ERROR:", result.stderr)
        self.assertIn(expected, result.stderr)
        self.assertEqual(result.stdout, "")

    def mach_info(self, image):
        result = invoke([str(INSPECTOR), "inspect", str(image), "--json"])
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def sign(self, image):
        result = invoke(["codesign", "--force", "--sign", "-", str(image)])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_original_hello_and_framework(self):
        hello = self.run_guest(SAMPLES["hello"])
        self.assertEqual(hello.returncode, 0, hello.stderr)
        self.assertEqual(hello.stdout, "Hello from macOS ARM64\n")

        framework = self.run_guest(SAMPLES["framework"])
        self.assertEqual(framework.returncode, 0, framework.stderr)
        self.assertEqual(framework.stdout, "CoreFoundation string length: 11\n")

    def test_file_io_success_cleanup_and_invalid_directory(self):
        with tempfile.TemporaryDirectory(prefix="phase2-fileio-") as directory:
            result = self.run_guest(SAMPLES["file_io"], directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "File I/O round trip OK\n")
            self.assertEqual(list(Path(directory).iterdir()), [])

            missing = Path(directory) / "does-not-exist"
            failed = self.run_guest(SAMPLES["file_io"], missing)
            self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
            self.assertEqual(failed.stdout, "")

    def test_metal_device_is_reported(self):
        result = self.run_guest(SAMPLES["metal_info"], timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"(?m)^Metal device: .+\n")
        self.assertRegex(result.stdout, r"(?m)^Registry ID: [1-9][0-9]*\n")
        self.assertRegex(result.stdout, r"(?m)^Unified memory: (?:yes|no)\n")

    def test_foundation_guest_behaviors(self):
        result = self.run_guest(PHASE2_GUESTS[0])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout,
                         "FOUNDATION_RESULT weak=cleared class=NSString selector=length length=17 count=2 "
                         "value=phase2-foundation|PHASE2-FOUNDATION\n")

    def test_metal_compute_values_and_checksum(self):
        result = self.run_guest(PHASE2_GUESTS[1], timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        match = re.fullmatch(r"METAL_RESULT count=(\d+) values=([0-9,]+) checksum=(\d+)\n",
                             result.stdout)
        self.assertIsNotNone(match, result.stdout)
        count, values, checksum = int(match.group(1)), list(map(int, match.group(2).split(","))), int(match.group(3))
        expected = [index * 3 + 7 for index in range(16)]
        self.assertEqual(count, 16)
        self.assertEqual(values, expected)
        self.assertEqual(checksum, sum(expected))
        self.assertEqual(checksum, 472)

    def test_abi_guest_runner(self):
        result = invoke([str(ABI_TEST), str(ROOT / "build/phase2/interactive")], timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ABI_OK", result.stdout)

    def test_rejects_malformed_and_unsupported_images(self):
        hello = SAMPLES["hello"]
        with tempfile.TemporaryDirectory(prefix="phase2-malformed-") as directory:
            directory = Path(directory)
            info = self.mach_info(hello)

            badmagic = directory / "badmagic"
            data = bytearray(hello.read_bytes())
            data[0] ^= 0xff
            badmagic.write_bytes(data)
            self.assert_guest_rejected(badmagic, "thin ordinary ARM64 MH_EXECUTE")

            truncated = directory / "truncated"
            truncated.write_bytes(hello.read_bytes()[:48])
            self.assert_guest_rejected(truncated, "bad load command region")

            def copy_image(name):
                target = directory / name
                shutil.copyfile(hello, target)
                return target, bytearray(target.read_bytes())

            build_version = next(command for command in info["load_commands"]
                                 if command["name"] == "LC_BUILD_VERSION")
            target, contents = copy_image("platform2")
            struct.pack_into("<I", contents, build_version["offset"] + 8, 2)
            target.write_bytes(contents)
            self.sign(target)
            self.assert_guest_rejected(target, "supported macOS executable contract")

            main_command = next(command for command in info["load_commands"]
                                if command["name"] == "LC_MAIN")
            target, contents = copy_image("badentry")
            struct.pack_into("<Q", contents, main_command["offset"] + 8, 0)
            target.write_bytes(contents)
            self.sign(target)
            self.assert_guest_rejected(target, "supported macOS executable contract")

            bind = next(stream for stream in info["linkedit"] if stream["kind"] == "lazy_bind")
            target, contents = copy_image("unknownimport")
            start, end = bind["offset"], bind["offset"] + bind["size"]
            position = contents.index(b"_puts\0", start, end)
            contents[position:position + 5] = b"_nope"
            target.write_bytes(contents)
            self.sign(target)
            self.assert_guest_rejected(target, "unsupported import")
            repeated = invoke([str(ABI_TEST), str(ROOT / "build/phase2/interactive"), str(target)])
            self.assertEqual(repeated.returncode, 0, repeated.stderr)

            data_command = next(c for c in info["load_commands"] if c["name"] == "LC_SEGMENT_64" and hello.read_bytes()[c["offset"]+8:c["offset"]+24].rstrip(b"\0") == b"__DATA")
            target, contents = copy_image("permissions")
            struct.pack_into("<I", contents, data_command["offset"]+56, 1)
            target.write_bytes(contents); self.sign(target)
            self.assert_guest_rejected(target, "invalid segment bounds/alignment")

            for name, patch, expected in [
                ("unaligned-entry", lambda data: struct.pack_into("<Q", data, main_command["offset"]+8, 1), "supported macOS executable contract"),
            ]:
                target, contents = copy_image(name)
                patch(contents); target.write_bytes(contents); self.sign(target)
                self.assert_guest_rejected(target, expected)

            rebase = next(stream for stream in info["linkedit"] if stream["kind"] == "rebase")
            target, contents = copy_image("unsupported-rebase")
            contents[rebase["offset"]] = (contents[rebase["offset"]] & 0xf0) | 2
            target.write_bytes(contents)
            self.sign(target)
            self.assert_guest_rejected(target, "unsupported rebase type")

    def test_rejects_guest_tls_and_objc_class_registration(self):
        sdk = invoke(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
        self.assertEqual(sdk.returncode, 0, sdk.stderr)
        with tempfile.TemporaryDirectory(prefix="phase2-rejection-fixtures-") as directory:
            directory = Path(directory)
            fixtures = {
                "tls": ("tls.c", "__thread int phase2_tls = 9;\nint main(void) { return phase2_tls; }\n",
                        "TLS/terminators unsupported", []),
                "objc": ("objc.m", "#import <Foundation/Foundation.h>\n"
                         "@interface Phase2GuestObject : NSObject @end\n"
                         "@implementation Phase2GuestObject @end\n"
                         "int main(void) { return 0; }\n",
                         "guest Objective-C class/category registration unsupported",
                         ["-fobjc-arc", "-framework", "Foundation"]),
            }
            for name, (source_name, source, expected, extra) in fixtures.items():
                with self.subTest(fixture=name):
                    source_path = directory / source_name
                    image = directory / name
                    source_path.write_text(source)
                    compile_result = invoke(["xcrun", "clang", "-arch", "arm64", "-isysroot",
                                             sdk.stdout.strip(), "-mmacosx-version-min=11.0",
                                             *extra, str(source_path), "-o", str(image)], timeout=60)
                    self.assertEqual(compile_result.returncode, 0,
                                     compile_result.stdout + compile_result.stderr)
                    self.sign(image)
                    self.assert_guest_rejected(image, expected)

    def test_phase1_samples_match_recorded_hashes(self):
        for relative, path in (("build/hello", SAMPLES["hello"]),
                               ("build/file_io", SAMPLES["file_io"]),
                               ("build/framework", SAMPLES["framework"]),
                               ("build/metal_info", SAMPLES["metal_info"])):
            with self.subTest(sample=relative):
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),
                                 self.baseline["preserved_sha256"][relative])

    def test_phase2_guest_images_are_not_modified(self):
        for path, original_hash in self.initial_guest_hashes.items():
            with self.subTest(guest=path.name):
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), original_hash)


if __name__ == "__main__":
    unittest.main()
