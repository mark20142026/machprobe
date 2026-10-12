#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include "Extended.h"
#include "ImageShim.h"
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>
#include <CommonCrypto/CommonDigest.h>
#include <unistd.h>
static NSString *reportPath;
static NSMutableDictionary *report;
static void stage(NSString *value) {
    report[@"stage"]=value;
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:reportPath atomically:YES];
}
int main(int argc,char **argv) {
    @autoreleasepool {
        NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        reportPath=[documents stringByAppendingPathComponent:@"runtime.json"];
        report=[@{@"run_id":NSUUID.UUID.UUIDString,@"pid":@(getpid())} mutableCopy];stage(@"start");
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
        mp_extended_set_shim(mp_ios_shim);
        char error[256];MPServices services={.extensions=mp_extended_policy()};stage(@"loading");
        MPImage *image=mp_image_open_embedded(path.fileSystemRepresentation,"__TEXT",bytes,size,services,error);
        if(!image){report[@"error"]=[NSString stringWithUTF8String:error];stage(@"load failed");return 1;}
        MPStats stats=mp_image_stats(image);report[@"rebases"]=@(stats.rebases);report[@"binds"]=@(stats.binds);stage(@"registering metadata");
        if(!mp_register_metadata(image,error)){report[@"error"]=[NSString stringWithUTF8String:error];stage(@"metadata failed");return 1;}
        // The guest owns SwiftUI App.main and creates the platform application.
        // Starting a separate UIApplication first would compete for lifecycle.
        for(NSURL *font in [NSBundle.mainBundle URLsForResourcesWithExtension:@"ttf" subdirectory:@"Fonts"])
            CTFontManagerRegisterFontsForURL((__bridge CFURLRef)font,kCTFontManagerScopeProcess,NULL);
        stage(@"guest entry");int result=-1;
        int status=mp_image_main(image,argc,argv,&result);
        report[@"entry_status"]=@(status);report[@"guest_exit"]=@(result);stage(@"guest returned");return status?status:result;
    }
}
