# Hardware, heat and limits

Some limits are iOS policy, some are physics. Knowing which is which saves a lot of wasted effort.

## Memory

| Fact | Value |
|---|---|
| Physical RAM (iPhone 18 Pro) | 12 GB |
| What one app may use (default) | ~3.4 GB |
| With `com.apple.developer.kernel.increased-memory-limit` | ~6 GB (works on a free account) |
| `increased-debugging-memory-limit`, `extended-virtual-addressing` | Not allowed for free (personal) teams |

**Where does the other ~6 GB go?** iOS itself, the GPU's shared memory, the display/camera
pipelines, other apps kept in memory, and a safety margin. On iPhone, CPU and GPU share
the same RAM, so the game's textures count against the same limit as its code and data.

**What counts:** `phys_footprint` — dirty memory plus GPU allocations. Purgeable (volatile)
memory isn't counted. Exceeding the limit = instant kill (jetsam), no crash report.

## Address space

iOS gives an app a ~64 GB window (`0x7000000000–0x8000000000`) plus ~1.5 GB of low memory;
anything else is refused even with `MAP_FIXED`. Cyberpunk's RED Engine wants 16 + 64 + 32 GB
regions, so machprobe rations them inside the window. On macOS the same game has terabytes of room.

## GPU

The A20 Pro GPU runs the game's Metal code natively. In the city the game is **GPU-bound**;
the translation layer costs ~1–5%. Lowering resolution or GPU-heavy settings helps; CPU-side
optimization of the layer can't add much more.

## Heat

- The 18 Pro (not Max) throttles within minutes at uncapped fps; a bigger vapor chamber
  doesn't change that the phone has to shed several watts through glass and aluminium.
- Charging while playing adds heat.
- What helps, in order: **fps cap (60 or 40)** → lower resolution → an external
  **magnetic Peltier cooler**. A "PC cooler" would help only as much as heat can cross from
  the chip to the back of the phone.
- The `[perf]` telemetry line reports iOS's thermal state so throttling shows up in logs.

## Signing

Free developer profiles expire after **7 days**. When they expire the app stops launching
but stays installed **with its data**; re-signing and installing over the same App ID fixes
it. Deleting the app deletes the 60 GB of data and the saves.
