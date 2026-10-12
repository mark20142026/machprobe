# First iOS VM execution: host repaired, guest admission blocked

Observed 1 October 2026. This is a focused follow-up to the completed Phase 2;
it is not a claim that the compatibility runtime now executes macOS code on iOS.

## Result

**VERIFIED:** The new official-SDK UIKit host launches in the existing `iphone`
vphone VM. All seven unchanged macOS guest files reach the loader, with their
original SHA-256 hashes verified inside the app. Each fails at
`fcntl(F_ADDFILESIGS_RETURN)` with `EBADEXEC` (errno 85). No guest entry point,
Objective-C guest operation, or guest Metal work executes in this run.

**VERIFIED:** The same signature-registration call succeeds on the installed
iOS host and fails on a byte-identical copy of that host in Documents. A separately
compiled, explicitly ad-hoc-signed iOS hello control also fails registration.
Thus macOS platform metadata alone does not explain the failure. Copying executable
bytes does not reproduce the installed file's admission state in this environment.

**HYPOTHESIS:** Installation establishes signature/trust state associated with
the installed file that ordinary in-app extraction does not reproduce. The precise
kernel/policy rejection branch remains unknown. Errno 85 alone does not identify it.
The public XNU implementation has multiple invalid-signature paths returning this
error; source inspection is not a trace of this VM's actual kernel.

## Environment and limits

- Xcode 27.0, build 27A266a; iPhoneOS 27.0 SDK. Per-build `DEVELOPER_DIR` selects
  Xcode, leaving the global command-line-tools selection unchanged.
- vphone Launchpad/Bundle 2.2.5; existing VM `iphone`, iOS 27.0 / firmware 24A435,
  kernel 25.4.0, four CPUs, approximately 4 GiB RAM.
- `device.info` reports jailbreak layout and jbroot as null, source `not detected`.
  No jailbreak/bootstrap was installed for this work. The user reports this VM
  is not jailbroken; do not carry the Phase 2 proposed configuration forward as fact.
- The running host reports UID 501. Installation reports a containerized User app.
  Installed entitlements include `com.apple.private.security.container-required`
  and **`jb.pmap_cs_custom_trust = PMAP_CS_APP_STORE`**, supplied by the vphone
  installer, not by our build script. This is an observed installation dependency;
  it does not establish stock-device signing or prove every sandbox restriction.
- `security find-identity -v -p codesigning` found **zero valid identities**.
  A normally provisioned development-signing comparison was not available.
- No Simulator was downloaded. No host/guest security setting was changed.
  No checks were removed, no executable-memory bypass was introduced, and no
  privileged service was added to the runtime.

## What was fixed

The original experimental IPA's guest was changed by installation. The installed
`interactive` measured 52,560 bytes, versus 51,944 bytes locally; its SHA-256 was
`e5217889b05717989a9be319564b4e73e744e6a2c24ac65ffc6e996b378be93a`.
Its `LC_CODE_SIGNATURE` size changed from 536 to 1,152 bytes at offset 51,408.
Apple's local strict codesign verification rejected that installed copy. The
inspector's recorded output is retained in `evidence/phase3/installer-modified-interactive.json`.
This observation did **not** prove the entire runtime error was caused by rewriting:
the unchanged copies also fail, as the later experiment demonstrates.

The new `phase3/host/build.py`:

1. Builds an ARM64 iOS host with official UIKit headers and the real iPhoneOS SDK.
2. Embeds the existing macOS guests as base64 resources so the installer's recursive
   executable signing cannot rewrite their embedded signatures.
3. Records original hashes; the host decodes into its own Documents directory and
   verifies bytes both before and after writing.
4. Includes an explicitly separate, recompiled iOS hello admission control.

The host uses UIKit scenes. The initial official-SDK build without a scene lifecycle
failed to reach foreground; adding SceneDelegate and the scene manifest produced a
verified foreground launch. This matches Apple's documented scene migration
requirement for the release after iOS 26 when linked with the latest SDK.

The UI now records each guest's real failure independently instead of leaving
the original misleading “Running framework checks…” message after an early return.
`Documents/probe.json` is persisted before each load/entry stage. The runtime error
includes numeric errno. The loader's signature and library-validation policy remains
the same as Phase 2.

## Measured admission matrix

| File tested in iOS VM | Identity | Signature registration | Library validation | Guest execution |
|---|---|---|---|---|
| Installed UIKit host | Installer-signed iOS app | Pass | Pass | Native host already running |
| Documents copy of host | Exact same bytes as installed host | errno 85 | Not reached | Not attempted |
| iOS hello | Recompiled iOS counterpart, ad-hoc signed | errno 85 | Not reached | Not attempted |
| macOS hello | Unchanged Phase 1 original | errno 85 | Not reached | Not reached |
| macOS interactive | Unchanged Phase 2 original | errno 85 | Not reached | Input not reached |
| macOS file I/O | Unchanged Phase 1 original | errno 85 | Not reached | Not reached |
| macOS CoreFoundation | Unchanged Phase 1 original | errno 85 | Not reached | Not reached |
| macOS Foundation | Unchanged Phase 2 original | errno 85 | Not reached | Not reached |
| macOS Metal device | Unchanged Phase 1 original | errno 85 | Not reached | Not reached |
| macOS Metal compute | Unchanged Phase 2 original | errno 85 | Not reached | Not reached |

No metadata-modified or separately re-signed macOS guest is counted in this matrix.
The earlier installer-modified interactive copy is separate evidence.

## Reproduce

From the repository root, preserving the existing guest binaries:

```sh
python3 phase3/host/build.py
python3 -m unittest discover -s phase3/tests -v
make test test-loader
make -f phase2/Makefile test
make -f phase2/Makefile sanitize
```

Output: `build/phase3-ios/MachProbe.ipa`, bundle ID
`research.machprobe.Admission`. It is locally ad-hoc signed; it is not a provisioned
device distribution package. Install into the existing VM through the vphone
installer. This route registers through vphoned, not ordinary installd signing.

Use `apps.info` to obtain the current data-container path, then read
`<data_path>/Documents/probe.json` with `files.read`. Container UUIDs in evidence
are observations, not stable configuration. `admission-probe.json` records the
final run; `initial-unchanged-probe.json` precedes the admission controls.

Five new tests validate actual IPA contents, raw-guest exclusion, hashes/platforms,
embedded signatures on the native control, scene manifest, and saved evidence
consistency. Their saved-evidence test does not constitute another VM run.
All 48 existing normal tests and 10 Phase 2 sanitizer test methods pass after
the runtime diagnostic change.

## Next bounded experiment

**UNTESTED:** Use supported development signing to compare a provisioned installed
iOS code component with a separately signed macOS copy, preserving the original
guest alongside it. Any signed copy must be labeled as changed. First establish
whether admission works under supported signing before modifying loader behavior.

**UNTESTED:** A debugger/kernel diagnostic may identify the exact errno-85 branch;
no debugger attach or security-policy change was performed in this fix.

The current native unmodified-guest architecture remains blocked at code admission
in this VM. Framework forwarding, CPU ABI, Metal and input cannot be evaluated
here until that gate is resolved. The verified Phase 2 Mac/Catalyst results remain
valid, but cannot fill these iOS result columns.

## Sources

- [Apple: transitioning to the UIKit scene lifecycle](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)
- [Apple XNU: signature validation implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/ubc_subr.c)
- [vphone upstream](https://github.com/Lakr233/vphone-cli)
- [Final in-app report](evidence/phase3/admission-probe.json),
  [installed host metadata](evidence/phase3/installed-host.json),
  [VM observation](evidence/phase3/device.json)
