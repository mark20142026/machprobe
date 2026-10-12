#pragma once
#include "runtime.h"
#include <mach-o/loader.h>
#define MAX_SEGMENTS 16
#define MAX_SECTIONS 96
#define MAX_LIBRARIES 64
#define MAX_IMAGE (64u * 1024u * 1024u)
struct MPImage {
    const unsigned char *file;
    size_t file_size;
    struct segment_command_64 segments[MAX_SEGMENTS];
    struct section_64 sections[MAX_SECTIONS];
    struct symtab_command symtab;
    const char *libraries[MAX_LIBRARIES];
    unsigned count, section_count, library_count;
    uint64_t low, span;
    unsigned char *base;
    int resident, resident_fd, pinned;
    uint64_t source_offset;
    size_t resident_capacity, resident_text_size;
    struct MPImage *next_resident;
    uintptr_t entry;
    MPStats stats;
    MPServices services;
    struct MPTLSImage *tls;
    // Multi-image (group) state. A group is one link unit: its main executable
    // and the guest dylibs it ships. Single-image opens leave these empty.
    int dylib;
    const char *install_name;
    struct MPGroup *group;
    struct MPImage *dependencies[MAX_LIBRARIES]; // Guest image per library ordinal, or NULL for host.
    struct MPExports *exports;
    struct dyld_info_command dyld;
    struct linkedit_data_command chains,exports_trie; // exports_trie: LC_DYLD_EXPORTS_TRIE (else dyld_info.export_*).
    unsigned chains_count;
    uint64_t entryoff;
    int dl_token; // Address identifies this image as a guest dlopen handle.
    char error[256];
};
typedef struct MPImage Image;
#define MAX_GROUP 32
struct MPGroup { Image *images[MAX_GROUP]; unsigned count; };
static inline unsigned mp_fixup_limit(const Image *im) {
    return im->services.extensions && im->services.extensions->max_fixups?
        im->services.extensions->max_fixups:8192;
}
extern _Thread_local Image *mp_active;
int mp_fail(Image *,const char *);
int mp_library_allowed(const char *);
void *mp_resolve(Image *,const char *,const char *);
void *mp_resolve_weak(Image *,const char *);
int mp_prepare_objc(Image *);
int mp_initialize(Image *);
int mp_prepare_tls(Image *);
int mp_release_tls(Image *);
int mp_apply_rebase(Image *,uint32_t,uint32_t);
int mp_apply_bind(Image *,uint32_t,uint32_t,int);

int mp_apply_chains(Image *,uint32_t,uint32_t);
// Exports from the immutable symbol table, hashed on first use.
void *mp_export(Image *,const char *symbol,int *weak);
Image *mp_group_find(struct MPGroup *,const char *install_name);
void *mp_resolve_special(Image *,int ordinal,const char *symbol);
void *mp_group_dl_import(const char *symbol);
void mp_register_unwind_image(Image *);
void mp_unregister_unwind_image(Image *);
void mp_group_activate(struct MPGroup *);
