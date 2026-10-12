#!/usr/bin/env python3
"""Capture a machine-readable macOS ARM64 machprobe baseline."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import platform
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SAMPLES = ["build/hello", "build/file_io", "build/framework", "build/metal_info"]


def capture(argv: list[str], cwd: Path = ROOT) -> dict:
    try:
        p = subprocess.run(argv, cwd=cwd, text=True, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, check=False)
        return {"argv": argv, "returncode": p.returncode, "stdout": p.stdout,
                "stderr": p.stderr}
    except OSError as e:
        return {"argv": argv, "returncode": None, "stdout": "", "stderr": str(e)}


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main() -> int:
    result: dict = {
        "schema_version": 1,
        "captured_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "environment": {
            "platform": platform.platform(),
            "python": sys.version,
            "sw_vers": capture(["sw_vers"]),
            "uname": capture(["uname", "-a"]),
            "xcrun_sdk": capture(["xcrun", "--sdk", "macosx", "--show-sdk-path"]),
            "sdk_version": capture(["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
            "git_status": capture(["git", "status", "--porcelain"]),
            "clang_version": capture(["xcrun", "clang", "--version"]),
            "git_head": capture(["git", "rev-parse", "HEAD"]),
            "build_dry_run": capture(["make", "-Bn", "all"]),
        },
        "samples": {},
        "essential_failures": [],
        "auxiliary_tool_notes": [],
    }

    for rel in SAMPLES:
        path = ROOT / rel
        entry: dict = {"path": rel, "sha256": digest(path) if path.is_file() else None,
                       "commands": {}}
        if not path.is_file():
            result["essential_failures"].append(f"missing sample executable: {rel}")
            result["samples"][rel] = entry
            continue

        if rel.endswith("file_io"):
            with tempfile.TemporaryDirectory(prefix="machprobe-evidence-") as tmp:
                run = capture([str(path), tmp])
        else:
            run = capture([str(path)])
        entry["commands"]["run"] = run
        if run["returncode"] != 0:
            result["essential_failures"].append(f"sample failed: {rel} ({run['returncode']})")

        commands = {
            "file": ["file", str(path)],
            "lipo_archs": ["lipo", "-archs", str(path)],
            "otool_load_commands": ["otool", "-l", str(path)],
            "otool_libraries": ["otool", "-L", str(path)],
            "nm_globals": ["nm", "-g", str(path)],
            "nm_undefined": ["nm", "-u", str(path)],
            "vtool_build": ["vtool", "-show-build", str(path)],
            "codesign_details": ["codesign", "-dv", "--verbose=4", str(path)],
            "codesign_verify": ["codesign", "--verify", "--strict", "--verbose=2", str(path)],
            "inspect_json": [str(ROOT / "build/machprobe"), "inspect", str(path), "--arch", "arm64", "--json"],
            "deps_json": [str(ROOT / "build/machprobe"), "deps", str(path), "--arch", "arm64", "--json"],
        }
        for label, argv in commands.items():
            entry["commands"][label] = capture(argv)

        arch = entry["commands"]["lipo_archs"]
        if arch["returncode"] != 0 or "arm64" not in arch["stdout"].split():
            result["essential_failures"].append(f"sample lacks verifiable arm64 architecture: {rel}")
        for label in ("inspect_json", "deps_json"):
            cmd = entry["commands"][label]
            if cmd["returncode"] != 0:
                result["essential_failures"].append(f"inspector {label} failed for {rel} ({cmd['returncode']})")
            try:
                json.loads(cmd["stdout"])
            except (TypeError, json.JSONDecodeError):
                result["essential_failures"].append(f"inspector {label} did not emit valid JSON for {rel}")
        verify = entry["commands"]["codesign_verify"]
        if verify["returncode"] != 0:
            result["essential_failures"].append(f"signature verification failed for {rel} ({verify['returncode']})")
        for label in ("file", "lipo_archs", "otool_load_commands", "otool_libraries", "nm_globals",
                      "nm_undefined", "vtool_build", "codesign_details"):
            cmd = entry["commands"][label]
            if cmd["returncode"] != 0:
                result["auxiliary_tool_notes"].append(
                    f"{label} returned {cmd['returncode']} for {rel}: {cmd['stderr'].strip()}")
        result["samples"][rel] = entry

    out = ROOT / "docs/evidence/baseline.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {out.relative_to(ROOT)}")
    if result["essential_failures"]:
        print("Evidence capture had essential failures:", file=sys.stderr)
        for failure in result["essential_failures"]:
            print(f"- {failure}", file=sys.stderr)
        return 1
    if result["auxiliary_tool_notes"]:
        print(f"Recorded {len(result['auxiliary_tool_notes'])} auxiliary tool issue(s).", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
