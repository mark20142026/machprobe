// macOS harness: load an app's executable plus Contents/Frameworks dylibs as
// one guest group with host frameworks. Usage:
//   cp-load DIR EXECUTABLE [--run args...]   (DIR holds EXECUTABLE + Frameworks/)
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "runtime.h"
#include <stdlib.h>
#include <dirent.h>
#include <dlfcn.h>
extern const MPExtensions *mp_cp_policy(void);
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc<3)return 2;
        int run=argc>=4 && !strcmp(argv[3],"--run");
        MPGuestSource sources[32];unsigned count=0;char *path;
        asprintf(&path,"%s/%s",argv[1],argv[2]);sources[count++]=(MPGuestSource){.path=path};
        char libs[1024];snprintf(libs,sizeof libs,"%s/Frameworks",argv[1]);
        DIR *d=opendir(libs);struct dirent *e;
        while(d && (e=readdir(d)) && count<32)if(strstr(e->d_name,".dylib")){asprintf(&path,"%s/%s",libs,e->d_name);sources[count++]=(MPGuestSource){.path=path};}
        if(d)closedir(d);
        char *guestArgv[64]={argv[2]};int guestArgc=1;
        for(int i=4;run && i<argc && guestArgc<63;i++)guestArgv[guestArgc++]=argv[i];
        MPServices services={.extensions=mp_cp_policy(),.argc=guestArgc,.argv=guestArgv};
        char error[256];double t=[NSDate timeIntervalSinceReferenceDate];
        MPGroup *group=mp_group_open(sources,count,services,error);
        if(!group){fprintf(stderr,"GROUP: %s\n",error);return 1;}
        unsigned rebases=0,binds=0,selectors=0,inits=0;
        for(unsigned i=0;i<mp_group_count(group);i++){MPStats s=mp_image_stats(mp_group_image(group,i));rebases+=s.rebases;binds+=s.binds;selectors+=s.selectors;inits+=s.initializers;}
        fprintf(stderr,"GROUP LOADED in %.2fs: images=%u rebases=%u binds=%u selectors=%u initializers=%u\n",[NSDate timeIntervalSinceReferenceDate]-t,mp_group_count(group),rebases,binds,selectors,inits);
        if(getenv("MP_DUMP_CLASSES")) { // Load-only introspection: methods of the named guest classes.
            for(NSString *name in [@(getenv("MP_DUMP_CLASSES")) componentsSeparatedByString:@","]) {
                Class c=NSClassFromString(name);if(!c){fprintf(stderr,"%s: not found\n",name.UTF8String);continue;}
                fprintf(stderr,"%s < %s:",name.UTF8String,class_getName(class_getSuperclass(c)));
                unsigned n=0;Method *ms=class_copyMethodList(c,&n);for(unsigned i=0;i<n;i++){Dl_info info={0};IMP imp=method_getImplementation(ms[i]);extern const char *mp_locate(uintptr_t,uintptr_t *);uintptr_t off=0;const char *g=mp_locate((uintptr_t)imp,&off);fprintf(stderr," %s@%#lx",sel_getName(method_getName(ms[i])),g?(unsigned long)(off+0x100000000):0UL);}free(ms);
                fprintf(stderr,"\n  ivars:");unsigned ni=0;Ivar *iv=class_copyIvarList(c,&ni);for(unsigned i=0;i<ni;i++)fprintf(stderr," %s@%td",ivar_getName(iv[i]),ivar_getOffset(iv[i]));free(iv);
                fprintf(stderr,"\n");
            }
        }
        if(getenv("MP_FIND_SELECTOR")) { // Load-only: guest classes implementing a selector.
            SEL sel=sel_registerName(getenv("MP_FIND_SELECTOR"));unsigned n=0;Class *all=objc_copyClassList(&n);
            extern const char *mp_locate(uintptr_t,uintptr_t *);
            for(unsigned i=0;i<n;i++){Method m=class_getInstanceMethod(all[i],sel);uintptr_t off;
                if(m && class_getMethodImplementation(class_getSuperclass(all[i]),sel)!=method_getImplementation(m) && mp_locate((uintptr_t)method_getImplementation(m),&off))
                    fprintf(stderr,"%s implements %s @%#lx\n",class_getName(all[i]),getenv("MP_FIND_SELECTOR"),(unsigned long)(off+0x100000000));}
            free(all);
        }
        if(getenv("MP_FIND_ADDR")) { // Load-only: guest method whose code starts nearest below an address.
            uintptr_t want=strtoull(getenv("MP_FIND_ADDR"),NULL,16);uintptr_t best=0;char name[512]="?";unsigned n=0;Class *all=objc_copyClassList(&n);
            extern const char *mp_locate(uintptr_t,uintptr_t *);
            for(unsigned i=0;i<n;i++)for(int meta=0;meta<2;meta++){Class c=meta?object_getClass((id)all[i]):all[i];unsigned k=0;Method *ms=class_copyMethodList(c,&k);
                for(unsigned j=0;j<k;j++){uintptr_t off;if(!mp_locate((uintptr_t)method_getImplementation(ms[j]),&off))continue;uintptr_t a=off+0x100000000;
                    if(a<=want && a>best){best=a;snprintf(name,sizeof name,"%c[%s %s]",meta?'+':'-',class_getName(all[i]),sel_getName(method_getName(ms[j])));}}free(ms);}
            free(all);fprintf(stderr,"%#lx is in %s @%#lx\n",(unsigned long)want,name,(unsigned long)best);
        }
        if(!run)return 0;
        int result;return mp_image_main(mp_group_image(group,0),guestArgc,guestArgv,&result)?1:result;
    }
}
