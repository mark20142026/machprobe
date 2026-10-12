#pragma once
#include <stdint.h>
typedef struct {
    char output[512];
    char error[256];
    int target_return;
    unsigned mapped_segments, rebases, binds, puts_calls;
    unsigned signature_registered, library_validation_passed;
    uintptr_t entry_address;
} MPHelloResult;
// Only the repository's controlled arm64 macOS hello fixture is supported.
// Executes synchronously in this process. This is not a security boundary.
int mp_run_hello(const char *path, MPHelloResult *result);

// Read-only probe: map one signed file page with R or RX, never execute it.
int mp_mapping_errno(const char *path, int executable);
