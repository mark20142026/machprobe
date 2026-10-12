#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include "Extended.h"
#include "GameBridge.h"
#include "Policy.h"
#include "ImageShim.h"
#import "Observe.h"
#import "Input.h"
#import "Lifecycle.h"
#import "MetalCompat.h"
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>
#include <CommonCrypto/CommonDigest.h>
#include <unistd.h>
extern const MPExtensions *mp_large_game_policy(void);
extern NSDictionary *mp_metal_probe(void);
extern NSDictionary *mp_uikit_probe(void);
extern NSDictionary *mp_legacy_presentation_stats(void);
static NSString *reportPath;
static NSMutableDictionary *report;
static void stage(NSString *value) {
    report[@"stage"]=value;
    report[@"presentation"]=mp_legacy_presentation_stats();
    report[@"frames"]=mp_game_frame_stats();report[@"input"]=mp_game_input_stats();report[@"metal"]=mp_game_metal_stats();report[@"audio"]=mp_game_audio_stats();
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:reportPath atomically:YES];
}
void mp_audio_probe_finished(NSDictionary *result){report[@"audio_probe"]=result;stage(@"Audio probe complete");}
extern void mp_start_audio_probe(void);
static BOOL audioProbePending;
static void exception(NSException *e){report[@"exception"]=e.description;report[@"stack"]=e.callStackSymbols;stage(@"exception");}
void mp_game_trace(NSString *event){
    NSMutableArray *events=report[@"events"];if(!events){events=[NSMutableArray new];report[@"events"]=events;}
    if(events.count<200)[events addObject:event];stage(event);
}
void mp_game_sample(void){stage(report[@"stage"]);if(audioProbePending){audioProbePending=NO;mp_start_audio_probe();}}
int main(int argc,char **argv) {
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(exception);
        NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        freopen([[documents stringByAppendingPathComponent:@"runtime-stderr.log"] fileSystemRepresentation],"w",stderr);
        freopen([[documents stringByAppendingPathComponent:@"runtime-stdout.log"] fileSystemRepresentation],"w",stdout);
        setvbuf(stderr,NULL,_IONBF,0);setvbuf(stdout,NULL,_IONBF,0);
        reportPath=[documents stringByAppendingPathComponent:@"runtime.json"];
        report=[@{@"run_id":NSUUID.UUID.UUIDString,@"pid":@(getpid())} mutableCopy];stage(@"start");
        if([NSFileManager.defaultManager fileExistsAtPath:[documents stringByAppendingPathComponent:@"run-uikit-probe"]]) {
            stage(@"running independent UIKit probe");report[@"uikit_probe"]=mp_uikit_probe();stage(@"UIKit probe complete");return 0;
        }
        if([NSFileManager.defaultManager fileExistsAtPath:[documents stringByAppendingPathComponent:@"run-metal-probe"]]) {
            stage(@"running independent Metal probe");report[@"metal_probe"]=mp_metal_probe();stage(@"Metal probe complete");return 0;
        }
        if([NSFileManager.defaultManager fileExistsAtPath:[documents stringByAppendingPathComponent:@"run-audio-probe"]]) {
            stage(@"running independent Audio probe");audioProbePending=YES;[[MPGameApplication sharedApplication] run];return 0;
        }
        NSDictionary *manifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"target" ofType:@"json"]] options:0 error:NULL];
        NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"MPGuest.dylib"];
        void *handle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
        if(!handle){report[@"error"]=[NSString stringWithUTF8String:dlerror()];stage(@"container failed");return 1;}
        const struct mach_header_64 *header=NULL;
        for(uint32_t i=0;i<_dyld_image_count();i++)if(!strcmp(_dyld_get_image_name(i),path.fileSystemRepresentation))header=(const struct mach_header_64 *)_dyld_get_image_header(i);
        unsigned long n=0;void *bytes=header?getsectiondata(header,"__TEXT","__guest",&n):NULL;
        size_t size=[manifest[@"slice_size"] unsignedLongValue];
        if(!bytes){stage(@"missing resident section");return 1;}
        unsigned char digest[32];CC_SHA256(bytes,(CC_LONG)size,digest);NSMutableString *hash=[NSMutableString string];
        for(unsigned i=0;i<32;i++)[hash appendFormat:@"%02x",digest[i]];
        report[@"guest_sha256"]=hash;
        if(![hash isEqual:manifest[@"arm64_sha256"]]){stage(@"guest hash mismatch");return 1;}
        
        // Documented launcher environment, pointing to normal writable app data.
        NSString *userdata=[documents stringByAppendingPathComponent:@"userdata"];
        [NSFileManager.defaultManager createDirectoryAtPath:userdata withIntermediateDirectories:YES attributes:nil error:NULL];
        setenv("VELOREN_USERDATA",userdata.fileSystemRepresentation,1);
        NSString *assets=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"assets"];
        if(![NSFileManager.defaultManager fileExistsAtPath:assets])assets=[documents stringByAppendingPathComponent:@"assets"];
        setenv("VELOREN_ASSETS",assets.fileSystemRepresentation,1);
        mp_extended_set_shim(mp_ios_shim);
        char error[256];NSArray *arguments=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[documents stringByAppendingPathComponent:@"arguments.json"]]?:[NSData data] options:0 error:NULL];
        if(![arguments isKindOfClass:NSArray.class])arguments=@[];
        if(arguments.count>32){stage(@"too many guest arguments");return 1;}
        char *guestArgs[34]={"veloren-voxygen",NULL};
        for(NSUInteger i=0;i<arguments.count;i++) {
            if(![arguments[i] isKindOfClass:NSString.class] || [arguments[i] length]>2048){stage(@"invalid guest argument");return 1;}
            guestArgs[i+1]=(char *)[arguments[i] UTF8String];
        }
        MPServices services={.extensions=mp_large_game_policy(),.argc=(int)arguments.count+1,.argv=guestArgs};stage(@"loading");
        MPImage *image=mp_image_open_embedded(path.fileSystemRepresentation,"__TEXT",bytes,size,services,error);
        if(!image){report[@"error"]=[NSString stringWithUTF8String:error];stage(@"load failed");return 1;}
        MPStats stats=mp_image_stats(image);report[@"rebases"]=@(stats.rebases);report[@"binds"]=@(stats.binds);stage(@"registering metadata");
        if(!mp_register_metadata(image,error)){report[@"error"]=[NSString stringWithUTF8String:error];stage(@"metadata failed");return 1;}
        // The original macOS main calls NSApplication.run. That adapter starts
        // UIKit and delivers AppKit launch notifications to the guest delegate.
        for(NSURL *font in [NSBundle.mainBundle URLsForResourcesWithExtension:@"ttf" subdirectory:@"Fonts"])
            CTFontManagerRegisterFontsForURL((__bridge CFURLRef)font,kCTFontManagerScopeProcess,NULL);
        chdir(NSBundle.mainBundle.bundlePath.fileSystemRepresentation);
        stage(@"guest entry");int result=-1;
        int status=mp_image_main(image,services.argc,services.argv,&result);
        report[@"entry_status"]=@(status);report[@"guest_exit"]=@(result);stage(@"guest returned");return status?status:result;
    }
}
