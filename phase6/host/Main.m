// iOS host for the unchanged SuperTuxKart 1.5 arm64 images. Each guest image
// lives in its own signed container (see phase6/tools/build.py); this host
// verifies their bytes, opens them as one group and enters the executable.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
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
extern const MPExtensions *mp_stk_policy(void);
extern NSDictionary *mp_metal_probe(void);
extern NSDictionary *mp_uikit_probe(void);
extern NSDictionary *mp_legacy_presentation_stats(void);
static NSString *reportPath;
static NSMutableDictionary *report;
static NSLock *reportLock;
static void stage(NSString *value) {
    [reportLock lock];
    report[@"stage"]=value;
    report[@"presentation"]=mp_legacy_presentation_stats();
    extern NSDictionary *mp_base_vertex_stats(void);report[@"base_vertex"]=mp_base_vertex_stats();
    extern NSDictionary *mp_stk_frame_window(void);report[@"frame_window"]=mp_stk_frame_window();
    extern NSArray *mp_draw_probe_results(void);NSArray *draws=mp_draw_probe_results();if(draws.count)report[@"draw_probe"]=draws;
    extern NSDictionary *mp_draw_probe_pipelines(void);report[@"draw_pipelines"]=mp_draw_probe_pipelines();
    extern NSDictionary *mp_draw_probe_kinds(void);NSDictionary *kinds=mp_draw_probe_kinds();if(kinds.count)report[@"draw_kinds"]=kinds;
    extern NSDictionary *mp_legacy_forwarded_selectors(void);report[@"device_selectors"]=mp_legacy_forwarded_selectors();
    report[@"frames"]=mp_game_frame_stats();report[@"input"]=mp_game_input_stats();report[@"metal"]=mp_game_metal_stats();report[@"audio"]=mp_game_audio_stats();
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:reportPath atomically:YES];
    [reportLock unlock];
}
void mp_audio_probe_finished(NSDictionary *result){report[@"audio_probe"]=result;stage(@"Audio probe complete");}
extern NSArray *mp_selector_survey_results(void);
static void exception(NSException *e){report[@"exception"]=e.description;report[@"stack"]=e.callStackSymbols;report[@"selector_survey"]=mp_selector_survey_results();stage(@"exception");}
// Traces are frequent during play (every key event). Record immediately but
// write the report at most every 0.5 s; stage() itself is reserved for
// lifecycle transitions and exceptions, which write at once.
void mp_game_trace(NSString *event){
    static double lastWrite;static BOOL pending;
    [reportLock lock];
    NSMutableArray *events=report[@"events"];if(!events){events=[NSMutableArray new];report[@"events"]=events;}
    if(events.count>=400)[events removeObjectAtIndex:0];
    [events addObject:event];report[@"stage"]=event;
    double now=CACurrentMediaTime();BOOL write=now-lastWrite>0.5;if(write)lastWrite=now;else if(!pending){pending=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)),dispatch_get_main_queue(),^{pending=NO;stage(report[@"stage"]);});}
    [reportLock unlock];
    if(write)stage(event);
}
void mp_game_sample(void){stage(report[@"stage"]);}
static NSMutableDictionary *probeResults;
void mp_probe_unresolved(MPImage *image,const char *library,const char *symbol,int lazy) {
    if(!probeResults)probeResults=[NSMutableDictionary dictionary];
    NSString *key=[NSString stringWithFormat:@"%s%s",lazy?"lazy ":"",library];
    NSMutableArray *list=probeResults[key];if(!list){list=[NSMutableArray array];probeResults[key]=list;}
    NSString *entry=[NSString stringWithFormat:@"%s (%s)",symbol,mp_image_install_name(image)?:"main"];
    if(![list containsObject:entry])[list addObject:entry];
}
static NSDictionary *mp_probe_results(void){return probeResults?:@{};}
static NSString *sha256(const void *bytes,size_t size) {
    unsigned char digest[32];CC_SHA256(bytes,(CC_LONG)size,digest);NSMutableString *hash=[NSMutableString string];
    for(unsigned i=0;i<32;i++)[hash appendFormat:@"%02x",digest[i]];
    return hash;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        reportLock=[NSLock new];
        NSSetUncaughtExceptionHandler(exception);
        NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        freopen([[documents stringByAppendingPathComponent:@"runtime-stderr.log"] fileSystemRepresentation],"w",stderr);
        freopen([[documents stringByAppendingPathComponent:@"runtime-stdout.log"] fileSystemRepresentation],"w",stdout);
        setvbuf(stderr,NULL,_IONBF,0);setvbuf(stdout,NULL,_IONBF,0);
        reportPath=[documents stringByAppendingPathComponent:@"runtime.json"];
        report=[@{@"run_id":NSUUID.UUID.UUIDString,@"pid":@(getpid())} mutableCopy];stage(@"start");
        NSFileManager *fm=NSFileManager.defaultManager;
        if([fm fileExistsAtPath:[documents stringByAppendingPathComponent:@"run-uikit-probe"]]){report[@"uikit_probe"]=mp_uikit_probe();stage(@"UIKit probe complete");return 0;}
        if([fm fileExistsAtPath:[documents stringByAppendingPathComponent:@"run-vertex-probe"]]){extern NSDictionary *mp_vertex_format_probe(void);report[@"vertex_probe"]=mp_vertex_format_probe();stage(@"vertex probe complete");return 0;}
        if([fm fileExistsAtPath:[documents stringByAppendingPathComponent:@"run-metal-probe"]]){report[@"metal_probe"]=mp_metal_probe();stage(@"Metal probe complete");return 0;}
        NSDictionary *manifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"target" ofType:@"json"]] options:0 error:NULL];
        NSArray *images=manifest[@"images"];
        if(images.count<1 || images.count>32){stage(@"bad manifest");return 1;}
        MPGuestSource sources[32];NSMutableArray *verified=[NSMutableArray array];
        for(NSUInteger i=0;i<images.count;i++) {
            NSDictionary *m=images[i];
            NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:m[@"container"]];
            if(!dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL)){report[@"error"]=[NSString stringWithUTF8String:dlerror()];stage(@"container failed");return 1;}
            const struct mach_header_64 *header=NULL;
            for(uint32_t j=0;j<_dyld_image_count();j++)if(!strcmp(_dyld_get_image_name(j),path.fileSystemRepresentation))header=(const struct mach_header_64 *)_dyld_get_image_header(j);
            unsigned long n=0;void *bytes=header?getsectiondata(header,"__TEXT","__guest",&n):NULL;
            size_t size=[m[@"slice_size"] unsignedLongValue];
            if(!bytes){report[@"error"]=m[@"name"];stage(@"missing resident section");return 1;}
            if(![sha256(bytes,size) isEqual:m[@"sha256"]]){report[@"error"]=m[@"name"];stage(@"guest hash mismatch");return 1;}
            [verified addObject:m[@"name"]];
            sources[i]=(MPGuestSource){.path=strdup(path.fileSystemRepresentation),.section="__TEXT",.resident=bytes,.size=size};
        }
        report[@"verified_images"]=verified;stage(@"guest hashes verified");
        // Documented SuperTuxKart launcher environment: data tree pushed to
        // Documents/stkdata/data, saves in Documents/save, cwd writable.
        NSString *datadir=[documents stringByAppendingPathComponent:@"stkdata"];
        NSString *savedir=[documents stringByAppendingPathComponent:@"save"];
        NSString *config=[savedir stringByAppendingPathComponent:@"config-0.10"];
        [fm createDirectoryAtPath:config withIntermediateDirectories:YES attributes:nil error:NULL];
        // Seed the game's own config once with render_driver="vulkan": iOS
        // has no desktop OpenGL. The game owns the file afterwards.
        NSString *seed=[NSBundle.mainBundle pathForResource:@"config-seed" ofType:@"xml"];
        NSString *configFile=[config stringByAppendingPathComponent:@"config.xml"];
        if(seed && ![fm fileExistsAtPath:configFile])[fm copyItemAtPath:seed toPath:configFile error:NULL];
        // MoltenVK's documented config: allocate each resource individually
        // rather than sub-allocating placement MTLHeaps (see phase6 findings).
        // Optional diagnostic environment (Documents/env.json: {"NAME":"value"}),
        // e.g. MoltenVK's documented MVK_CONFIG_* settings.
        NSDictionary *extraEnv=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[documents stringByAppendingPathComponent:@"env.json"]]?:[NSData data] options:0 error:NULL];
        if([extraEnv isKindOfClass:NSDictionary.class])for(NSString *k in extraEnv)if(([k hasPrefix:@"MVK_CONFIG_"] || [k hasPrefix:@"MP_"]) && [extraEnv[k] isKindOfClass:NSString.class]) {
            NSString *value=[extraEnv[k] stringByReplacingOccurrencesOfString:@"$DOCUMENTS" withString:documents];
            [fm createDirectoryAtPath:[documents stringByAppendingPathComponent:@"mvkdump"] withIntermediateDirectories:YES attributes:nil error:NULL];
            setenv(k.UTF8String,value.UTF8String,1);
        }
        report[@"extra_env"]=extraEnv?:@{};
        if(!getenv("MVK_CONFIG_USE_MTLHEAP"))setenv("MVK_CONFIG_USE_MTLHEAP","0",1);
        setenv("SUPERTUXKART_DATADIR",datadir.fileSystemRepresentation,1);
        setenv("SUPERTUXKART_SAVEDIR",savedir.fileSystemRepresentation,1);
        chdir(documents.fileSystemRepresentation);
        mp_extended_set_shim(mp_ios_shim);
        // Plain Apple-family device for MoltenVK: no legacy Mac feature-set
        // profile, which would advertise BC formats this GPU cannot sample.
        extern void mp_legacy_set_mac_profile(BOOL);mp_legacy_set_mac_profile(NO);
        extern void mp_selector_survey_install(void);
        static BOOL survey;survey=[fm fileExistsAtPath:[documents stringByAppendingPathComponent:@"run-selector-survey"]];

        static NSMutableDictionary *missing;
        if([fm fileExistsAtPath:[documents stringByAppendingPathComponent:@"run-import-probe"]]) {
            // Link-only probe through the real iOS resolution chain.
            static MPExtensions probe;probe=*mp_stk_policy();missing=[NSMutableDictionary dictionary];
            probe.unresolved=mp_probe_unresolved;
            char *probeArgs[]={"supertuxkart",NULL};MPServices s={.extensions=&probe,.argc=1,.argv=probeArgs};char e[256];
            mp_group_open(sources,(unsigned)images.count,s,e);
            report[@"import_probe"]=mp_probe_results();report[@"error"]=[NSString stringWithUTF8String:e];stage(@"import probe complete");return 0;
        }
        // Optional guest arguments (Documents/arguments.json), e.g. --race-now.
        static char *guestArgs[34]={"supertuxkart",NULL};int guestArgc=1;
        NSArray *arguments=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[documents stringByAppendingPathComponent:@"arguments.json"]]?:[NSData data] options:0 error:NULL];
        if([arguments isKindOfClass:NSArray.class])for(id a in arguments)if([a isKindOfClass:NSString.class] && guestArgc<33 && [a length]<512)guestArgs[guestArgc++]=strdup([a UTF8String]);
        report[@"guest_arguments"]=arguments?:@[];
        MPServices services={.extensions=mp_stk_policy(),.argc=guestArgc,.argv=guestArgs};
        stage(@"loading group");
        char error[256];
        MPGroup *group=mp_group_open(sources,(unsigned)images.count,services,error);
        if(!group){report[@"error"]=[NSString stringWithUTF8String:error];stage(@"group load failed");return 1;}
        unsigned rebases=0,binds=0,inits=0;
        for(unsigned i=0;i<mp_group_count(group);i++){MPStats s=mp_image_stats(mp_group_image(group,i));rebases+=s.rebases;binds+=s.binds;inits+=s.initializers;}
        report[@"rebases"]=@(rebases);report[@"binds"]=@(binds);report[@"initializers"]=@(inits);
        if(survey)mp_selector_survey_install(); // After linking: declared classes now exist.
        // SDL's error text survives the guest's own exit for the report.
        static const char *(*sdlError)(void);
        for(unsigned i=0;i<mp_group_count(group);i++){const char *n=mp_image_install_name(mp_group_image(group,i));if(n && strstr(n,"libSDL2"))sdlError=(const char *(*)(void))mp_image_symbol(mp_group_image(group,i),"_SDL_GetError");}
        atexit_b(^{if(survey)report[@"selector_survey"]=mp_selector_survey_results();if(sdlError){const char *e=sdlError();if(e && *e)report[@"sdl_error"]=[NSString stringWithUTF8String:e];}stage(@"process exit");});
        // STK owns its main loop: start UIKit, then enter the guest from the
        // run loop once the scene exists (SDL's iOS SDL_main pattern).
        static MPGroup *entered;entered=group;static MPServices enteredServices;enteredServices=services;
        mp_game_set_launch_hook(^{
            stage(@"guest entry");int result=-1;
            int status=mp_image_main(mp_group_image(entered,0),enteredServices.argc,enteredServices.argv,&result);
            report[@"entry_status"]=@(status);report[@"guest_exit"]=@(result);stage(@"guest returned");exit(status?status:result);
        });
        extern void mp_watchdog_start(void (^)(NSArray *));
        mp_watchdog_start(^(NSArray *stack){report[@"main_stack_stalled"]=stack;if(survey)report[@"selector_survey"]=mp_selector_survey_results();stage(@"main thread stalled (watchdog)");});
        extern void mp_watchdog_set_sampler(void (^)(NSArray *));
        mp_watchdog_set_sampler(^(NSArray *stack){report[@"main_stack_sample"]=stack;if(survey)report[@"selector_survey"]=mp_selector_survey_results();mp_game_sample();});
        // Touch gamepad above the guest's window once it is presented.
        extern void mp_install_gamepad(UIWindow *);
        [NSNotificationCenter.defaultCenter addObserverForName:@"NSWindowDidBecomeKeyNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            dispatch_async(dispatch_get_main_queue(),^{mp_install_gamepad(mp_game_host_view().window);});
        }];
        return mp_game_run_uikit();
    }
}
