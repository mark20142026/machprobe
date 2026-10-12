# Project status (October 2026)

## Works

| Area | State |
|---|---|
| Cyberpunk 2077 boots on iPhone 18 Pro | ✅ Main menu, loads saves, open world, driving |
| Input | ✅ Touch menus (tap/scroll), touch gamepad, Xbox controller |
| Resolution | ✅ Aspect-correct native modes (e.g. 1564×720, 1956×900) |
| Offline play | ✅ Network services answer "offline" cleanly |
| App identity | ✅ Own App ID, real icon generated from the user's install, name "Cyberpunk 2077" |
| SuperTuxKart | ✅ 60 fps on the physical iPhone (phase 7) |

## Measured performance (Cyberpunk, user-tuned settings)

- In-game benchmark: **39.44 fps average** at 1564×720.
- City driving: **30s to ~40 fps**, mostly GPU-bound.
- Overhead of the layer: **~1–5%**. The game's own code runs natively; Metal is pass-through.
- Recommended settings: `phase8/config-recommended-UserSettings.json`
  (details in [../04-cyberpunk/performance.md](../04-cyberpunk/performance.md)).

## Open problems

| Problem | Notes |
|---|---|
| Memory kills during bursts (crashes, max settings) | iOS limit ≈ 6 GB; kills seen at ~250–350 MB free |
| Slow `MALLOC_SMALL` growth ≈ 1.4 MB/s | Leak hunt pending; autorelease-pool theory |
| Heat | Phone throttles within minutes at uncapped fps; fps cap helps most |
| Touch controls | Work, but the layout is a quick hack; rebuild planned |
| Signing | Free profiles expire every 7 days; re-sign and reinstall over the same App ID |

## Next (agreed plan)

1. Touch-controls rebuild
2. 120 Hz in menus, 60 fps cap in gameplay (optional 40 "cool" mode)
3. Measured resolution-vs-performance table
4. In-app Steam QR sign-in and download of the user's own copy

Full roadmap: [../06-policies-and-roadmap/roadmap.md](../06-policies-and-roadmap/roadmap.md).
