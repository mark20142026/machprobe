# Phase history

> Not piracy: no game files are included; you need your own copy. MIT-licensed. See [../NOTICE.md](../NOTICE.md).

This section records how machprobe was built, phase by phase: the goal, what
was actually built, the steps taken, the problems found, how they were hunted
down, how they were fixed, and what the evidence shows. Each phase file uses
the same structure so they can be compared directly.

Sources are the repository itself: `README.md`, `progress.md`, `CONTEXT.md`,
`docs/phase*-findings.md`, `docs/phase*-report.md`, the `phase*/` directories,
and the git history. Dates are commit dates from `git log` (author date, short
format). Commit hashes are short hashes from the same log.

Conventions used in these files:

- **VERIFIED / UNTESTED / HYPOTHESIS** follow the labels used in the original
  findings documents. "Verified" means observed in this repository's recorded
  environment, not a general compatibility claim.
- "Unknown" means the repository does not record the answer. It is not filled
  in by inference.
- Personal identifiers (device IDs, signing team IDs, identity hashes, account
  names, e-mail addresses) are replaced with placeholders such as
  `<DEVICE-UDID>` or `<TEAM-ID>`, and home paths are written as `~`.

## Phases

| File | Phase |
|---|---|
| [phase-1-inspector.md](phase-1-inspector.md) | 1. Mach-O inspector and controlled macOS samples |
| [phase-2-controlled-runtime.md](phase-2-controlled-runtime.md) | 2. In-process runtime, Catalyst host, ABI and Metal compute |
| [phase-3-ios-admission.md](phase-3-ios-admission.md) | 3. First iOS VM run and the signature-registration gate |
| [phase-4-dashboardcalculator.md](phase-4-dashboardcalculator.md) | 4. Unchanged SwiftUI calculator running in the iOS VM |
| [phase-4.5-metal-arena.md](phase-4.5-metal-arena.md) | 4.5. Native Metal workload embedded in the iOS container |
| [phase-5-strataris.md](phase-5-strataris.md) | 5. Unchanged Strataris gameplay (AppKit and Metal adapters) |
| [phase-5.5-veloren.md](phase-5.5-veloren.md) | 5.5. Veloren: large image loading, TLS, input, first gameplay |
| [phase-6-supertuxkart.md](phase-6-supertuxkart.md) | 6. SuperTuxKart 1.5 with multi-image guest groups |
| [phase-7-physical-iphone.md](phase-7-physical-iphone.md) | 7. SuperTuxKart on a physical iPhone 18 Pro |
| [phase-8-cyberpunk-overview.md](phase-8-cyberpunk-overview.md) | 8. Cyberpunk 2077 (overview only; see `../04-cyberpunk/`) |

## Timeline

Phase names follow the repository's own labels in `progress.md` and
`CONTEXT.md`. Results are stated as they were recorded at the end of each
phase. "Not complete" means the repository says so.

| Phase | Goal | Result | Date range (git) | Commits |
|---|---|---|---|---|
| 1 Inspector | Build a Mach-O inspector and four controlled ARM64 macOS samples | Done. Inspector, 30 tests, evidence capture. No macOS executable run on iOS. | 2026-10-01 | `0030ed5`..`c2333fe` |
| 2 Controlled runtime | Load unchanged macOS guests inside a UIKit/Catalyst host | Done on macOS/Catalyst, all seven controlled guests. No iOS result. | 2026-10-01 | `6f6f606`..`56d849c` |
| 3 iOS admission | Run the guests in the iOS 27 VM | Standalone guests blocked at signature registration (errno 85). Guests then ran when embedded in a signed iOS container. | 2026-10-01 | `345af7f`..`989e3d9` |
| 4 DashboardCalculator | Run the unchanged SwiftUI calculator in the VM | Done in the VM: 2 + 2 = 4 and 7 x 8 = 56. Ordinary signing unverified. | 2026-10-01 | `0073476`..`aaa8b5f` |
| 4.5 Metal arena | Measure a native Metal workload inside the iOS container | Sustained run at about 29.5 fps with Metal validation on, 0 GPU errors. No findings document. | 2026-10-01 | `fd1ccdc` |
| 5 Strataris | Run unchanged Strataris gameplay | Title, briefing, cockpit, movement and firing observed. Stopped at user request. Audio failed. | 2026-10-01 | `d1e2146`, `cebead4` |
| 5.5 Veloren | Run the large Veloren Rust/wgpu build | Gameplay observed in the VM. Not complete: audio, ordinary signing, stability open. | 2026-10-01 | `9df8ec4`..`ba9e9b8` |
| 6 SuperTuxKart | Run SuperTuxKart 1.5 with 19 linked images | Playable in the VM at about 55-60 fps. Audio and touch controls open. | 2026-10-07 | `da59c42`..`cd4145c` |
| 7 Physical iPhone | Run SuperTuxKart on the user's iPhone 18 Pro | Runs at 60 fps with a touch gamepad. | 2026-10-09 | `cdcbf0c`..`5f24c6f` |
| 8 Cyberpunk 2077 | Run Cyberpunk 2077 on the same iPhone | Playable end to end. About 22-24 fps in the city, GPU-bound, heat-limited. In progress. | 2026-10-09 to 2026-10-10 | `e831216`..`5e022eb` |

## Recurring themes

Several problems came back in different phases. They are listed here once,
with pointers to the phase where each was handled.

- **Signature registration and admission.** The gate that decided whether an
  unchanged macOS image could be mapped was the first real barrier (Phases 1,
  3). The working answer was to embed the original bytes in a separately signed
  iOS container, which leaves the guest bytes unchanged (Phases 3, 4, 4.5).
- **Mac-only APIs.** Each game asked for APIs that iOS does not have or answers
  differently: AppKit classes, CoreGraphics display queries, `MTLDevice` queries
  and Managed storage (Phases 4-8).
- **Metal differences.** Legacy Mac feature-set answers, BC texture support,
  MTLHeap placement, a 16-bit `baseVertex` defect in the VM GPU, and heap
  limits on the phone (Phases 5, 5.5, 6, 8).
- **Audio never worked in the VM.** Audio initialization returned -10851
  (AVAudioEngine in Phase 5, RemoteIO in Phase 5.5), and Phase 6 found no VM
  output route. No phase records a working audio path. Phases 7 and 8 do not
  record audio results in the repository.
- **Research-VM trust dependency.** The VM installer added custom trust
  entitlements. Every VM result is labelled as depending on that. Ordinary
  signing was never verified in the VM. Phase 7 is the first run on a real
  device with a development profile.
- **Test and evidence discipline.** Each phase kept an evidence directory under
  `docs/evidence/` and test counts in its report. Later phases re-ran earlier
  test suites as regressions.
