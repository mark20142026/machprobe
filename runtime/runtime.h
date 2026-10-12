#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct MPImage MPImage;
typedef struct {
    int allow_class_metadata;
    int allow_weak_imports;
    int (*library_allowed)(const char *name);
    void *(*resolve)(const char *library, const char *symbol);
    int allow_chained_fixups;
    // Zero keeps the 64 MiB fixture limit. Hosts may opt in up to 512 MiB.
    size_t max_image_bytes;
    int allow_thread_locals;
    int allow_weak_coalescing;
    unsigned max_fixups; // Zero keeps 8192 per kind; ceiling is 1048576.
    void *(*resolve_lazy)(const char *library,const char *symbol);
    // Group opens only: admit MH_DYLIB members, apply compiled Objective-C
    // categories, and register each member's metadata after every member is
    // linked and before any initializer runs (dyld's map_images ordering).
    int allow_guest_dylibs;
    int allow_categories;
    int (*register_metadata)(MPImage *image,char error[256]);
    // Diagnostics only: report each import that fails to resolve (lazy=1 for
    // lazy binds) instead of failing the link, and stop a group after linking
    // so no guest code ever runs with those zero-filled slots.
    void (*unresolved)(MPImage *image,const char *library,const char *symbol,int lazy);
} MPExtensions;
typedef struct {
    void *context;
    void (*output)(void *context, const char *bytes, size_t length);
    const MPExtensions *extensions; // Optional, immutable for the image lifetime.
    int argc;
    char **argv; // Optional guest startup arguments; storage lives with image.
} MPServices;
typedef struct {
    unsigned segments, rebases, binds, selectors, initializers;
    unsigned signature_registered, library_validation_passed;
} MPStats;
// Only controlled, trusted fixtures. This loader provides no isolation.
// Calls on each image are synchronous and serialized by its owner. Destroy all
// guest contexts, finish callbacks and release guest-backed objects before close.
// mp_image_main activates output capture; raw exported calls use their explicit
// callback ABI. Export pointers are invalid immediately after image_close.
MPImage *mp_image_open(const char *path, MPServices services, char error[256]);
// Load a guest prepackaged in a signed, dyld-loaded container. Its __TEXT and
// __DATA __guest sections preserve contiguous file bytes. The data section may
// include trailing reserved capacity for virtual zero-fill gaps.
// resident_section is that loaded __TEXT,__guest address. The caller owns the
// dlopen handle and must keep it until close. One active image per container.
// Admission uses the container signature: this is build-time packaging, not
// admission of arbitrary downloaded macOS executables.
MPImage *mp_image_open_embedded(const char *host_path, const char *section, void *resident_section, size_t guest_size,
                              MPServices services, char error[256]);
void *mp_image_symbol(MPImage *image, const char *macho_name);
// One link unit: sources[0] is the main executable, the rest are the guest
// dylibs it ships (in any order). All members are mapped, then all are bound
// (imports naming a member's install name resolve to that member; @-relative
// names also match by basename), then initializers run dependencies first and
// the main executable last. Weak definitions coalesce in member order, so the
// main executable wins as with dyld. Guest dlopen/dlsym/dladdr see members.
// A failed or opened group is process-lifetime: members are never unloaded.
typedef struct MPGroup MPGroup;
typedef struct {
    const char *path;    // File to admit: the guest itself, or its signed container.
    const char *section; // NULL maps the file directly; otherwise embedded segment name.
    void *resident;      // Embedded only: the container's loaded __guest address.
    size_t size;         // Embedded only: original guest byte count.
} MPGuestSource;
MPGroup *mp_group_open(const MPGuestSource *sources, unsigned count, MPServices services, char error[256]);
unsigned mp_group_count(const MPGroup *group);
MPImage *mp_group_image(MPGroup *group, unsigned index);
const char *mp_image_install_name(const MPImage *image);
int mp_image_main(MPImage *image, int argc, char **argv, int *guest_result);
void mp_image_close(MPImage *image);
// Metadata published to host runtimes has process lifetime. Pin BEFORE publishing;
// close then intentionally retains mappings, and the caller must retain dlopen.
void mp_image_pin(MPImage *image);
void *mp_image_section(MPImage *image, const char *name, size_t *size);
MPStats mp_image_stats(const MPImage *image);
const char *mp_image_error(const MPImage *image);
size_t mp_live_images(void);
// Configure the explicit AppKit shim before loading any image. Other imports
// retain the runtime whitelist; this resolver is never used for arbitrary dylibs.
int mp_set_appkit_resolver(void *(*resolver)(const char *symbol));
#ifdef __cplusplus
}
#endif
