# Working rules (for contributors and AI agents)

Lessons learned the hard way. Follow them when working on the project.

## The phone is the user's

1. **Never install or relaunch the app without asking** — it kills a game in progress.
2. **Never delete the app** — it wipes the data container (60 GB + saves).
3. **Read logs read-only.** Pulling reports and logs is fine; changing files on the phone isn't, without asking.
4. **Don't overwrite the phone's EULA/settings files** unless restoring on purpose.
5. **One App ID per game.** Installing a different project under the same App ID replaced
   Cyberpunk and wiped its data once. Cyberpunk now uses its own ID.

## Measuring

6. **Measure without shipping when you can.** Instruments (`xctrace`) can attach to a running
   app; telemetry is in the logs. Don't push a new build just to measure.
7. **Never run the game on the Mac** through the loader harness; test on the phone.
8. **Settings traps:** the game's VSync list is dynamic — write `"120"`, never `"60"`.

## Code

9. Never modify game bytes; add adapters outside the game.
10. Keep game assets out of git (icons are generated at build time).
11. Never print or commit tokens, signing identities, device IDs or personal paths. Use placeholders in docs.
12. Prefer real optimization over shortcuts (no upscaling as a substitute for performance work).

## Handoff

13. Keep `CONTEXT.md` up to date at the end of each session: status, plan, settled facts.
14. Start fresh sessions often; `CONTEXT.md` plus these docs are enough to resume.
