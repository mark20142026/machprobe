#import "Audit.h"
#include "runtime.h"
#include "guest_abi.h"
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <string.h>

static unsigned descriptors(void) { unsigned n=0;for(int fd=0;fd<256;fd++)if(fcntl(fd,F_GETFD)!=-1)n++;return n; }
static unsigned regions(void) {
    vm_address_t address=0;vm_size_t size;unsigned n=0;
    while(1) {
        vm_region_basic_info_data_64_t info;mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;mach_port_t object=0;
        kern_return_t kr=vm_region_64(mach_task_self(),&address,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&count,&object);
        if(object)mach_port_deallocate(mach_task_self(),object);
        if(kr!=KERN_SUCCESS || !size || address>UINT64_MAX-size)break;
        n++;address+=size;
    }
    return n;
}
typedef struct {unsigned callbacks;MPState state;} Observation;
static void changed(void *context,MPState state,const char *message) { (void)message;Observation *o=context;o->callbacks++;o->state=state; }
static NSDictionary *audit_cycles(NSDictionary *manifest,BOOL keepContainer) {
    NSMutableDictionary *report=[NSMutableDictionary dictionary];
    NSMutableArray *cycles=[NSMutableArray array],*errors=[NSMutableArray array];
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:manifest[@"interactive"][@"container"]];
    unsigned beforeFD=0,beforeRegions=0;BOOL all=YES;
    void *held=keepContainer?dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL):NULL;
    // One warm-up avoids counting framework/dyld initialization as a leak.
    for(unsigned i=0;i<21;i++)@autoreleasepool {
        if(i==1){beforeFD=descriptors();beforeRegions=regions();}
        char error[256]={0};void *handle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
        const struct mach_header_64 *header=NULL;
        for(uint32_t j=0;handle && j<_dyld_image_count();j++)if(!strcmp(_dyld_get_image_name(j),path.fileSystemRepresentation))header=(const struct mach_header_64 *)_dyld_get_image_header(j);
        unsigned long length=0;void *bytes=header?getsectiondata(header,"__TEXT","__guest",&length):NULL;
        size_t size=[manifest[@"interactive"][@"size"] unsignedLongValue];
        MPImage *im=bytes?mp_image_open_embedded(path.fileSystemRepresentation,"__TEXT",bytes,size,(MPServices){0},error):NULL;
        BOOL pass=im!=NULL;
        if(im) {
            if(i==1) {
                MPImage *duplicate=mp_image_open_embedded(path.fileSystemRepresentation,"__TEXT",bytes,size,(MPServices){0},error);
                report[@"duplicate_rejected"]=@(!duplicate);report[@"duplicate_diagnostic"]=[NSString stringWithUTF8String:error];
                if(duplicate){pass=NO;mp_image_close(duplicate);}
            }
            MPOpenGuest open=mp_image_symbol(im,"_mp_guest_open");Observation observation={0};
            MPHost host={sizeof host,MP_ABI_VERSION,&observation,changed};MPGuest guest={.size=sizeof guest};
            int status=open?open(&host,&guest):-1;pass=pass && status==0;
            if(!status) {
                MPEvent event={sizeof event,MP_INCREMENT,0};MPState state;
                pass=pass && guest.event(guest.context,&event,&state)==0 && state.counter==1 && state.sequence==1 && observation.callbacks==2;
                event.type=999;pass=pass && guest.event(guest.context,&event,&state)==-22 && observation.callbacks==2;
                guest.destroy(guest.context);
            }
            mp_image_close(im);
            if(i==1) {
                MPImage *bad=mp_image_open_embedded(path.fileSystemRepresentation,"__TEXT",bytes,size-1,(MPServices){0},error);
                report[@"wrong_size_rejected"]=@(!bad);report[@"wrong_size_diagnostic"]=[NSString stringWithUTF8String:error];if(bad)mp_image_close(bad);
                bad=mp_image_open_embedded(path.fileSystemRepresentation,"__TEXT",(char *)bytes+1,size,(MPServices){0},error);
                report[@"misaligned_rejected"]=@(!bad);report[@"misaligned_diagnostic"]=[NSString stringWithUTF8String:error];if(bad)mp_image_close(bad);
            }
        } else [errors addObject:[NSString stringWithUTF8String:error]];
        if(handle)dlclose(handle);
        pass=pass && mp_live_images()==0;all=all && pass;if(i)[cycles addObject:@(pass)];
    }
    report[@"container_kept_resident"]=@(keepContainer);
    report[@"cycles"]=cycles;report[@"passed"]=@(all);report[@"errors"]=errors;
    report[@"fd_scan_limit"]=@256;report[@"fd_before"]=@(beforeFD);report[@"fd_after"]=@(descriptors());
    report[@"regions_before"]=@(beforeRegions);report[@"regions_after"]=@(regions());report[@"live_images_after"]=@(mp_live_images());
    if(held)dlclose(held);
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *truncated=[documents stringByAppendingPathComponent:@"malformed-guest"];
    [@"bad" writeToFile:truncated atomically:YES encoding:NSUTF8StringEncoding error:NULL];char error[256];
    MPImage *bad=mp_image_open(truncated.fileSystemRepresentation,(MPServices){0},error);
    report[@"truncated_rejected"]=@(!bad);report[@"truncated_diagnostic"]=[NSString stringWithUTF8String:error];if(bad)mp_image_close(bad);
    [NSFileManager.defaultManager removeItemAtPath:truncated error:NULL];
    errno=0;int fd=open("/private/var/mobile/ipas/machprobe-sandbox-sentinel.txt",O_RDONLY);int code=errno;
    report[@"outside_container_read_rc"]=@(fd>=0?0:-1);report[@"outside_container_errno"]=@(code);if(fd>=0)close(fd);
    NSMutableArray *injected=[NSMutableArray array];
    for(uint32_t i=0;i<_dyld_image_count();i++) {
        NSString *name=[NSString stringWithUTF8String:_dyld_get_image_name(i)];
        if([name containsString:@"vphone"] || [name containsString:@"camfix"])[injected addObject:name];
    }
    report[@"vm_specific_images"]=injected;return report;
}

NSDictionary *mp_runtime_audit(NSDictionary *manifest) {
    NSMutableDictionary *result=[audit_cycles(manifest,NO) mutableCopy];
    result[@"resident_container_control"]=audit_cycles(manifest,YES);
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:manifest[@"interactive"][@"container"]];
    unsigned before=regions();BOOL pass=YES;
    for(unsigned i=0;i<20;i++) {
        void *handle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
        if(handle)dlclose(handle);else pass=NO;
    }
    result[@"dyld_only_control"]=@{@"cycles":@20,@"passed":@(pass),@"regions_before":@(before),@"regions_after":@(regions())};
    return result;
}
