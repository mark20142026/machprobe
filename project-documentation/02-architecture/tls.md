# Thread-local variables (`runtime/tls.c`)

Darwin implements `thread_local` / `__thread` with **thread-local variable (TLV)
descriptors**: three words per variable, `{thunk, key, offset}`. Code reads a
variable with `blr` through the descriptor: it loads the thunk from word 0 and
calls it with `x0 = &descriptor`; the thunk returns the variable's address in
`x0`. The loader owns this mechanism for guests because the guest's TLS
template and descriptors live in our mapped image, not in anything dyld knows
about.

Real games use TLS heavily (the Rust game Veloren has 45 TLV descriptors; RED
Engine's allocators and runtime use it constantly), and every access goes through
the thunk. That makes the thunk the hottest piece of loader code.

## How it works

At link time, `mp_prepare_tls` (called from `image_link`) does this:

1. Scans the image's sections: `S_THREAD_LOCAL_REGULAR` and
   `S_THREAD_LOCAL_ZEROFILL` form the per-thread **template** (`state->initial`,
   size capped at 1 MiB, alignment up to 2^20); `S_THREAD_LOCAL_VARIABLES` are
   the descriptor arrays.
2. Allocates a `struct MPTLSImage` and a **per-image pthread key**
   (`pthread_key_create`), registered in a `by_key[1024]` table.
3. Rewrites every descriptor in the mapped (writable) data: `thunk = tls_thunk`,
   `key = <pthread key>`. Offsets must lie inside the template. Guest executable
   bytes are never rewritten; only the data pointers in the descriptor are.

At run time each thread has, per image, a TSD slot (the pthread key) that holds
the base of that thread's copy of the image's TLS block.

### Key functions

| Function | File | What it does |
|---|---|---|
| `mp_prepare_tls` | `runtime/tls.c` | Builds the template, allocates the key, patches descriptors (thunk + key). Fails with "TLS descriptors must be writable", "invalid or oversized TLS template", etc. |
| `tls_thunk` | `runtime/tls.c` | `naked` assembly entry installed in every descriptor: fast path inline, slow path saves registers and calls `tls_address`. |
| `tls_address` | `runtime/tls.c` | Slow path: finds or creates this thread's block for the image, copies the template (`memcpy` of `state->initial`), publishes it with `pthread_setspecific` (both the shared `blocks_key` list and the per-image key), registers teardown. |
| `free_thread_blocks` | `runtime/tls.c` | Thread-exit destructor (registered via `_tlv_atexit`): clears each image's key, frees blocks, decrements `active`. |
| `mp_release_tls` | `runtime/tls.c` | At image close: refuses (returns 0) while any thread still has a block; otherwise deletes the key and frees the template. A refusal pins the image. |
| `mp_image_close`, `image_discard` | `runtime/image.c` | Call `mp_release_tls`; if it refuses, set `pinned` instead of unmapping. |

## The fast path (commit `25bef28`)

```asm
mrs  x16, TPIDRRO_EL0            ; thread pointer (TSD base)
and  x16, x16, #~7               ; mask the low 3 bits, as dyld does
ldr  x17, [x0, #8]               ; descriptor->key  (pthread key = TSD index)
ldr  x16, [x16, x17, lsl #3]     ; TSD[key] = this thread's block base for this image
cbz  x16, slow                   ; not created yet on this thread
ldr  x17, [x0, #16]              ; descriptor->offset
add  x0, x16, x17                ; return &variable in x0
ret
```

It uses only `x16`/`x17` besides `x0`, exactly like dyld's own `tlv_get_addr`
(Apple dyld `libdyld/threadLocalHelpers.s`, referenced in
`docs/phase5.5-findings.md`). This matters because the Darwin TLV calling
convention says the thunk preserves **all** registers other than `x0`, `x16`,
`x17`; the compiler relies on that and keeps live values in caller-saved registers
across `blr`.

## The slow path

Only the *first* access to an image's TLS on each thread takes it. It must keep
the same contract, so the thunk:

- saves `x1`-`x15` and `x18` (everything the normal C ABI would let a callee
  clobber, except `x0`/`x16`/`x17`) and all 32 SIMD registers `q0`-`q31`
  (640 bytes of stack),
- calls the C function `tls_address`,
- restores everything and returns the address in `x0`.

`tls_address` aborts on any inconsistency (unknown key, allocation failure)
rather than returning a bad pointer: a wrong TLS address would be silent memory
corruption.

## Teardown ordering

The first TLS allocation on a thread calls `_tlv_atexit(free_thread_blocks, NULL)`
**before any guest `_tlv_atexit` callback can exist** (the guest cannot have run
TLS-using code on that thread yet). dyld runs `_tlv_atexit` callbacks LIFO, so
guest destructors run first, and our block freeing runs last. The source comment
states the intent: guest objects are destroyed first, "including callbacks which
use TLS from another loaded image". If our cleanup ran earlier, a guest
destructor touching a thread-local from another image would read freed memory.

`free_thread_blocks` also clears the per-image key to NULL before freeing, so
the fast path cannot return a dangling base on a reused thread.

Image unload: the owner must join guest threads first. `mp_release_tls` refuses
while `active > 0`, and the image then stays pinned for process lifetime rather
than leaving code or data that a live thread's TLS callbacks could still touch
(`docs/phase5.5-findings.md`, "TLS design and evidence").

## Design decisions

- **Per-image pthread key instead of a global list.** Before the fast path, the
  thunk always took the slow route: `pthread_once`, `pthread_getspecific` of a
  list head, then a linked-list walk comparing `image` pointers, with a
  640-byte register spill around the C call, on *every* access. The key lookup
  is the same indirection dyld uses and costs a handful of instructions with no
  call, no spill and no list walk.
- **Key stored in the descriptor.** The descriptor's word 1 holds the key (as dyld's
  do), and the slow path maps key back to image via `by_key[]`
  (`pthread_key_create` keys are small integers; the table has 1024 entries and
  `mp_prepare_tls` rejects a key >= 1024). Before the commit, word 1 held the
  `MPTLSImage` pointer directly.
- **Mask `TPIDRRO_EL0` before indexing.** The thunk clears the low three bits
  (`and x16, x16, #~7`) exactly as the dyld thunk does before using it as the TSD base.
- **Why it matters for performance.** The commit message calls it "Performance:
  dyld-style TLS fast path; no per-frame overhead in our layer". Cyberpunk is
  GPU-bound on the phone (command-buffer GPU time ~300 percent, main thread ~1 percent,
  CPU ~2 of 6 cores in `CONTEXT.md` telemetry), so this was about making sure the
  *layer* adds nothing per frame. The repository does not record a before/after
  frame-time measurement for this change; treat the benefit as removing a
  known per-access cost rather than a measured speedup.
- **Tested.** Phase 5.5 TLS tests (288 workers, 12 unload cycles) passed after
  the change (commit `25bef28`; `phase5_5/guests/tls.c`, `docs/evidence/phase5.5/tls-tests.txt`).

## Related limits

- TLS *initializer function pointers* (`S_THREAD_LOCAL_INIT_FUNCTION_POINTERS`)
  and `S_MOD_TERM_FUNC_POINTERS` are rejected at parse time
  (`TLS/terminators unsupported`).
- A TLS template over 1 MiB is rejected.
- Guest `thread_local` destructors are supported through the host's
  `_tlv_atexit`, because the guest imports `_tlv_atexit` and we bind it to the
  real one.

See [loader.md](loader.md) for where `mp_prepare_tls` sits in the link phase and
[../03-phase-history/](../03-phase-history/) for the Veloren work that introduced
TLS.
