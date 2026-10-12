# machprobe — project documentation

> **Not piracy.** machprobe contains no game files. It runs **your own** purchased macOS copy of a
> game on **your own** iPhone. MIT-licensed. **Read [NOTICE.md](NOTICE.md) first.**

machprobe is a macOS → iOS translation layer that runs unmodified Apple-silicon Mac games on
iPhone. Its headline result: **Cyberpunk 2077 (Steam macOS build) playable on an iPhone 18 Pro**.

## Sections

| # | Section | Read it if you want to… |
|---|---|---|
| — | [NOTICE.md](NOTICE.md) | know what this is and isn't: legality, licence, privacy, requirements |
| 00 | [Overview](00-overview/) | understand the project in 10 minutes, see status, tested hardware, glossary |
| 01 | [Getting started](01-getting-started/) | set it up yourself, step by step: requirements → profile → build → copy data → play |
| 02 | [Architecture & code](02-architecture/) | learn how the loader, TLS, memory, AppKit-on-UIKit, Metal and system services work, function by function |
| 03 | [Phase history](03-phase-history/) | follow how the project was built, phase by phase, with the bugs and fixes of each step |
| 04 | [Cyberpunk 2077](04-cyberpunk/) | read the full bring-up story, the bug log, memory, performance and controls |
| 05 | [Tools & diagnostics](05-tools-and-diagnostics/) | use the build/phone scripts, read telemetry, debug crashes, run tests |
| — | [videos.md](videos.md) | record the demo videos (shot list, privacy rules) |
| 06 | [Policies & roadmap](06-policies-and-roadmap/) | read the legal, privacy and working rules, the roadmap, and porting other games |

## Suggested reading paths

- **"I want to play it."** NOTICE → 00/what-to-expect → 00/tested-hardware → the main [README](../README.md) (Part 1 with an AI agent, Part 2 by hand) → 01 for details.
- **"I want to understand how it works."** 00/how-it-works-in-5-minutes → 02 → 05/telemetry.
- **"I want the story."** 03 (phase by phase) → 04/bring-up-journal → 04/bug-log.
- **"I want to port another game."** 06/porting-other-games → 02 → 05/debugging-playbook → 04/bug-log.

## Conventions

- Paths are relative to the repository root (e.g. `phase8/runtime/CPMetal.m`).
- Commit hashes are short git hashes, e.g. `ed2227a`.
- Personal identifiers are placeholders: `<DEVICE-UDID>`, `<TEAM-ID>`, `<SIGNING-IDENTITY-SHA1>`.
- "Unknown" means the repository doesn't record it. Nothing here is guessed on purpose.
