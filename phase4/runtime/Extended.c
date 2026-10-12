#include "Extended.h"
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <objc/runtime.h>
#include <TargetConditionals.h>
static void *(*extra_shim)(const char *,const char *);
void mp_extended_set_shim(void *(*shim)(const char *,const char *)){extra_shim=shim;}
static int library_allowed(const char *name) {
    static const char *frameworks[]={"/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
        "/System/Library/Frameworks/Combine.framework/Versions/A/Combine",
        "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"};
    for(unsigned i=0;i<sizeof frameworks/sizeof *frameworks;i++)if(!strcmp(name,frameworks[i]))return 1;
    if(!strcmp(name,"/usr/lib/libc++.1.dylib"))return 1;
    return !strncmp(name,"/usr/lib/swift/libswift",22) && !strstr(name,"/../") && strlen(name)<160;
}
static void *host_symbol(const char *library,const char *symbol) {
    if(extra_shim){void *result=extra_shim(library,symbol);if(result)return result;}
    if(!strcmp(symbol,"dyld_stub_binder"))return NULL; // Existing eager binder guard.
    char path[256];snprintf(path,sizeof path,"%s",library);
#if TARGET_OS_IPHONE
    const char *versions=strstr(library,".framework/Versions/");
    if(versions)snprintf(path,sizeof path,"%.*s/%s",(int)(versions-library+10),library,strrchr(library,'/')+1);
#endif
    // Hold host libraries for the lifetime of published guest metadata.
    static struct {char path[256];void *handle;} cache[64];static unsigned count;
    void *handle=NULL;unsigned i=0;
    for(;i<count;i++)if(!strcmp(cache[i].path,path)){handle=cache[i].handle;break;}
    if(i==count && count<64){handle=dlopen(path,RTLD_NOW|RTLD_LOCAL);snprintf(cache[count].path,256,"%s",path);cache[count++].handle=handle;}
    return handle?dlsym(handle,symbol[0]=='_'?symbol+1:symbol):NULL;
}
const MPExtensions *mp_extended_policy(void) {
    static const MPExtensions policy={.allow_class_metadata=1,.allow_weak_imports=1,.library_allowed=library_allowed,.resolve=host_symbol};return &policy;
}
// Compiled category_t / method_list_t layouts (objc4 objc-runtime-new.h).
// Methods are attached with class_replaceMethod because category methods
// override the class's own. Relative (small) lists name their selector via a
// selref already registered by the loader; pointer lists name a C string.
struct mp_category {const char *name;Class cls;const uint32_t *instance_methods,*class_methods;const uintptr_t *protocols;};
static int apply_methods(Class cls,const uint32_t *list,char error[256]) {
    if(!list || !cls)return 1;
    uint32_t flags=list[0],count=list[1],entsize=flags&~0xffff0003u;int small=(flags&0x80000000u)!=0;
    if((small && entsize!=12) || (!small && entsize!=24)){snprintf(error,256,"unsupported category method list entsize %u",entsize);return 0;}
    const char *entries=(const char *)(list+2);
    for(uint32_t i=0;i<count;i++) {
        const char *e=entries+(size_t)i*entsize;SEL sel;const char *types;IMP imp;
        if(small) {
            int32_t o[3];memcpy(o,e,sizeof o);
            if(!o[2])continue;
            memcpy(&sel,e+o[0],sizeof sel);types=e+4+o[1];imp=(IMP)(uintptr_t)(e+8+o[2]);
        } else {
            const char *name;memcpy(&name,e,sizeof name);memcpy(&types,e+8,sizeof types);memcpy(&imp,e+16,sizeof imp);
            if(!imp)continue;sel=sel_registerName(name);
        }
        class_replaceMethod(cls,sel,imp,types);
    }
    return 1;
}
static int apply_categories(MPImage *image,char error[256]) {
    size_t size=0;struct mp_category **list=mp_image_section(image,"__objc_catlist",&size);
    if(size%sizeof *list){snprintf(error,256,"bad category list");return 0;}
    for(size_t i=0;i<size/sizeof *list;i++) {
        struct mp_category *c=list[i];
        if(!c->cls)continue; // Weak-imported class absent on this host.
        if(!apply_methods(c->cls,c->instance_methods,error) || !apply_methods(object_getClass((id)c->cls),c->class_methods,error))return 0;
        // Protocol conformance only where the host already knows the protocol.
        for(uintptr_t j=0;c->protocols && j<c->protocols[0];j++) {
            const char *proto_name;memcpy(&proto_name,(const char *)c->protocols[j+1]+sizeof(void *),sizeof proto_name);
            Protocol *p=objc_getProtocol(proto_name);if(p)class_addProtocol(c->cls,p);
        }
    }
    return 1;
}
int mp_register_metadata(MPImage *image,char error[256]) {
    typedef Class (*ReadClass)(Class,const void *);
    typedef void (*Register)(const void *,const void *);
    void *swift=dlopen("/usr/lib/swift/libswiftCore.dylib",RTLD_NOW|RTLD_LOCAL);
    void *objc=dlopen("/usr/lib/libobjc.A.dylib",RTLD_NOW|RTLD_LOCAL);
    ReadClass read=objc?(ReadClass)dlsym(objc,"objc_readClassPair"):NULL;
    const char *names[]={"__swift5_protos","__swift5_proto","__swift5_types"};
    const char *functions[]={"swift_registerProtocols","swift_registerProtocolConformances","swift_registerTypeMetadataRecords"};
    void *sections[3];size_t sizes[3];Register registrations[3];
    for(unsigned i=0;i<3;i++) {
        sections[i]=mp_image_section(image,names[i],&sizes[i]);
        registrations[i]=swift?(Register)dlsym(swift,functions[i]):NULL;
        if(sizes[i]%4 || (sizes[i] && !registrations[i])){snprintf(error,256,"metadata registration unavailable: %s",names[i]);return 0;}
    }
    size_t count=0,infoSize=0;Class *classes=mp_image_section(image,"__objc_classlist",&count);
    void *info=mp_image_section(image,"__objc_imageinfo",&infoSize);
    if(count%sizeof(Class) || (count && (!read || !info || infoSize!=8))){snprintf(error,256,"class registration prerequisites unavailable");return 0;}
    // objc_readClassPair and Swift registration are runtime SPIs. They do not
    // grant executable-memory or signing privileges, but are version-sensitive.
    // Neither runtime provides a matching general unregister operation here.
    mp_image_pin(image);
    for(size_t i=0;i<count/sizeof(Class);i++) {
        if(!read(classes[i],info)){snprintf(error,256,"host rejected compiled class %zu",i);return 0;}
    }
    for(unsigned i=0;i<3;i++)if(sizes[i])registrations[i](sections[i],(char *)sections[i]+sizes[i]);
    if(!apply_categories(image,error))return 0;
    if(error)error[0]=0;return 1;
}
