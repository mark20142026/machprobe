#import "Probe.h"
#include "runtime.h"
#include <CommonCrypto/CommonDigest.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <unistd.h>
static NSString *hash(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
    NSMutableString *s=[NSMutableString string];for(unsigned i=0;i<sizeof bytes;i++)[s appendFormat:@"%02x",bytes[i]];return s;
}
NSDictionary *MPProbe(NSString *resources,NSString *scratch,BOOL ios) {
    NSDictionary *manifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[resources stringByAppendingPathComponent:@"target.json"]] options:0 error:NULL];
    NSMutableDictionary *report=[@{@"run_id":NSUUID.UUID.UUIDString,@"uid":@(getuid()),@"pid":@(getpid()),@"ios":@(ios),@"symbol_addresses_are_not_abi_proof":@YES} mutableCopy];
    NSMutableDictionary *loads=[NSMutableDictionary dictionary];
    for(NSString *name in @[@"original",@"arm64"]) {
        NSData *data=[[NSData alloc] initWithBase64EncodedData:[NSData dataWithContentsOfFile:[resources stringByAppendingPathComponent:[name stringByAppendingString:@".b64"]]] options:0];
        NSString *expected=manifest[[name stringByAppendingString:@"_sha256"]];
        BOOL matches=data && [hash(data) isEqual:expected];
        NSMutableDictionary *r=[@{@"sha256":data?hash(data):@"missing",@"matches":@(matches)} mutableCopy];loads[name]=r;
        NSString *path=[scratch stringByAppendingPathComponent:name];
        if(!matches || ![data writeToFile:path atomically:YES]){r[@"error"]=@"resource hash/write failure";continue;}
        char error[256];MPImage *image=mp_image_open(path.fileSystemRepresentation,(MPServices){0},error);
        r[@"loads"]=@(image!=NULL);r[@"error"]=[NSString stringWithUTF8String:error];r[@"entry_called"]=@NO;
        if(image)mp_image_close(image);
    }
    report[@"loader"]=loads;
    NSMutableDictionary *handles=[NSMutableDictionary dictionary],*libraries=[NSMutableDictionary dictionary];
    for(NSDictionary *library in manifest[@"libraries"]) {
        NSString *path=library[@"name"],*host=path;
        if(ios) {
            NSRange r=[path rangeOfString:@".framework/Versions/"];
            if(r.location!=NSNotFound)host=[[path substringToIndex:r.location+10] stringByAppendingPathComponent:path.lastPathComponent];
        }
        dlerror();void *handle=dlopen(host.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
        const char *error=handle?NULL:dlerror();
        libraries[path]=@{@"host_path":host,@"available":@(handle!=NULL),@"error":error?[NSString stringWithUTF8String:error]:@""};
        if(handle)handles[path]=[NSValue valueWithPointer:handle];
    }
    NSMutableArray *symbols=[NSMutableArray array];unsigned missingStrong=0;
    for(NSDictionary *symbol in manifest[@"imports"]) {
        NSString *name=symbol[@"name"],*library=symbol[@"library"];
        void *handle=[handles[library] pointerValue];
        // Mach-O's leading underscore is not part of the dlsym spelling.
        NSString *lookup=[name hasPrefix:@"_"]?[name substringFromIndex:1]:name;
        void *address=handle?dlsym(handle,lookup.UTF8String):NULL;
        BOOL weak=[symbol[@"weak_import"] boolValue];if(!address && !weak)missingStrong++;
        [symbols addObject:@{@"name":name,@"library":library?:@"",@"available":@(address!=NULL),@"weak":@(weak)}];
    }
    report[@"libraries"]=libraries;report[@"symbols"]=symbols;report[@"missing_strong"]=@(missingStrong);
    NSMutableArray *injected=[NSMutableArray array];for(uint32_t i=0;i<_dyld_image_count();i++) {
        NSString *name=[NSString stringWithUTF8String:_dyld_get_image_name(i)];
        if([name containsString:@"vphone"] || [name containsString:@"camfix"])[injected addObject:name];
    }
    report[@"vm_images"]=injected;
    for(NSValue *value in handles.allValues)dlclose(value.pointerValue);
    report[@"complete"]=@YES;return report;
}
