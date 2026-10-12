// Cyberpunk 2077 (Steam macOS build 20383525) group policy: the Phase 5.5
// large-game policy plus guest dylibs, categories and the exact system
// dependencies of its five arm64 images. Admission never implies the API
// exists on iOS; unresolved imports still fail or abort visibly.
#include "runtime.h"
#include "Extended.h"
#include <string.h>
#include <TargetConditionals.h>
extern const MPExtensions *mp_large_game_policy(void);
#if TARGET_OS_IPHONE
extern void *mp_stk_desktop_symbol(const char *library,const char *symbol);
extern void *mp_cp_desktop_symbol(const char *library,const char *symbol);
extern void *mp_cp_metal_devices(void);
extern void *mp_cp_metal_default_device(void);
#endif
static int allowed(const char *name) {
    if(mp_large_game_policy()->library_allowed(name))return 1;
    static const char *extra[]={
        "/System/Library/Frameworks/AudioUnit.framework/Versions/A/AudioUnit",
        "/System/Library/Frameworks/CoreHaptics.framework/Versions/A/CoreHaptics",
        "/System/Library/Frameworks/MetalFX.framework/Versions/A/MetalFX",
        "/System/Library/Frameworks/MetricKit.framework/Versions/A/MetricKit",
        "/usr/lib/libbz2.1.0.dylib",
        "/usr/lib/libcurl.4.dylib",
    };
    for(unsigned i=0;i<sizeof extra/sizeof *extra;i++)if(!strcmp(name,extra[i]))return 1;
    return 0;
}
// Virtual executable path: the game locates archive/, engine/ and r6/ by
// walking up from its own executable path. MP_GUEST_EXECUTABLE_PATH names
// where Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077 would sit in a normal
// install (on iOS: inside Documents, next to the copied data).
#include <stdlib.h>
#include <stdint.h>
static int guest_executable_path(char *buffer,uint32_t *size) {
    const char *path=getenv("MP_GUEST_EXECUTABLE_PATH");
    if(!path){extern int _NSGetExecutablePath(char *,uint32_t *);return _NSGetExecutablePath(buffer,size);}
    uint32_t need=(uint32_t)strlen(path)+1;
    if(*size<need){*size=need;return -1;}
    memcpy(buffer,path,need);return 0;
}
// Memory trace (MP_MEM_TRACE): large mappings and every failure, to size the
// engine's up-front reservations against the iOS address-space limit.
#include <stdio.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
static int mem_trace=-1;
static int tracing(void){if(mem_trace<0)mem_trace=getenv("MP_MEM_TRACE")!=NULL;return mem_trace;}
// Address-space rationing. iOS gives this app ~66 GB of virtual address space
// (64 GB window 0x7000000000-0x8000000000 plus ~1.5 GB low; the rest is
// reserved by the system). RED Engine's allocator reserves 16 GB (small),
// 64 GB (medium) and 32 GB (large) regions up front, fills each from its start,
// and routes a free by range: small, then medium, else large. Requests of
// 16 GB or more are therefore stacked top-down from the window's end in request
// order (small on top), and those above 16 GB get MP_VA_CAP_GB (default 8) of
// real space. Each region's unbacked tail then covers only regions checked
// before it, or addresses past the window that nothing can occupy. Later calls
// reaching into a tail are clipped or refused so they never touch other mappings.
struct Shrunk {uintptr_t base,real,claimed;};
static struct Shrunk shrunk[32];static unsigned shrunk_count;
static size_t va_cap(void) {
    static size_t cap;if(!cap){const char *v=getenv("MP_VA_CAP_GB");cap=(size_t)(v?atoi(v):8)<<30;if(!cap)cap=(size_t)8<<30;}
    return cap;
}
// Clip [a,a+n) to exclude unbacked tails; returns 0 if nothing backed remains.
static int clip(uintptr_t *a,size_t *n) {
    for(unsigned i=0;i<shrunk_count;i++) {
        uintptr_t lo=shrunk[i].base+shrunk[i].real,hi=shrunk[i].base+shrunk[i].claimed,end=*a+*n;
        if(end<=lo || *a>=hi)continue;
        if(*a>=lo){ // Starts in the tail.
            if(end<=hi)return 0;
            *n=end-hi;*a=hi;continue;
        }
        *n=lo-*a; // Starts before the tail: keep the backed part only.
    }
    return *n>0;
}
const char *mp_cp_va_tail(uintptr_t address) { // For crash reports.
    for(unsigned i=0;i<shrunk_count;i++)if(address>=shrunk[i].base+shrunk[i].real && address<shrunk[i].base+shrunk[i].claimed)return "unbacked tail of a rationed guest reservation";
    return NULL;
}
static void trace_callers(void) {
    extern const char *mp_locate(uintptr_t,uintptr_t *);uintptr_t *fp=__builtin_frame_address(1);
    for(int i=0;i<5 && fp;i++){uintptr_t off;const char *g=mp_locate(fp[1],&off);if(g)fprintf(stderr,"[mem]    %s+%#lx\n",g,(unsigned long)off);fp=(uintptr_t *)fp[0];}
}
static void *guest_mmap(void *a,size_t n,int prot,int flags,int fd,off_t off) {
    if(flags&MAP_FIXED) {
        uintptr_t start=(uintptr_t)a;size_t len=n;
        if(!clip(&start,&len) || start!=(uintptr_t)a || len!=n){fprintf(stderr,"[mem] refused MAP_FIXED %p %zu MB into a rationed tail\n",a,n>>20);errno=ENOMEM;return MAP_FAILED;}
    }
    void *r=MAP_FAILED;
#if TARGET_OS_IPHONE
    static uintptr_t top=0x8000000000ull;
    if(!a && (flags&MAP_ANON) && !(flags&MAP_FIXED) && n>=((size_t)16<<30) && shrunk_count<32) {
        size_t real=n>((size_t)16<<30)?va_cap():n;uintptr_t at=top-real;
        r=mmap((void *)at,real,prot,flags,fd,off);
        if(r!=MAP_FAILED && (uintptr_t)r!=at){munmap(r,real);r=MAP_FAILED;}
        if(r!=MAP_FAILED){top=at;if(real<n)shrunk[shrunk_count++]=(struct Shrunk){at,real,n};
            fprintf(stderr,"[mem] placed %zu GB reservation at %p with %zu GB real\n",n>>30,r,real>>30);}
        else fprintf(stderr,"[mem] could not place %zu GB reservation at %#lx\n",n>>30,(unsigned long)at);
    }
    if(r==MAP_FAILED)
#endif
    r=mmap(a,n,prot,flags,fd,off);
    if(r==MAP_FAILED || (tracing() && n>=(64u<<20))) {
        fprintf(stderr,"[mem] mmap %p %zu MB prot=%d flags=%#x fd=%d -> %p%s%s\n",a,n>>20,prot,flags,fd,r,r==MAP_FAILED?" errno ":"",r==MAP_FAILED?strerror(errno):"");
        if(tracing())trace_callers();
    }
    return r;
}
static int guest_munmap(void *a,size_t n) {
    for(unsigned i=0;i<shrunk_count;i++)if((uintptr_t)a==shrunk[i].base && n==shrunk[i].claimed) {
        int r=munmap(a,shrunk[i].real);shrunk[i]=shrunk[--shrunk_count];return r;
    }
    uintptr_t start=(uintptr_t)a;size_t len=n;
    if(!clip(&start,&len))return 0; // Nothing backed there: already unmapped.
    return munmap((void *)start,len);
}
static int guest_mprotect(void *a,size_t n,int prot) {
    uintptr_t start=(uintptr_t)a;size_t len=n;
    if(!clip(&start,&len)){fprintf(stderr,"[mem] mprotect %p %zu MB entirely in a rationed tail\n",a,n>>20);trace_callers();errno=ENOMEM;return -1;}
    return mprotect((void *)start,len,prot);
}
static int guest_madvise(void *a,size_t n,int advice) {
    uintptr_t start=(uintptr_t)a;size_t len=n;
    if(!clip(&start,&len))return 0;
    return madvise((void *)start,len,advice);
}
static void *guest_malloc(size_t n) {
    void *r=malloc(n);
    if(!r || (tracing() && n>=(64u<<20)))fprintf(stderr,"[mem] malloc %zu MB -> %p\n",n>>20,r);
    return r;
}
// RED sizes its streaming budgets from hw.memsize (12 GB on an iPhone 18 Pro),
// but an app may use only ~6.4 GB with the increased-memory entitlement, GPU
// included. Report MP_MEMSIZE_GB (default 3: the game budgets 75% of hw.memsize for the GPU) so the budgets fit.
static int guest_sysctlbyname(const char *name,void *old,size_t *oldlen,void *new,size_t newlen) {
    int r=sysctlbyname(name,old,oldlen,new,newlen);
#if TARGET_OS_IPHONE
    if(r==0 && name && !strcmp(name,"hw.memsize") && old && oldlen && *oldlen==8) {
        const char *v=getenv("MP_MEMSIZE_GB");uint64_t gb=v?(uint64_t)atoll(v):3;
        if(gb){uint64_t bytes=gb<<30;memcpy(old,&bytes,8);}
    }
#endif
    if(tracing())fprintf(stderr,"[mem] sysctlbyname %s -> %d value=%lld\n",name,r,old&&oldlen&&*oldlen==8?*(long long *)old:old&&oldlen&&*oldlen==4?(long long)*(int *)old:-1);
    return r;
}
// Paths. macOS volumes ignore case; the iOS data volume does not, and the
// game asks for e.g. archive/mac/content while the install has archive/Mac.
// A path that does not exist as given is matched component by component,
// ignoring case; components that match nothing are kept (for creation).
// Existing paths cost one access(); MP_FS_TRACE logs every lookup.
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <utime.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>
#include <strings.h>
static int fs_trace=-1;
static int fs_tracing(void){if(fs_trace<0)fs_trace=getenv("MP_FS_TRACE")!=NULL;return fs_trace;}
// Mac home paths baked into game files (e.g. gameservices.ini's LogPath
// "/Users/<build user>/Library/Logs/...") map to this app's home on iOS.
static const char *home_path(const char *path,char *out) {
#if TARGET_OS_IPHONE
    if(path && !strncmp(path,"/Users/",7)) {
        const char *rest=strchr(path+7,'/');const char *home=getenv("HOME");
        if(home && snprintf(out,PATH_MAX,"%s%s",home,rest?rest:"")<PATH_MAX)return out;
    }
#endif
    return path;
}
static const char *ci(const char *path,char *out) {
    char homed[PATH_MAX];path=home_path(path,homed);
    if(path==homed){strcpy(out,homed);path=out;char again[PATH_MAX];const char *r=ci(path,again);if(r==again){strcpy(out,again);}return out;}
    if(!path || !*path || access(path,F_OK)==0 || errno!=ENOENT)return path;
    size_t len=0;const char *p=path;out[0]=0;
    if(*p=='/'){out[len++]='/';out[len]=0;while(*p=='/')p++;}
    while(*p) {
        const char *end=strchr(p,'/');size_t n=end?(size_t)(end-p):strlen(p);
        if(len+n+2>=PATH_MAX)return path;
        size_t base=len;memcpy(out+len,p,n);out[len+n]=0;
        if(access(out,F_OK)!=0 && !(n==1&&p[0]=='.') && !(n==2&&p[0]=='.'&&p[1]=='.')) {
            char dir[PATH_MAX];if(base==0)strcpy(dir,".");else{memcpy(dir,out,base);dir[base]=0;}
            DIR *d=opendir(dir);struct dirent *e;
            if(d){while((e=readdir(d)))if(strlen(e->d_name)==n && !strncasecmp(e->d_name,p,n)){memcpy(out+base,e->d_name,n);break;}closedir(d);}
        }
        len=base+n;p+=n;
        if(*p=='/'){out[len++]='/';out[len]=0;while(*p=='/')p++;}
    }
    if(fs_tracing() && strcmp(out,path))fprintf(stderr,"[fs] case %s -> %s\n",path,out);
    return out;
}
#define CI(p) char ci_##p[PATH_MAX];const char *r_##p=ci(p,ci_##p)
#define TRACE(fmt,...) do{if(fs_tracing())fprintf(stderr,"[fs] " fmt "\n",__VA_ARGS__);}while(0)
static DIR *guest_opendir(const char *p){CI(p);DIR *r=opendir(r_p);TRACE("opendir %s -> %s",r_p,r?"ok":strerror(errno));return r;}
static int guest_stat(const char *p,struct stat *st){CI(p);int r=stat(r_p,st);TRACE("stat %s -> %d",r_p,r);return r;}
static int guest_lstat(const char *p,struct stat *st){CI(p);return lstat(r_p,st);}
static int guest_access(const char *p,int m){CI(p);int r=access(r_p,m);TRACE("access %s %d -> %d",r_p,m,r);return r;}
static int guest_open(const char *p,int flags,...){va_list ap;va_start(ap,flags);int mode=(flags&O_CREAT)?va_arg(ap,int):0;va_end(ap);
    CI(p);int r=open(r_p,flags,mode);TRACE("open %s %#x -> %d",r_p,flags,r);return r;}
static FILE *guest_fopen(const char *p,const char *m){CI(p);FILE *r=fopen(r_p,m);TRACE("fopen %s %s -> %s",r_p,m,r?"ok":strerror(errno));return r;}
static FILE *guest_freopen(const char *p,const char *m,FILE *f){CI(p);return freopen(r_p,m,f);}
static char *guest_realpath(const char *p,char *out){CI(p);char *r=realpath(r_p,out);TRACE("realpath %s -> %s",r_p,r?r:"NULL");return r;}
static char *guest_getcwd(char *b,size_t n){return getcwd(b,n);}
static int guest_mkdir(const char *p,mode_t m){CI(p);return mkdir(r_p,m);}
static int guest_rmdir(const char *p){CI(p);return rmdir(r_p);}
static int guest_unlink(const char *p){CI(p);return unlink(r_p);}
static int guest_rename(const char *a,const char *b){CI(a);CI(b);return rename(r_a,r_b);}
static int guest_chmod(const char *p,mode_t m){CI(p);return chmod(r_p,m);}
static int guest_utime(const char *p,const struct utimbuf *t){CI(p);return utime(r_p,t);}
static int guest_truncate(const char *p,off_t n){CI(p);return truncate(r_p,n);}
static int guest_statfs(const char *p,struct statfs *st){CI(p);return statfs(r_p,st);}
static const struct {const char *name;void *fn;} paths[]={
    {"_opendir",(void *)&guest_opendir},{"_stat",(void *)&guest_stat},{"_lstat",(void *)&guest_lstat},{"_access",(void *)&guest_access},
    {"_open",(void *)&guest_open},{"_fopen",(void *)&guest_fopen},{"_freopen",(void *)&guest_freopen},{"_realpath$DARWIN_EXTSN",(void *)&guest_realpath},
    {"_getcwd",(void *)&guest_getcwd},{"_mkdir",(void *)&guest_mkdir},{"_rmdir",(void *)&guest_rmdir},{"_unlink",(void *)&guest_unlink},
    {"_rename",(void *)&guest_rename},{"_chmod",(void *)&guest_chmod},{"_utime",(void *)&guest_utime},{"_truncate",(void *)&guest_truncate},
    {"_statfs",(void *)&guest_statfs},
};
static int guest_sysctl(int *mib,u_int count,void *old,size_t *oldlen,void *new,size_t newlen) {
    int r=sysctl(mib,count,old,oldlen,new,newlen);
#if TARGET_OS_IPHONE
    if(r==0 && count==2 && mib[0]==CTL_HW && mib[1]==HW_MEMSIZE && old && oldlen && *oldlen==8) {
        const char *v=getenv("MP_MEMSIZE_GB");uint64_t gb=v?(uint64_t)atoll(v):3;
        if(gb){uint64_t bytes=gb<<30;memcpy(old,&bytes,8);}
    }
#endif
    return r;
}
static void *resolve(const char *library,const char *symbol) {
    if(!strcmp(symbol,"__NSGetExecutablePath") && strstr(library,"libSystem"))return (void *)&guest_executable_path;
    if(strstr(library,"libSystem")) {
        if(!strcmp(symbol,"_mmap"))return (void *)&guest_mmap;
        for(unsigned i=0;i<sizeof paths/sizeof *paths;i++)if(!strcmp(symbol,paths[i].name))return paths[i].fn;
        if(!strcmp(symbol,"_munmap"))return (void *)&guest_munmap;
        if(!strcmp(symbol,"_mprotect"))return (void *)&guest_mprotect;
        if(!strcmp(symbol,"_madvise"))return (void *)&guest_madvise;
        if(!strcmp(symbol,"_malloc") && tracing())return (void *)&guest_malloc;   // Hot path: only when tracing.
        if(!strcmp(symbol,"_sysctlbyname"))return (void *)&guest_sysctlbyname;
        if(!strcmp(symbol,"_sysctl"))return (void *)&guest_sysctl;
    }
#if TARGET_OS_IPHONE
    // Lean Metal: Apple's real device objects, never the Phase 5 proxies.
    if(strstr(library,"/Metal.framework/")) {
        if(!strcmp(symbol,"_MTLCreateSystemDefaultDevice"))return (void *)&mp_cp_metal_default_device;
        if(!strcmp(symbol,"_MTLCopyAllDevices"))return (void *)&mp_cp_metal_devices;
    }
    void *cp=mp_cp_desktop_symbol(library,symbol);if(cp)return cp;
    void *desktop=mp_stk_desktop_symbol(library,symbol);if(desktop)return desktop;
#endif
    return mp_large_game_policy()->resolve(library,symbol);
}
const MPExtensions *mp_cp_policy(void) {
    static MPExtensions policy;
    policy=*mp_large_game_policy();
    policy.library_allowed=allowed;policy.resolve=resolve;
    policy.max_image_bytes=256u*1024u*1024u; // 151 MB executable.
    policy.allow_guest_dylibs=1;policy.allow_categories=1;policy.allow_weak_imports=1;
    policy.register_metadata=mp_register_metadata;
    return &policy;
}
