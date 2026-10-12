// Cross-image services for group opens: hashed exports, special bind
// ordinals, guest-aware dlopen family and libunwind section lookup.
#include "internal.h"
#include <dlfcn.h>
#include <TargetConditionals.h>
#include <mach-o/nlist.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---- Exports --------------------------------------------------------------
// Defined external symbols from the immutable file symtab (the same source as
// the original single-image lookup), in an open-addressed FNV-1a table.
struct MPExport {const char *name;uint64_t value;uint16_t desc;};
struct MPExports {struct MPExport *slots;size_t mask;};
static pthread_mutex_t export_lock=PTHREAD_MUTEX_INITIALIZER;
static uint64_t hash(const char *s) {uint64_t h=1469598103934665603ull;while(*s)h=(h^(unsigned char)*s++)*1099511628211ull;return h;}
static int uleb(const unsigned char **p,const unsigned char *end,uint64_t *v) {
    *v=0;for(unsigned shift=0;*p<end && shift<64;shift+=7){unsigned char c=*(*p)++;*v|=(uint64_t)(c&127)<<shift;if(!(c&128))return 1;}return 0;
}
// Recursive walk of the <mach-o/loader.h> EXPORT_SYMBOL trie: each node has
// terminal info (flags, then address or re-export data) and child edges.
// With e==NULL it only counts entries (to size the table).
struct TrieWalk {Image *im;struct MPExports *e;const unsigned char *trie;uint64_t size;char name[4096];size_t count;};
static int trie_node(struct TrieWalk *w,uint64_t node,size_t prefix,unsigned depth) {
    if(node>=w->size || depth>512)return mp_fail(w->im,"bad export trie node");
    const unsigned char *p=w->trie+node,*end=w->trie+w->size;uint64_t terminal;
    if(!uleb(&p,end,&terminal) || terminal>(uint64_t)(end-p))return mp_fail(w->im,"bad export trie terminal");
    if(terminal) {
        const unsigned char *t=p;uint64_t flags,address;
        if(!uleb(&t,p+terminal,&flags))return mp_fail(w->im,"bad export flags");
        // Re-exports and absolute symbols are not exported by these guests.
        if(!(flags&EXPORT_SYMBOL_FLAGS_REEXPORT) && (flags&EXPORT_SYMBOL_FLAGS_KIND_MASK)!=EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE && uleb(&t,p+terminal,&address) && address<w->im->span) {
            w->count++;
            if(w->e) {
                w->name[prefix]=0;size_t slot=hash(w->name)&w->e->mask;int present=0;
                for(;w->e->slots[slot].name;slot=(slot+1)&w->e->mask)if(!strcmp(w->e->slots[slot].name,w->name)){present=1;break;}
                if(!present)w->e->slots[slot]=(struct MPExport){strdup(w->name),w->im->low+address,(uint16_t)((flags&EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION)?N_WEAK_DEF:0)};
            }
        }
        p+=terminal;
    }
    if(p>=end)return mp_fail(w->im,"truncated export trie");
    unsigned children=*p++;
    for(unsigned c=0;c<children;c++) {
        const unsigned char *edge=p;while(p<end && *p)p++;
        if(p>=end)return mp_fail(w->im,"unterminated export edge");
        size_t len=(size_t)(p-edge);p++;uint64_t child;
        if(!uleb(&p,end,&child))return mp_fail(w->im,"bad export child");
        if(prefix+len>=sizeof w->name)return mp_fail(w->im,"export name too long");
        memcpy(w->name+prefix,edge,len);
        if(!trie_node(w,child,prefix+len,depth+1))return 0;
    }
    return 1;
}
static int trie_bounds(Image *im,const unsigned char **trie,uint64_t *size) {
    uint64_t off=im->exports_trie.datasize?im->exports_trie.dataoff:im->dyld.export_off;
    uint64_t n=im->exports_trie.datasize?im->exports_trie.datasize:im->dyld.export_size;
    if(!n || off>im->file_size || n>im->file_size-off)return 0;
    *trie=im->file+off;*size=n;return 1;
}
static struct MPExports *build(Image *im) {
    struct symtab_command *t=&im->symtab;
    if(t->symoff>im->file_size || (uint64_t)t->nsyms*sizeof(struct nlist_64)>im->file_size-t->symoff ||
       t->stroff>im->file_size || t->strsize>im->file_size-t->stroff){mp_fail(im,"bad symbol table");return NULL;}
    static struct TrieWalk counter;const unsigned char *trie;uint64_t tsize;size_t trieCount=0;
    if(trie_bounds(im,&trie,&tsize)){counter=(struct TrieWalk){im,NULL,trie,tsize};if(trie_node(&counter,0,0,0))trieCount=counter.count;}
    size_t capacity=16;while(capacity<((size_t)t->nsyms+trieCount)*2)capacity<<=1;
    struct MPExports *e=calloc(1,sizeof *e);
    if(!e || !(e->slots=calloc(capacity,sizeof *e->slots))){free(e);mp_fail(im,"export table allocation failed");return NULL;}
    e->mask=capacity-1;
    for(uint32_t i=0;i<t->nsyms;i++) {
        struct nlist_64 n;memcpy(&n,im->file+t->symoff+(size_t)i*sizeof n,sizeof n);
        if((n.n_type&N_STAB) || (n.n_type&N_PEXT) || !(n.n_type&N_EXT) || (n.n_type&N_TYPE)!=N_SECT)continue;
        if(n.n_un.n_strx>=t->strsize){mp_fail(im,"bad symbol string");goto bad;}
        const char *s=(const char *)im->file+t->stroff+n.n_un.n_strx;
        if(!memchr(s,0,t->strsize-n.n_un.n_strx)){mp_fail(im,"unterminated symbol");goto bad;}
        if(n.n_value<im->low || n.n_value-im->low>=im->span){mp_fail(im,"symbol outside image");goto bad;}
        size_t slot=hash(s)&e->mask;
        while(e->slots[slot].name && strcmp(e->slots[slot].name,s))slot=(slot+1)&e->mask;
        if(!e->slots[slot].name)e->slots[slot]=(struct MPExport){s,n.n_value,n.n_desc};
    }
    // Export trie (what dyld uses): stripped images such as Cyberpunk's Bink
    // keep only a few symtab entries. Trie entries the symtab lacks are added.
    if(trieCount){static struct TrieWalk walk;walk=(struct TrieWalk){im,e,trie,tsize};if(!trie_node(&walk,0,0,0))goto bad;}
    return e;
bad:
    free(e->slots);free(e);return NULL;
}
void *mp_export(Image *im,const char *symbol,int *weak) {
    *weak=0;
    pthread_mutex_lock(&export_lock);
    if(!im->exports)im->exports=build(im);
    struct MPExports *e=im->exports;
    pthread_mutex_unlock(&export_lock);
    if(!e)return NULL;
    for(size_t slot=hash(symbol)&e->mask;e->slots[slot].name;slot=(slot+1)&e->mask) {
        if(strcmp(e->slots[slot].name,symbol))continue;
        void *address=im->base+(e->slots[slot].value-im->low);
        *weak=(e->slots[slot].desc&N_WEAK_DEF)!=0;
        // N_SYMBOL_RESOLVER: the symbol is a resolver returning the target.
        if(e->slots[slot].desc&N_SYMBOL_RESOLVER){void *(*resolver)(void);memcpy(&resolver,&address,sizeof address);return resolver();}
        return address;
    }
    return NULL;
}

// ---- Special bind ordinals -------------------------------------------------
static void *group_search(struct MPGroup *g,const char *symbol,int strong_only) {
    void *weakest=NULL;
    for(unsigned i=0;g && i<g->count;i++) {
        int weak;void *p=mp_export(g->images[i],symbol,&weak);
        if(p && !weak)return p;
        if(p && !weakest)weakest=p;
    }
    return strong_only?NULL:weakest;
}
void *mp_resolve_special(Image *im,int ordinal,const char *symbol) {
    int weak;void *p=NULL;
    switch(ordinal) {
    case BIND_SPECIAL_DYLIB_SELF:p=mp_export(im,symbol,&weak);break;
    case BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE:p=im->group?mp_export(im->group->images[0],symbol,&weak):(im->dylib?NULL:mp_export(im,symbol,&weak));break;
    case BIND_SPECIAL_DYLIB_FLAT_LOOKUP:case BIND_SPECIAL_DYLIB_WEAK_LOOKUP:
        p=im->group?group_search(im->group,symbol,0):mp_export(im,symbol,&weak);
        if(!p && symbol[0]=='_')p=dlsym(RTLD_DEFAULT,symbol+1);
        break;
    }
    if(!p)snprintf(im->error,sizeof im->error,"unresolved special-ordinal %d import: %s",ordinal,symbol);
    return p;
}

// ---- Guest dlopen family ---------------------------------------------------
// One group per process is supported (the opened game). Guest handles are
// the address of a member's dl_token; anything else is a host handle.
static struct MPGroup *active_group;
static _Thread_local const char *guest_dlerror;
static _Thread_local char guest_dlerror_text[300];
static Image *guest_handle(void *handle) {
    for(unsigned i=0;active_group && i<active_group->count;i++)if(handle==(void *)&active_group->images[i]->dl_token)return active_group->images[i];
    return NULL;
}
static void set_dlerror(const char *what,const char *name) {
    snprintf(guest_dlerror_text,sizeof guest_dlerror_text,"%s: %s",what,name);guest_dlerror=guest_dlerror_text;
}
// Desktop framework paths become their iOS (shallow bundle) spelling; host
// dyld then decides. Missing optional libraries simply return NULL.
static void *host_dlopen(const char *path,int mode) {
#if TARGET_OS_IPHONE
    const char *versions=strstr(path,".framework/Versions/");
    if(versions){char t[512];snprintf(t,sizeof t,"%.*s/%s",(int)(versions-path+10),path,strrchr(path,'/')+1);return dlopen(t,mode);}
#endif
    return dlopen(path,mode);
}
static void *mp_dlopen(const char *path,int mode) {
    guest_dlerror=NULL;
    if(!path)return active_group?(void *)&active_group->images[0]->dl_token:dlopen(NULL,mode);
    Image *im=mp_group_find(active_group,path);
    if(!im && active_group && path[0]=='/') {
        // An absolute path inside our own bundle still names a guest member.
        const char *slash=strrchr(path,'/');
        char rel[400];snprintf(rel,sizeof rel,"@executable_path/../libs/%s",slash?slash+1:path);
        if(strstr(path,".app/Contents/"))im=mp_group_find(active_group,rel);
    }
    if(im)return &im->dl_token;
    void *h=host_dlopen(path,mode);
    return h;
}
static void *mp_dlsym(void *handle,const char *name) {
    guest_dlerror=NULL;
    char symbol[512];snprintf(symbol,sizeof symbol,"_%s",name);
    Image *im=guest_handle(handle);
    if(im) {
        int weak;void *p=mp_export(im,symbol,&weak);
        for(unsigned i=0;!p && i<im->library_count;i++)if(im->dependencies[i])p=mp_export(im->dependencies[i],symbol,&weak);
        if(!p)set_dlerror("symbol not found in guest image",name);
        return p;
    }
    // RTLD_DEFAULT (-2), RTLD_NEXT (-1), RTLD_SELF (-3), RTLD_MAIN_ONLY (-5):
    // guest members first (they are the process's "own" images), then host.
    if((intptr_t)handle<0 && (intptr_t)handle>=-5) {
        void *p=group_search(active_group,symbol,0);
        if(p)return p;
        if(handle==RTLD_MAIN_ONLY){set_dlerror("symbol not found in main executable",name);return NULL;}
        return dlsym(RTLD_DEFAULT,name);
    }
    return dlsym(handle,name);
}
static int mp_dlclose(void *handle) {return guest_handle(handle)?0:dlclose(handle);}
static char *mp_dlerror(void) {
    if(guest_dlerror){const char *e=guest_dlerror;guest_dlerror=NULL;return (char *)e;}
    return dlerror();
}
static int mp_dladdr(const void *address,Dl_info *info) {
    for(unsigned i=0;active_group && i<active_group->count;i++) {
        Image *im=active_group->images[i];
        if((const unsigned char *)address<im->base || (const unsigned char *)address>=im->base+im->span)continue;
        memset(info,0,sizeof *info);
        info->dli_fname=im->install_name?im->install_name:"@executable_path/main";
        info->dli_fbase=im->base;
        // Nearest preceding export, as dyld reports for exported symbols.
        uint64_t offset=(uint64_t)((const unsigned char *)address-im->base),best=0;
        pthread_mutex_lock(&export_lock);struct MPExports *e=im->exports;pthread_mutex_unlock(&export_lock);
        for(size_t s=0;e && s<=e->mask;s++) {
            if(!e->slots[s].name)continue;
            uint64_t o=e->slots[s].value-im->low;
            if(o<=offset && o>=best){best=o;info->dli_sname=e->slots[s].name+1;info->dli_saddr=im->base+o;}
        }
        return 1;
    }
    return dladdr(address,info);
}
void *mp_group_dl_import(const char *symbol) {
    if(!strcmp(symbol,"_dlopen"))return (void *)&mp_dlopen;
    if(!strcmp(symbol,"_dlsym"))return (void *)&mp_dlsym;
    if(!strcmp(symbol,"_dlclose"))return (void *)&mp_dlclose;
    if(!strcmp(symbol,"_dlerror"))return (void *)&mp_dlerror;
    if(!strcmp(symbol,"_dladdr"))return (void *)&mp_dladdr;
    return NULL;
}
void mp_group_activate(struct MPGroup *g) {active_group=g;}

// ---- Unwinding --------------------------------------------------------------
// Directly mapped guests are unknown to dyld; libunwind's dynamic-sections
// hook (also used by LLVM's JIT) lets C++ exceptions and Rust panics unwind
// through them. Resident (iOS container) guests are inside a dyld image, so
// libunwind asks dyld first; their containers carry rebased unwind sections.
typedef struct {uintptr_t dso_base,dwarf_section;size_t dwarf_section_length;uintptr_t compact_unwind_section;size_t compact_unwind_section_length;} UnwindSections;
static Image *registered[64];static unsigned registered_count;
static pthread_mutex_t unwind_lock=PTHREAD_MUTEX_INITIALIZER;
static int find_sections(uintptr_t address,UnwindSections *info) {
    pthread_mutex_lock(&unwind_lock);
    for(unsigned i=0;i<registered_count;i++) {
        Image *im=registered[i];
        if(address<(uintptr_t)im->base || address-(uintptr_t)im->base>=im->span)continue;
        memset(info,0,sizeof *info);info->dso_base=(uintptr_t)im->base;
        for(unsigned j=0;j<im->section_count;j++) {
            struct section_64 *s=&im->sections[j];
            if(strncmp(s->segname,"__TEXT",16))continue;
            if(!strncmp(s->sectname,"__unwind_info",16)){info->compact_unwind_section=(uintptr_t)im->base+(s->addr-im->low);info->compact_unwind_section_length=(size_t)s->size;}
            if(!strncmp(s->sectname,"__eh_frame",16)){info->dwarf_section=(uintptr_t)im->base+(s->addr-im->low);info->dwarf_section_length=(size_t)s->size;}
        }
        pthread_mutex_unlock(&unwind_lock);return 1;
    }
    pthread_mutex_unlock(&unwind_lock);return 0;
}
// Called by image_link for the image being linked (mp_active not used here).
void mp_register_unwind_image(Image *im) {
    static int hooked;
    pthread_mutex_lock(&unwind_lock);
    if(!hooked) {
        int (*add)(int (*)(uintptr_t,UnwindSections *))=(int (*)(int (*)(uintptr_t,UnwindSections *)))dlsym(RTLD_DEFAULT,"__unw_add_find_dynamic_unwind_sections");
        hooked=add && !add(find_sections)?1:-1;
    }
    if(hooked==1 && !im->resident && registered_count<64)registered[registered_count++]=im;
    pthread_mutex_unlock(&unwind_lock);
}
void mp_unregister_unwind_image(Image *im) {
    pthread_mutex_lock(&unwind_lock);
    for(unsigned i=0;i<registered_count;i++)if(registered[i]==im){registered[i]=registered[--registered_count];break;}
    pthread_mutex_unlock(&unwind_lock);
}
