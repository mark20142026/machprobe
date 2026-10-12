#include "internal.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>
#include <crt_externs.h>
_Thread_local Image *mp_active;
static void *(*appkit_resolver)(const char *);
int mp_set_appkit_resolver(void *(*resolver)(const char *)) {
    if(mp_live_images())return -1;
    appkit_resolver=resolver;return 0;
}
static int capture_printf(const char *format,...) {
    char text[4096];va_list ap;va_start(ap,format);int n=vsnprintf(text,sizeof text,format,ap);va_end(ap);
    if(n<0 || n>=(int)sizeof text)return -1;
    if(mp_active && mp_active->services.output)mp_active->services.output(mp_active->services.context,text,(size_t)n);
    return n;
}
static int capture_puts(const char *text) {return capture_printf("%s\n",text);}
static void unused_binder(void) {abort();}
static int *guest_argc(void) {return mp_active && mp_active->services.argv?&mp_active->services.argc:_NSGetArgc();}
static char ***guest_argv(void) {return mp_active && mp_active->services.argv?&mp_active->services.argv:_NSGetArgv();}
static const char *libraries[]={
    "/usr/lib/libSystem.B.dylib", "/usr/lib/libobjc.A.dylib",
    "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation",
    "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
    "/System/Library/Frameworks/Metal.framework/Versions/A/Metal",
    "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
};
int mp_library_allowed(const char *s) {for(unsigned i=0;i<sizeof libraries/sizeof *libraries;i++)if(!strcmp(s,libraries[i]))return 1;return 0;}
void *mp_resolve(Image *im,const char *library,const char *symbol) {
    if(im->group) {
        Image *member=mp_group_find(im->group,library);
        if(member) {
            int weak;void *p=mp_export(member,symbol,&weak);
            if(!p)snprintf(im->error,sizeof im->error,"guest symbol %s missing from %s",symbol,library);
            return p;
        }
        // Guest code's dlopen family must see sibling guest images.
        if(!strcmp(library,"/usr/lib/libSystem.B.dylib")){void *dl=mp_group_dl_import(symbol);if(dl)return dl;}
    }
    if(im->services.argv && !strcmp(library,"/usr/lib/libSystem.B.dylib")) {
        if(!strcmp(symbol,"__NSGetArgc"))return (void *)&guest_argc;
        if(!strcmp(symbol,"__NSGetArgv"))return (void *)&guest_argv;
    }
    if(im->services.extensions && im->services.extensions->resolve) {
        void *p=im->services.extensions->resolve(library,symbol);
        if(p)return p;
    }
    if(strstr(library,"/AppKit.framework/")) {
        void *target=appkit_resolver?appkit_resolver(symbol):NULL;
        if(!target)snprintf(im->error,sizeof im->error,"unsupported AppKit import: %s",symbol);
        return target;
    }
    // An explicit import surface; dlsym here resolves HOST implementations only.
    static const char *allowed[]={
      "puts","printf","__error","__snprintf_chk","snprintf","__stack_chk_fail","__stack_chk_guard","__stderrp",
      "close","fclose","fdopen","fprintf","fputs","fread","fseek","fwrite","memcmp","mkstemp","perror","unlink",
      "malloc","calloc","free","strlen","memcpy","memset","__memcpy_chk","__memset_chk",
      "CFStringCreateWithCString","CFStringGetLength","CFRelease","CFRetain","__CFConstantStringClassReference",
      "MTLCreateSystemDefaultDevice","objc_getClass","sel_registerName","objc_msgSend","objc_autoreleasePoolPush","objc_autoreleasePoolPop",
      "objc_allocateClassPair","class_addMethod","objc_registerClassPair","objc_disposeClassPair","objc_alloc","objc_opt_class",
      "objc_release","objc_retain","objc_retainAutorelease","objc_retainAutoreleasedReturnValue","objc_autoreleaseReturnValue",
      "objc_storeStrong","objc_storeWeak","objc_alloc_init","objc_opt_isKindOfClass","objc_opt_respondsToSelector","objc_retainAutoreleaseReturnValue","objc_initWeak","objc_destroyWeak","objc_loadWeakRetained",
      "OBJC_CLASS_$_NSString","OBJC_CLASS_$_NSArray","OBJC_CLASS_$_NSConstantArray","OBJC_CLASS_$_NSMutableArray","OBJC_CLASS_$_NSObject",NULL};
    if(!strcmp(symbol,"dyld_stub_binder"))return (void *)&unused_binder;
    if(symbol[0]!='_'){mp_fail(im,"unsupported imported symbol spelling");return NULL;}
    const char *name=symbol+1;
    int found=0;for(unsigned i=0;allowed[i];i++)if(!strcmp(name,allowed[i])){found=1;break;}
    if(!found){snprintf(im->error,sizeof im->error,"unsupported import: %s",symbol);return NULL;}
    if(!strcmp(name,"puts"))return (void *)&capture_puts;
    if(!strcmp(name,"printf"))return (void *)&capture_printf;
    // Preload frameworks through the host linker in both CLI and UIKit hosts.
    // Check the declared library exists, then resolve within it (no guest dlopen).
    const char *hostpath=library;
    char translated[180];
    if(strstr(library,"/Frameworks/")) {
        const char *start=strstr(library,"/Frameworks/")+12;
        const char *dot=strstr(start,".framework");
        if(!dot)return NULL;
        snprintf(translated,sizeof translated,"/System/Library/Frameworks/%.*s.framework/%.*s",(int)(dot-start),start,(int)(dot-start),start);
        hostpath=translated;
    }
    void *handle=dlopen(hostpath,RTLD_LAZY|RTLD_LOCAL);
    if(!handle){snprintf(im->error,sizeof im->error,"host library unavailable: %s",hostpath);return NULL;}
    void *target=dlsym(handle,name);
    dlclose(handle);
    if(!target)snprintf(im->error,sizeof im->error,"host symbol unavailable: %s",name);
    return target;
}
static void *mapped(Image *im,uint64_t addr,uint64_t length) {
    if(addr<im->low || addr-im->low>im->span || length>im->span-(addr-im->low))return NULL;
    return im->base+(addr-im->low);
}
void *mp_resolve_weak(Image *im,const char *symbol) {
    // Group: like dyld, the first strong definition in member order wins (the
    // main executable is member 0), else the first weak one. Single image:
    // its own definitions win. Then declared host dylibs.
    void *target=im->group?mp_resolve_special(im,BIND_SPECIAL_DYLIB_WEAK_LOOKUP,symbol):mp_image_symbol(im,symbol);
    if(target){im->error[0]=0;return target;}
    for(unsigned i=0;i<im->library_count;i++) {
        target=mp_resolve(im,im->libraries[i],symbol);
        if(target){im->error[0]=0;return target;}
    }
    snprintf(im->error,sizeof im->error,"unresolved weak definition: %s",symbol);
    return NULL;
}
int mp_prepare_objc(Image *im) {
    for(unsigned i=0;i<im->section_count;i++) {
        struct section_64 *s=&im->sections[i];
        if(strncmp(s->sectname,"__objc_selrefs",16))continue;
        if(s->size%sizeof(void *))return mp_fail(im,"bad selector section size");
        const char **refs=mapped(im,s->addr,s->size);
        if(!refs)return mp_fail(im,"bad selector section address");
        for(size_t j=0;j<s->size/sizeof(void *);j++) {
            uintptr_t addr=(uintptr_t)refs[j],lo=(uintptr_t)im->base;
            int valid=0;
            for(unsigned k=0;k<im->count;k++) {
                struct segment_command_64 *seg=&im->segments[k];
                if(!strncmp(seg->segname,"__PAGEZERO",16))continue;
                uint64_t begin=lo+(seg->vmaddr-im->low);
                if(addr>=begin && addr-begin<seg->filesize && (seg->initprot&1) && memchr(refs[j],0,seg->filesize-(addr-begin)))valid=1;
            }
            if(!valid)return mp_fail(im,"bad selector name");
            refs[j]=(const char *)sel_registerName(refs[j]);im->stats.selectors++;
        }
    }
    return 1;
}
static int executable_offset(Image *im,uint64_t offset) {
    for(unsigned k=0;k<im->count;k++) {
        struct segment_command_64 *seg=&im->segments[k];
        if((seg->initprot&4) && offset>=seg->vmaddr-im->low && offset-(seg->vmaddr-im->low)<seg->filesize)return 1;
    }
    return 0;
}
// Initializer currently running, for crash reports.
const char *volatile mp_init_image;volatile unsigned mp_init_index;volatile uint32_t mp_init_offset;
int mp_initialize(Image *im) {
    // Ordinary C initializers: pointer lists (S_MOD_INIT_FUNC_POINTERS) and the
    // modern 32-bit image-relative offset tables (S_INIT_FUNC_OFFSETS,
    // __TEXT,__init_offsets), run in section order as dyld does.
    for(unsigned i=0;i<im->section_count;i++) {
        struct section_64 *s=&im->sections[i];
        if((s->flags&SECTION_TYPE)==S_INIT_FUNC_OFFSETS) {
            if(s->size%4)return mp_fail(im,"invalid initializer offsets size");
            const uint32_t *offsets=mapped(im,s->addr,s->size);if(!offsets)return mp_fail(im,"invalid initializer offsets address");
            for(size_t j=0;j<s->size/4;j++) {
                if(!executable_offset(im,offsets[j]))return mp_fail(im,"initializer offset is not guest executable code");
                void (*fn)(void);uintptr_t address=(uintptr_t)im->base+offsets[j];memcpy(&fn,&address,sizeof fn);
                mp_init_image=im->install_name?im->install_name:"main";mp_init_index=(unsigned)j;mp_init_offset=offsets[j];
                Image *old=mp_active;mp_active=im;fn();mp_active=old;im->stats.initializers++;
            }
            continue;
        }
        if((s->flags&SECTION_TYPE)!=S_MOD_INIT_FUNC_POINTERS)continue;
        if(s->size%8)return mp_fail(im,"invalid initializer size");
        uintptr_t *functions=mapped(im,s->addr,s->size);if(!functions)return mp_fail(im,"invalid initializer address");
        for(size_t j=0;j<s->size/8;j++) {
            uintptr_t offset=functions[j]-(uintptr_t)im->base;int executable=0;
            for(unsigned k=0;k<im->count;k++) {
                struct segment_command_64 *seg=&im->segments[k];
                if((seg->initprot&4) && offset>=seg->vmaddr-im->low && offset-(seg->vmaddr-im->low)<seg->filesize)executable=1;
            }
            if(!executable)return mp_fail(im,"initializer is not guest executable code");
            void (*fn)(void);memcpy(&fn,&functions[j],sizeof fn);
            mp_init_image=im->install_name?im->install_name:"main";mp_init_index=(unsigned)j;mp_init_offset=(uint32_t)offset;
            Image *old=mp_active;mp_active=im;fn();mp_active=old;im->stats.initializers++;
        }
    }
    mp_init_image=NULL;
    return 1;
}
