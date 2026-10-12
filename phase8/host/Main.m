// Lean iOS host for the unchanged Cyberpunk 2077 (Steam macOS build) images.
// Same container model as Phase 6; performance first: Apple's real Metal
// objects (CPMetal.m), diagnostics only with Documents/debug present.
// Game data lives in Documents/Cyberpunk 2077/{archive,engine,r6}; the guest
// sees its executable at .../Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#include "Extended.h"
#include "GameBridge.h"
#include "ImageShim.h"
#import "Lifecycle.h"
#import "Observe.h"
#import "Input.h"
#import "MetalCompat.h"
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>
#include <CommonCrypto/CommonDigest.h>
#include <unistd.h>
#include <os/proc.h>
#include <signal.h>
#include <errno.h>
#include <sys/mman.h>
#include <mach/mach.h>
#include <sys/resource.h>
#include <sys/ucontext.h>
extern const MPExtensions *mp_cp_policy(void);
extern void mp_cp_metal_install(void);
extern NSDictionary *mp_cp_metal_features(void);
extern NSDictionary *mp_stk_frame_window(void);
static NSString *reportPath;static NSMutableDictionary *report;static NSLock *reportLock;
static void stage(NSString *value) {
    [reportLock lock];
    report[@"stage"]=value;report[@"frame_window"]=mp_stk_frame_window();
    if(NSThread.isMainThread)report[@"input"]=mp_game_input_stats(); // Input state is main-thread only.
    report[@"memory_available_bytes"]=@(os_proc_available_memory());
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:reportPath atomically:YES];
    [reportLock unlock];
}
void mp_audio_probe_finished(NSDictionary *result){}
static void exception(NSException *e){report[@"exception"]=e.description;report[@"stack"]=e.callStackSymbols;stage(@"exception");}
// Coalesced: at most two report writes per second from traces during play.
void mp_game_trace(NSString *event){
    static double lastWrite;static BOOL pending;
    [reportLock lock];
    NSMutableArray *events=report[@"events"];if(!events){events=[NSMutableArray new];report[@"events"]=events;}
    if(events.count>=300)[events removeObjectAtIndex:0];
    [events addObject:event];report[@"stage"]=event;
    double now=CACurrentMediaTime();BOOL write=now-lastWrite>0.5;if(write)lastWrite=now;
    else if(!pending){pending=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{pending=NO;[reportLock lock];NSString *last=report[@"stage"];[reportLock unlock];stage(last);});}
    [reportLock unlock];
    if(write){dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{stage(event);});} // Off the game's thread.
}
void mp_game_sample(void){stage(report[@"stage"]);}
static NSString *sha256(const void *bytes,size_t size) {
    unsigned char digest[32];CC_SHA256(bytes,(CC_LONG)size,digest);NSMutableString *h=[NSMutableString string];
    for(unsigned i=0;i<32;i++)[h appendFormat:@"%02x",digest[i]];return h;
}
// Crash report: fault address, registers, the running guest initializer and
// a frame-pointer backtrace with guest image offsets (stderr / console).
extern const char *mp_locate(uintptr_t,uintptr_t *);
extern const char *volatile mp_init_image;extern volatile unsigned mp_init_index;extern volatile uint32_t mp_init_offset;
static void crash_line(const char *label,uintptr_t a) {
    char line[320];uintptr_t off;const char *g=mp_locate(a,&off);Dl_info info;int n;
    if(g)n=snprintf(line,sizeof line,"[crash] %s %#lx = %s+%#lx\n",label,(unsigned long)a,g,(unsigned long)off);
    else if(a && dladdr((void *)a,&info) && info.dli_fname)n=snprintf(line,sizeof line,"[crash] %s %#lx = %s`%s+%#lx\n",label,(unsigned long)a,strrchr(info.dli_fname,'/')?strrchr(info.dli_fname,'/')+1:info.dli_fname,info.dli_sname?info.dli_sname:"?",(unsigned long)(a-(uintptr_t)(info.dli_sname?info.dli_saddr:info.dli_fbase)));
    else n=snprintf(line,sizeof line,"[crash] %s %#lx\n",label,(unsigned long)a);
    write(2,line,(size_t)n);
}
static void crash(int sig,siginfo_t *si,void *context) {
    ucontext_t *uc=context;char line[256];
    int n=snprintf(line,sizeof line,"[crash] signal %d at %p; initializer %s #%u offset %#x\n",sig,si->si_addr,mp_init_image?mp_init_image:"-",mp_init_index,mp_init_offset);write(2,line,(size_t)n);
    extern const char *mp_cp_va_tail(uintptr_t);const char *tail=mp_cp_va_tail((uintptr_t)si->si_addr);
    if(tail){n=snprintf(line,sizeof line,"[crash] fault is in the %s (raise MP_VA_CAP_GB)\n",tail);write(2,line,(size_t)n);}
    crash_line("pc",uc->uc_mcontext->__ss.__pc);crash_line("lr",uc->uc_mcontext->__ss.__lr);
    for(int i=0;i<9;i++){char r[8];snprintf(r,sizeof r,"x%d",i);crash_line(r,uc->uc_mcontext->__ss.__x[i]);}
    uintptr_t fp=uc->uc_mcontext->__ss.__fp;
    for(int i=0;i<40 && fp && !(fp&7);i++){uintptr_t *frame=(uintptr_t *)fp;crash_line("frame",frame[1]);if(frame[0]<=fp)break;fp=frame[0];}
    signal(sig,SIG_DFL);
}
int main(int argc,char **argv) {
    @autoreleasepool {
        reportLock=[NSLock new];NSSetUncaughtExceptionHandler(exception);
        static char altstack[65536];stack_t ss={.ss_sp=altstack,.ss_size=sizeof altstack};sigaltstack(&ss,NULL); // Reports stack overflows too.
        struct sigaction sa={0};sa.sa_sigaction=crash;sa.sa_flags=SA_SIGINFO|SA_ONSTACK;
        for(int sig=SIGILL;sig<=SIGSYS;sig++)if(sig==SIGILL||sig==SIGTRAP||sig==SIGABRT||sig==SIGBUS||sig==SIGSEGV||sig==SIGFPE||sig==SIGSYS)sigaction(sig,&sa,NULL);
        NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        { // Documents/env.json: {"MP_MEMSIZE_GB":"3",...} applied before anything reads them (tuning without a rebuild).
            NSDictionary *env=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[documents stringByAppendingPathComponent:@"env.json"]]?:[NSData data] options:0 error:NULL];
            if([env isKindOfClass:NSDictionary.class])for(NSString *k in env)if([k hasPrefix:@"MP_"] && [env[k] isKindOfClass:NSString.class])setenv(k.UTF8String,[env[k] UTF8String],1);
        }
        if(!getenv("MP_CONSOLE")) { // devicectl --console streams output live instead.
            freopen([[documents stringByAppendingPathComponent:@"runtime-stderr.log"] fileSystemRepresentation],"w",stderr);
            freopen([[documents stringByAppendingPathComponent:@"runtime-stdout.log"] fileSystemRepresentation],"w",stdout);
        }
        setvbuf(stderr,NULL,_IOLBF,0);setvbuf(stdout,NULL,_IOLBF,0);
        reportPath=[documents stringByAppendingPathComponent:@"runtime.json"];
        report=[@{@"run_id":NSUUID.UUID.UUIDString,@"pid":@(getpid()),@"game":@"Cyberpunk 2077"} mutableCopy];stage(@"start");
        NSFileManager *fm=NSFileManager.defaultManager;
        BOOL debug=[fm fileExistsAtPath:[documents stringByAppendingPathComponent:@"debug"]];
        if(getenv("MP_VA_PROBE")) { // Address-space experiment: free ranges by hint, largest block, total.
            for(uint64_t a=0x200000000ull;a<0x8000000000ull;a+=0x400000000ull){void *r=mmap((void *)a,1ull<<30,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);fprintf(stderr,"[va] hint %#llx -> %p\n",a,r);if(r!=MAP_FAILED)munmap(r,1ull<<30);}
            {uint64_t runStart=0;int in=0;
             for(uint64_t a=0x200000000ull;a<=0x7000000000ull;a+=0x10000000ull){vm_address_t at=(vm_address_t)a;kern_return_t kr=a<0x7000000000ull?vm_allocate(mach_task_self(),&at,0x10000000,VM_FLAGS_FIXED):KERN_NO_SPACE;int ok=kr==KERN_SUCCESS;if(ok)vm_deallocate(mach_task_self(),at,0x10000000);
              if(ok&&!in){runStart=a;in=1;}if(!ok&&in){fprintf(stderr,"[va] FIXED ok %#llx-%#llx (%llu MB) then kr=%d\n",runStart,a,(a-runStart)>>20,kr);in=0;}}}
            {void *r=mmap((void *)0x8000000000ull,1ull<<30,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON|MAP_FIXED,-1,0);fprintf(stderr,"[va] FIXED 512GB -> %p\n",r);}
            {void *r=mmap(NULL,1ull<<30,PROT_NONE,MAP_PRIVATE|MAP_ANON,-1,0);fprintf(stderr,"[va] PROT_NONE 1 GB -> %p\n",r);}
            for(size_t gb=128;gb>=8;gb/=2){void *r=mmap(NULL,gb<<30,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);fprintf(stderr,"[va] single %zu GB -> %p\n",gb,r);if(r!=MAP_FAILED)munmap(r,gb<<30);}
            size_t total=0;void *keep[512];size_t sizes[512];int k=0;
            for(size_t mb=65536;mb>=256 && k<512;){void *r=mmap(NULL,mb<<20,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);if(r==MAP_FAILED){mb/=2;continue;}keep[k]=r;sizes[k++]=mb<<20;total+=mb;fprintf(stderr,"[va] +%zu MB at %p\n",mb,r);}
            fprintf(stderr,"[va] total reservable ~%zu MB\n",total);
            for(int i=0;i<k;i++)munmap(keep[i],sizes[i]);
            exit(0);
        }
        mp_cp_metal_install();report[@"gpu"]=mp_cp_metal_features();stage(@"gpu ready");
        NSDictionary *manifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"target" ofType:@"json"]] options:0 error:NULL];
        NSArray *images=manifest[@"images"];MPGuestSource sources[32];
        if(images.count<1 || images.count>32){stage(@"bad manifest");return 1;}
        for(NSUInteger i=0;i<images.count;i++) {
            NSDictionary *m=images[i];
            NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:m[@"container"]];
            if(!dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL)){report[@"error"]=[NSString stringWithUTF8String:dlerror()];stage(@"container failed");return 1;}
            const struct mach_header_64 *header=NULL;
            for(uint32_t j=0;j<_dyld_image_count();j++)if(!strcmp(_dyld_get_image_name(j),path.fileSystemRepresentation))header=(const struct mach_header_64 *)_dyld_get_image_header(j);
            unsigned long n=0;void *bytes=header?getsectiondata(header,"__TEXT","__guest",&n):NULL;size_t size=[m[@"slice_size"] unsignedLongValue];
            if(!bytes){report[@"error"]=m[@"name"];stage(@"missing resident section");return 1;}
            if(![sha256(bytes,size) isEqual:m[@"sha256"]]){report[@"error"]=m[@"name"];stage(@"guest hash mismatch");return 1;}
            sources[i]=(MPGuestSource){.path=strdup(path.fileSystemRepresentation),.section="__TEXT",.resident=bytes,.size=size};
        }
        stage(@"guest hashes verified");
        // Normal install layout inside Documents; the guest walks up from here.
        NSString *root=[documents stringByAppendingPathComponent:@"Cyberpunk 2077"];
        NSString *exe=[root stringByAppendingPathComponent:@"Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077"];
        [fm createDirectoryAtPath:exe.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        if(![fm fileExistsAtPath:exe])[fm createFileAtPath:exe contents:[NSData data] attributes:nil]; // Path anchor only; code is in the containers.
        setenv("MP_GUEST_EXECUTABLE_PATH",exe.fileSystemRepresentation,1);
        [fm createDirectoryAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Cyberpunk 2077"] withIntermediateDirectories:YES attributes:nil error:NULL]; // GameServices.log
        report[@"data_present"]=@{@"archive":@([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"archive"]]),@"engine":@([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"engine"]]),@"r6":@([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"r6"]])};
        chdir(root.fileSystemRepresentation);
        mp_extended_set_shim(mp_ios_shim);
        static char *guestArgs[34]={"Cyberpunk2077",NULL};int guestArgc=1;
        NSArray *arguments=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[documents stringByAppendingPathComponent:@"arguments.json"]]?:[NSData data] options:0 error:NULL];
        if([arguments isKindOfClass:NSArray.class])for(id a in arguments)if([a isKindOfClass:NSString.class] && guestArgc<33)guestArgs[guestArgc++]=strdup([a UTF8String]);
        MPServices services={.extensions=mp_cp_policy(),.argc=guestArgc,.argv=guestArgs};
        stage(@"loading group");char error[256];double t=CACurrentMediaTime();
        MPGroup *group=mp_group_open(sources,(unsigned)images.count,services,error);
        if(!group){report[@"error"]=[NSString stringWithUTF8String:error];stage(@"group load failed");return 1;}
        if(getenv("MP_SEL_SURVEY")) { // Selectors the game uses that no class on this device implements.
            NSMutableSet *have=[NSMutableSet set];int count=0;Class *classes=objc_copyClassList((unsigned *)&count);
            for(int i=0;i<count;i++)for(Class c=classes[i],m=object_getClass(classes[i]);c;c=(c==m?Nil:m)){unsigned n=0;Method *ms=class_copyMethodList(c,&n);for(unsigned j=0;j<n;j++)[have addObject:NSStringFromSelector(method_getName(ms[j]))];free(ms);}
            free(classes);
            NSString *list=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"selectors" ofType:@"txt"] encoding:NSUTF8StringEncoding error:NULL];
            for(NSString *sel in [list componentsSeparatedByString:@"\n"])if(sel.length && ![have containsObject:sel])fprintf(stderr,"[sel] missing %s\n",sel.UTF8String);
            fprintf(stderr,"[sel] survey done (%d classes)\n",count);exit(0);
        }
        unsigned rebases=0,binds=0,inits=0;
        for(unsigned i=0;i<mp_group_count(group);i++){MPStats s=mp_image_stats(mp_group_image(group,i));rebases+=s.rebases;binds+=s.binds;inits+=s.initializers;}
        report[@"load"]=@{@"seconds":@(CACurrentMediaTime()-t),@"rebases":@(rebases),@"binds":@(binds),@"initializers":@(inits)};
        if(debug){extern void mp_watchdog_start(void (^)(NSArray *));extern void mp_watchdog_set_sampler(void (^)(NSArray *));
            mp_watchdog_start(^(NSArray *stack){report[@"main_stack_stalled"]=stack;stage(@"main thread stalled (watchdog)");});
            mp_watchdog_set_sampler(^(NSArray *stack){report[@"main_stack_sample"]=stack;mp_game_sample();});}
        atexit_b(^{stage(@"process exit");});
        { // Memory breakdown every 5 s (always; one line): footprint, GPU (device), CPU (rest), headroom.
            id<MTLDevice> dev=MTLCreateSystemDefaultDevice();
            extern void mp_cp_gpu_timing_install(id<MTLDevice>);extern uint64_t mp_cp_gpu_busy_nanos(void);mp_cp_gpu_timing_install(dev);
            static thread_act_t mainThread;mainThread=mach_thread_self();
            [NSThread detachNewThreadWithBlock:^{uint64_t lastGpu=0,lastMain=0,lastAll=0;for(int t=0;;t+=5){
                // Main-thread and whole-process CPU time over the last 5 s.
                thread_basic_info_data_t ti;mach_msg_type_number_t tn=THREAD_BASIC_INFO_COUNT;uint64_t mainUs=0;
                if(thread_info(mainThread,THREAD_BASIC_INFO,(thread_info_t)&ti,&tn)==KERN_SUCCESS)mainUs=(uint64_t)ti.user_time.seconds*1000000+ti.user_time.microseconds+(uint64_t)ti.system_time.seconds*1000000+ti.system_time.microseconds;
                struct rusage ru;getrusage(RUSAGE_SELF,&ru);uint64_t allUs=(uint64_t)(ru.ru_utime.tv_sec+ru.ru_stime.tv_sec)*1000000+ru.ru_utime.tv_usec+ru.ru_stime.tv_usec;
                uint64_t gpuNs=mp_cp_gpu_busy_nanos();
                extern _Atomic unsigned long mp_tex_census[4];static const char *thermal[]={"nominal","fair","SERIOUS","CRITICAL"};
                NSInteger th=NSProcessInfo.processInfo.thermalState;
                if(t>0)fprintf(stderr,"[perf] t=%ds gpu_busy=%.0f%% main_thread=%.0f%% all_cpu=%.0f%% thermal=%s textures(managedRT=%lu managed=%lu shared=%lu private=%lu)\n",t,(gpuNs-lastGpu)/5e7,(mainUs-lastMain)/5e4,(allUs-lastAll)/5e4,
                    th>=0&&th<4?thermal[th]:"?",mp_tex_census[0],mp_tex_census[1],mp_tex_census[2],mp_tex_census[3]);
                lastGpu=gpuNs;lastMain=mainUs;lastAll=allUs;
                task_vm_info_data_t vm;mach_msg_type_number_t n=TASK_VM_INFO_COUNT;uint64_t fp=0;
                if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&vm,&n)==KERN_SUCCESS)fp=vm.phys_footprint;
                uint64_t gpu=dev.currentAllocatedSize;
                if(t%10==0) { // vmmap-style breakdown: dirty+compressed MB per VM tag (engine regions by address).
                    uint64_t byTag[256]={0},engine=0;vm_address_t addr=0;
                    for(;;){vm_size_t size=0;natural_t depth=1;struct vm_region_submap_info_64 info;mach_msg_type_number_t cnt=VM_REGION_SUBMAP_INFO_COUNT_64;
                        if(vm_region_recurse_64(mach_task_self(),&addr,&size,&depth,(vm_region_recurse_info_t)&info,&cnt)!=KERN_SUCCESS)break;
                        if(info.is_submap){depth++;continue;}
                        uint64_t bytes=((uint64_t)info.pages_dirtied+info.pages_swapped_out)*vm_page_size;
                        if(addr>=0x7000000000ull && addr<0x8000000000ull && info.user_tag==0)engine+=bytes;else byTag[info.user_tag&255]+=bytes;
                        addr+=size;}
                    char line[512];int n=snprintf(line,sizeof line,"[vmtags] t=%ds engine-regions=%llu",t,engine>>20);
                    for(int k=0;k<8;k++){int best=-1;for(int g=0;g<256;g++)if(byTag[g]>(64ull<<20) && (best<0||byTag[g]>byTag[best]))best=g;if(best<0)break;
                        n+=snprintf(line+n,sizeof line-n," tag%d=%llu",best,byTag[best]>>20);byTag[best]=0;}
                    fprintf(stderr,"%s MB\n",line);
                }
                double fps=[mp_stk_frame_window()[@"window_fps"] doubleValue];
                fprintf(stderr,"[budget] t=%ds fps=%.1f footprint=%llu MB gpu=%llu MB cpu=%llu MB free=%zu MB\n",t,fps,fp>>20,gpu>>20,(fp>gpu?fp-gpu:0)>>20,os_proc_available_memory()>>20);
                sleep(5);}}];
        }
        if(getenv("MP_CONSOLE"))[NSThread detachNewThreadWithBlock:^{ // Memory headroom, once a second.
            for(int t=0;;t++){fprintf(stderr,"[memwatch] t=%ds available=%zu MB\n",t,os_proc_available_memory()>>20);sleep(1);}
        }];
        // UIKit first; the guest's main enters from a run-loop timer (see
        // Lifecycle.m). If it calls -[NSApp run], the run loop keeps running.
        static MPGroup *entered;entered=group;static MPServices enteredServices;enteredServices=services;
        mp_game_set_launch_hook(^{
            stage(@"guest entry");int result=-1;
            int status=mp_image_main(mp_group_image(entered,0),enteredServices.argc,enteredServices.argv,&result);
            report[@"entry_status"]=@(status);report[@"guest_exit"]=@(result);stage(@"guest returned");exit(status?status:result);
        });
        // Report sampling off the game's (main) thread: JSON + file write every 2 s.
        dispatch_source_t sampler=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
        dispatch_source_set_timer(sampler,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),2*NSEC_PER_SEC,NSEC_PER_SEC/2);
        dispatch_source_set_event_handler(sampler,^{mp_game_sample();});dispatch_resume(sampler);static dispatch_source_t keep;keep=sampler;
        mp_game_queue_events=YES; // Cyberpunk drains the AppKit queue itself.
        { // Render resolutions at the panel's aspect ratio (iPhone 18 Pro 2622x1206): 900p first.
            CGSize native=UIScreen.mainScreen.nativeBounds.size;if(native.height>native.width)native=CGSizeMake(native.height,native.width);
            double aspect=native.width/native.height;CGSize modes[6];unsigned n=0;
            int heights[]={900,1080,804,720,603};
            for(unsigned i=0;i<5;i++){int h=heights[i];int w=((int)lround(h*aspect))&~1;if(h<=native.height)modes[n++]=CGSizeMake(w,h);}
            modes[n++]=native;
            extern void mp_display_set_modes(const CGSize *,unsigned);mp_display_set_modes(modes,n);
        }
        mp_game_touch_scroll=YES;mp_game_appkit_points=YES;
        extern void mp_cp_install_controls(void);mp_cp_install_controls(); // Touch keys + stick (temporary).
        return mp_game_run_uikit();
    }
}
