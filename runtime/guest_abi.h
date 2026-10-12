#pragma once
#include <stddef.h>
#include <stdint.h>
#define MP_ABI_VERSION 1u
enum { MP_INCREMENT=1, MP_DECREMENT=2, MP_RESET=3 };
typedef struct { uint32_t size, type; int64_t amount; } MPEvent;
typedef struct { int64_t counter; uint64_t sequence; } MPState;
typedef struct {
    uint32_t size, version;
    void *context;
    void (*changed)(void *context, MPState state, const char *message);
} MPHost;
typedef struct {
    uint32_t size, version;
    void *context;
    int (*event)(void *context, const MPEvent *event, MPState *result);
    void (*destroy)(void *context);
} MPGuest;
typedef int (*MPOpenGuest)(const MPHost *, MPGuest *);
// Buffers and callback strings are borrowed only for the duration of the call.
// Host must destroy guest state before unloading its image. Calls are synchronous.
