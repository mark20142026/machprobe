# 05 - Tools and diagnostics

> Not piracy: no game files are included; you need your own copy. MIT-licensed. See [../NOTICE.md](../NOTICE.md).

This section documents the code and the tools behind Phase 8 (Cyberpunk 2077 on a
physical iPhone): the build and deploy scripts, the iOS host app, the Phase 8 runtime
layer, the telemetry lines the app prints, the debugging recipes, and the test suites.

Everything here is taken from the repository as it stood on the `phase6-supertuxkart`
branch. Paths are repo-relative. Where the code does not say something, the text says
"unknown" rather than guessing.

## Files

| File | What it covers |
|------|----------------|
| [build-tools.md](build-tools.md) | `phase8/tools/setup.py` (the one entry point: `doctor`, `config`, `prepare-game`, `profile`, `build`, `install`, `copy-data`, `restore`, `launch`), `phase7/tools/localconfig.py`, `build.py`, `phone.py` (every subcommand), `push_resume.py`, `make_icon.swift`, `import_gaps.py`, and `phase7/tools/device.py` |
| [host-app.md](host-app.md) | `phase8/host/Main.m` (startup, crash handler, env.json, telemetry threads, display modes, control install) and `phase8/host/LoadCLI.m` (Mac load-only introspection flags) |
| [phase8-runtime-reference.md](phase8-runtime-reference.md) | Function-by-function reference for `phase8/runtime/`: `Policy.c`, `CPMetal.m`, `CPAppKit.m`, `CPDesktop.m`, `CPControls.m` |
| [telemetry.md](telemetry.md) | Every log line family the app prints (`[budget]`, `[vmtags]`, `[perf]`, `[mem]`, `[gpu]`, `[crash]`, ...), the frame counter, the watchdog, and how each was used to find a bug |
| [debugging-playbook.md](debugging-playbook.md) | Step-by-step recipes: reading crashes, streaming logs, Instruments, selector survey, VA probe, fs and memory traces, the `Documents/debug` toggle |
| [tests.md](tests.md) | `tests/` (Phase 1 parser and sample tests) and `phase5_5/tests/` (runtime, keyboard, TLS), and how to run them |

## Conventions used

- **Shared layers.** Phase 8 is built on code from earlier phases. `runtime/` (loader),
  `phase5/`, `phase5_5/`, and `phase6/runtime/` are shared. The Phase 8 files are
  `phase8/runtime/*` and `phase8/host/*` plus the Phase 8 tools. Where a function lives in
  a shared layer, the docs say so.
- **Placeholders.** Device identifiers, the Apple team ID, the signing identity and the App ID
  prefix are written as `<DEVICE-UDID>`, `<TEAM-ID>`, `<SIGNING-IDENTITY-SHA1>` and
  `<your-bundle-prefix>`. The scripts do not contain these values: `setup.py config` writes
  them to the git-ignored `machprobe.local.json`, which `phase7/tools/localconfig.py` reads.
  The docs do not repeat anyone's real values.
- **Setup entry point.** Use `python3 phase8/tools/setup.py` (usage: `... setup.py help`) to
  set up; the tools below are what it runs. Step-by-step guide:
  [../01-getting-started/](../01-getting-started/), [Part 2 of the README](../../README.md),
  and [AGENT-SETUP.md](../../AGENT-SETUP.md) for agents.
- **Two output folders.** `build/phase8-runtime/` holds the iOS app bundle and the
  files the app writes on the phone. `build/phase7/` is where `phase7/tools/device.py`
  (and therefore `phone.py logs` and `phone.py report`) pulls files from the device.
- **Log evidence.** Numbers quoted from device runs come from `CONTEXT.md`, the handoff
  file. They are not re-measured here.

## Things to know before using the tools

- `phase7/tools/device.py` targets the SuperTuxKart App ID `<your-bundle-prefix>.STKHost`.
  `CONTEXT.md` records that, in the author's original setup, another project took over that
  App ID. Do not use its `deploy` or `install` for Cyberpunk. The Cyberpunk path is
  `phase8/tools/phone.py` (`setup.py install` / `setup.py launch`), which uses
  `<your-bundle-prefix>.CP2077`.
- `device.py` and `phone.py` load `machprobe.local.json` when imported. If it is missing,
  every subcommand exits with a message to run `setup.py config`. The provisioning profile is
  looked up only by `phone.py deploy`; if none exists for the Cyberpunk App ID it exits with
  a message to run `setup.py profile` (see [build-tools.md](build-tools.md)).
- Nothing in this section builds, deploys, or launches anything. The docs describe the
  code only.
