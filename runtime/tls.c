#include "internal.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <mach-o/dyld.h>

// Disk TLV descriptors use the SDK's three-word ABI. Our thunk replaces only
// their mapped data pointers; guest executable bytes are never rewritten.
struct MPTLSImage {
    unsigned char *initial;
    size_t size, alignment;
    _Atomic unsigned active;
    pthread_key_t key; // This thread's block base, read directly by the thunk's fast path.
};
// Descriptors carry the image's pthread key, as dyld's do; the slow path maps
// it back to the image.
static struct MPTLSImage *_Atomic by_key[1024];
typedef struct MPTLSBlock {
    struct MPTLSBlock *next;
    struct MPTLSImage *image;
    void *bytes;
} TLSBlock;
static pthread_once_t key_once=PTHREAD_ONCE_INIT;
static pthread_key_t blocks_key;
static void make_key(void) {if(pthread_key_create(&blocks_key,NULL))abort();}
static void free_thread_blocks(void *unused) {
    (void)unused;
    TLSBlock *block=pthread_getspecific(blocks_key);
    pthread_setspecific(blocks_key,NULL);
    while(block) {
        TLSBlock *next=block->next;
        pthread_setspecific(block->image->key,NULL);
        free(block->bytes);
        atomic_fetch_sub(&block->image->active,1);
        free(block);block=next;
    }
}
// The first thread allocation registers cleanup with dyld before any guest
// _tlv_atexit callbacks. LIFO teardown therefore destroys guest objects first,
// including callbacks which use TLS from another loaded image.
__attribute__((noinline,used))
static void *tls_address(struct tlv_descriptor *descriptor) {
    struct MPTLSImage *state=descriptor->key<1024?by_key[descriptor->key]:NULL;if(!state)abort();
    if(pthread_once(&key_once,make_key))abort();
    TLSBlock *head=pthread_getspecific(blocks_key);
    for(TLSBlock *b=head;b;b=b->next)
        if(b->image==state)return (char *)b->bytes+descriptor->offset;
    TLSBlock *block=calloc(1,sizeof *block);
    if(!block || posix_memalign(&block->bytes,state->alignment,state->size))abort();
    memcpy(block->bytes,state->initial,state->size);
    block->image=state;block->next=head;
    atomic_fetch_add(&state->active,1);
    if(pthread_setspecific(blocks_key,block) || pthread_setspecific(state->key,block->bytes))abort();
    if(!head)_tlv_atexit(free_thread_blocks,NULL);
    return (char *)block->bytes+descriptor->offset;
}

// Darwin TLV calls preserve registers beyond the normal C ABI (Apple dyld's
// libdyld/threadLocalHelpers.s). Fast path, as dyld's: the thread's TSD slot
// for the image key holds the block base (x16/x17 scratch only). First access
// on a thread takes the slow path, which saves every SIMD register plus the
// volatile integer registers other than x0/x16/x17.
__attribute__((naked)) static void *tls_thunk(struct tlv_descriptor *descriptor) {
    __asm__ volatile(
        "mrs x16, TPIDRRO_EL0\nand x16, x16, #0xfffffffffffffff8\n"
        "ldr x17, [x0, #8]\nldr x16, [x16, x17, lsl #3]\n"
        "cbz x16, 1f\nldr x17, [x0, #16]\nadd x0, x16, x17\nret\n"
        "1:\n"
        "stp x29, x30, [sp, #-16]!\nmov x29, sp\nsub sp, sp, #640\n"
        "stp x1, x2, [sp, #0]\nstp x3, x4, [sp, #16]\n"
        "stp x5, x6, [sp, #32]\nstp x7, x8, [sp, #48]\n"
        "stp x9, x10, [sp, #64]\nstp x11, x12, [sp, #80]\n"
        "stp x13, x14, [sp, #96]\nstp x15, x18, [sp, #112]\n"
        "stp q0, q1, [sp, #128]\nstp q2, q3, [sp, #160]\n"
        "stp q4, q5, [sp, #192]\nstp q6, q7, [sp, #224]\n"
        "stp q8, q9, [sp, #256]\nstp q10, q11, [sp, #288]\n"
        "stp q12, q13, [sp, #320]\nstp q14, q15, [sp, #352]\n"
        "stp q16, q17, [sp, #384]\nstp q18, q19, [sp, #416]\n"
        "stp q20, q21, [sp, #448]\nstp q22, q23, [sp, #480]\n"
        "stp q24, q25, [sp, #512]\nstp q26, q27, [sp, #544]\n"
        "stp q28, q29, [sp, #576]\nstp q30, q31, [sp, #608]\n"
        "bl _tls_address\n"
        "ldp q0, q1, [sp, #128]\nldp q2, q3, [sp, #160]\n"
        "ldp q4, q5, [sp, #192]\nldp q6, q7, [sp, #224]\n"
        "ldp q8, q9, [sp, #256]\nldp q10, q11, [sp, #288]\n"
        "ldp q12, q13, [sp, #320]\nldp q14, q15, [sp, #352]\n"
        "ldp q16, q17, [sp, #384]\nldp q18, q19, [sp, #416]\n"
        "ldp q20, q21, [sp, #448]\nldp q22, q23, [sp, #480]\n"
        "ldp q24, q25, [sp, #512]\nldp q26, q27, [sp, #544]\n"
        "ldp q28, q29, [sp, #576]\nldp q30, q31, [sp, #608]\n"
        "ldp x1, x2, [sp, #0]\nldp x3, x4, [sp, #16]\n"
        "ldp x5, x6, [sp, #32]\nldp x7, x8, [sp, #48]\n"
        "ldp x9, x10, [sp, #64]\nldp x11, x12, [sp, #80]\n"
        "ldp x13, x14, [sp, #96]\nldp x15, x18, [sp, #112]\n"
        "mov sp, x29\nldp x29, x30, [sp], #16\nret\n");
}

int mp_prepare_tls(Image *im) {
    uint64_t low=UINT64_MAX,high=0;size_t alignment=sizeof(void *);
    unsigned descriptors=0;
    for(unsigned i=0;i<im->section_count;i++) {
        struct section_64 *s=&im->sections[i];unsigned type=s->flags&SECTION_TYPE;
        if(type==S_THREAD_LOCAL_VARIABLES)descriptors++;
        if(type!=S_THREAD_LOCAL_REGULAR && type!=S_THREAD_LOCAL_ZEROFILL)continue;
        if(s->align>20)return mp_fail(im,"TLS alignment limit");
        size_t a=(size_t)1<<s->align;if(a>alignment)alignment=a;
        if(s->addr<low)low=s->addr;
        if(s->addr+s->size>high)high=s->addr+s->size;
    }
    if(!descriptors && !high)return 1;
    if(!descriptors || high<=low || high-low>1024u*1024u)return mp_fail(im,"invalid or oversized TLS template");
    struct MPTLSImage *state=calloc(1,sizeof *state);
    if(!state)return mp_fail(im,"TLS allocation failed");
    im->tls=state;state->size=(size_t)(high-low);state->alignment=alignment;
    if(pthread_key_create(&state->key,NULL) || state->key>=1024)return mp_fail(im,"TLS key allocation failed");
    by_key[state->key]=state;
    state->initial=calloc(1,state->size);
    if(!state->initial)return mp_fail(im,"TLS template allocation failed");
    for(unsigned i=0;i<im->section_count;i++) {
        struct section_64 *s=&im->sections[i];unsigned type=s->flags&SECTION_TYPE;
        void *address=im->base+(s->addr-im->low);
        if(type==S_THREAD_LOCAL_REGULAR)memcpy(state->initial+s->addr-low,address,(size_t)s->size);
        if(type!=S_THREAD_LOCAL_VARIABLES)continue;
        if(s->addr%8 || s->size%sizeof(struct tlv_descriptor))return mp_fail(im,"invalid TLS descriptor section");
        int writable=0;
        for(unsigned j=0;j<im->count;j++) {
            struct segment_command_64 *seg=&im->segments[j];
            if(s->addr>=seg->vmaddr && s->addr-seg->vmaddr<seg->vmsize && (seg->initprot&VM_PROT_WRITE))writable=1;
        }
        if(!writable)return mp_fail(im,"TLS descriptors must be writable");
        struct tlv_descriptor *d=address;
        for(size_t j=0;j<s->size/sizeof *d;j++) {
            if(d[j].offset>=state->size)return mp_fail(im,"TLS descriptor offset outside template");
            d[j].key=state->key;d[j].thunk=tls_thunk;
        }
    }
    return 1;
}
int mp_release_tls(Image *im) {
    if(!im->tls)return 1;
    // Owner must join guest threads before close. Outstanding main-thread TLS
    // and its callbacks pin the image rather than leaving dangling code/data.
    if(atomic_load(&im->tls->active))return 0;
    by_key[im->tls->key]=NULL;pthread_key_delete(im->tls->key);
    free(im->tls->initial);free(im->tls);im->tls=NULL;return 1;
}
