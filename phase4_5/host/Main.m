#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import "GameBridge.h"
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach/mach.h>
#include <sys/resource.h>
#include <dlfcn.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
static NSString *sha(const void *p,size_t size){unsigned char d[32];CC_SHA256(p,(CC_LONG)size,d);NSMutableString *s=[NSMutableString new];for(int i=0;i<32;i++)[s appendFormat:@"%02x",d[i]];return s;}
static NSString *documents(void){return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;}
static NSDictionary *memory(void){struct task_vm_info info;mach_msg_type_number_t n=TASK_VM_INFO_COUNT;task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&n);struct rusage r;getrusage(RUSAGE_SELF,&r);return @{@"footprint":@(info.phys_footprint),@"resident":@(info.resident_size),@"process_cpu_seconds":@(r.ru_utime.tv_sec+r.ru_utime.tv_usec*1e-6+r.ru_stime.tv_sec+r.ru_stime.tv_usec*1e-6)};}
// Guest dictionaries contain guest-backed constant strings. Copy through JSON
// inside a drained pool before retaining diagnostics across an image unload.
static NSDictionary *snapshotCopy(NSDictionary *(*function)(void)) {
    if(!function)return @{};
    @autoreleasepool {NSData *bytes=[NSJSONSerialization dataWithJSONObject:function() options:0 error:NULL];return [NSJSONSerialization JSONObjectWithData:bytes options:0 error:NULL]?:@{};}
}
@interface ArenaController:UIViewController {
    MPImage *_image;void *_handle;NSDictionary *(*_snapshot)(void);NSDictionary *(*_verify)(void);void (*_stop)(void);
}
@property(strong) UIView *display;
@property(strong) UILabel *status;
@property(strong) NSTimer *timer;
@property(strong) NSMutableDictionary *report;
@property(strong) NSMutableArray *history;
@property(strong) NSMutableArray *cycles;
@property(strong) NSDictionary *manifest;
@property double previousTime,previousFrames;
@end
@implementation ArenaController
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;UIApplication.sharedApplication.idleTimerDisabled=YES;
    self.report=[@{@"run_id":NSUUID.UUID.UUIDString,@"pid":@(getpid()),@"uid":@(getuid()),@"ios":UIDevice.currentDevice.systemVersion,@"admission":@"signed iOS container; VM trust independence unverified"} mutableCopy];self.history=[NSMutableArray new];self.cycles=[NSMutableArray new];
    self.manifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"guest" ofType:@"json"]] options:0 error:NULL];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=4;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];
    self.status=[UILabel new];self.status.textColor=UIColor.whiteColor;self.status.numberOfLines=2;self.status.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];self.status.text=@"Loading macOS guest";[stack addArrangedSubview:self.status];
    self.display=[UIView new];[stack addArrangedSubview:self.display];[self.display.heightAnchor constraintGreaterThanOrEqualToConstant:250].active=YES;arena_attach_surface(self.display);
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];[self.display addGestureRecognizer:pan];
    NSArray *rows=@[@[@"A",@"W",@"S",@"D"],@[@"J",@"L",@"Space",@"Reset"],@[@"Verify",@"Reload"]];
    for(NSArray *row in rows){UIStackView *buttons=[UIStackView new];buttons.distribution=UIStackViewDistributionFillEqually;[buttons.heightAnchor constraintEqualToConstant:44].active=YES;[stack addArrangedSubview:buttons];for(NSString *name in row){UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:name forState:UIControlStateNormal];b.accessibilityIdentifier=[@"arena-" stringByAppendingString:name];[b addTarget:self action:@selector(down:) forControlEvents:UIControlEventTouchDown];[b addTarget:self action:@selector(up:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];[buttons addArrangedSubview:b];}}
    [self.view layoutIfNeeded];[self load];self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)background {arena_clear_input();arena_surface().paused=YES;}
- (void)foreground {arena_surface().paused=NO;}
- (NSString *)key:(NSString *)name {if([name isEqual:@"Space"])return @" ";if([name isEqual:@"Reset"])return @"r";return name.lowercaseString;}
- (void)down:(UIButton *)b {NSString *s=b.currentTitle;if(![s isEqual:@"Verify"] && ![s isEqual:@"Reload"])arena_key([self key:s],YES);}
- (void)up:(UIButton *)b {NSString *s=b.currentTitle;if([s isEqual:@"Verify"]){if(_verify)self.report[@"verification"]=snapshotCopy(_verify);}else if([s isEqual:@"Reload"]){[self unload];[self load];}else arena_key([self key:s],NO);[self tick];}
- (void)pan:(UIPanGestureRecognizer *)g {CGPoint p=[g translationInView:self.display];arena_drag(p);[g setTranslation:CGPointZero inView:self.display];}
- (void)save {
    self.report[@"samples"]=self.history;self.report[@"cycles"]=self.cycles;
    [[NSJSONSerialization dataWithJSONObject:self.report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[documents() stringByAppendingPathComponent:@"arena.json"] atomically:YES];
}
- (void)load {
    NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"ArenaGuest.dylib"];_handle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
    const struct mach_header_64 *header=NULL;for(unsigned i=0;_handle && i<_dyld_image_count();i++)if(!strcmp(_dyld_get_image_name(i),path.fileSystemRepresentation))header=(const struct mach_header_64 *)_dyld_get_image_header(i);
    unsigned long sectionSize=0;void *bytes=header?getsectiondata(header,"__TEXT","__guest",&sectionSize):NULL;size_t size=[self.manifest[@"size"] unsignedLongValue];char error[256]={0};
    if(bytes){self.report[@"guest_sha256"]=sha(bytes,size);if(![self.report[@"guest_sha256"] isEqual:self.manifest[@"sha256"]])bytes=NULL;}
    if(bytes)_image=mp_image_open_embedded(path.fileSystemRepresentation,"__TEXT",bytes,size,(MPServices){.extensions=arena_policy()},error);
    if(!_image){self.report[@"error"]=@(error[0]?error:"container/hash failure");[self save];return;}
    _snapshot=mp_image_symbol(_image,"_game_snapshot");_verify=mp_image_symbol(_image,"_game_verify");_stop=mp_image_symbol(_image,"_game_stop");
    int result=-1;mp_image_main(_image,0,NULL,&result);self.report[@"guest_exit"]=@(result);self.report[@"live_images"]=@(mp_live_images());
    if(!result && _verify)self.report[@"verification"]=snapshotCopy(_verify);
    self.previousFrames=0;self.previousTime=CACurrentMediaTime();[self tick];
}
- (void)unload {
    if(!_image)return;arena_clear_input();NSMutableDictionary *cycle=[NSMutableDictionary new];cycle[@"before"]=snapshotCopy(_snapshot);
    if(_stop)_stop();cycle[@"after_stop"]=snapshotCopy(_snapshot);_snapshot=NULL;_stop=NULL;_verify=NULL;mp_image_close(_image);_image=NULL;
    if(_handle)dlclose(_handle);_handle=NULL;cycle[@"live_images_after"]=@(mp_live_images());cycle[@"bridge_after"]=arena_bridge_stats();cycle[@"memory_after"]=memory();[self.cycles addObject:cycle];
}
- (void)tick {
    if(_snapshot){NSDictionary *s=snapshotCopy(_snapshot);self.report[@"guest"]=s;double now=CACurrentMediaTime(),f=[s[@"frames"] doubleValue],dt=now-self.previousTime;double fps=dt>.01?(f-self.previousFrames)/dt:0;self.previousTime=now;self.previousFrames=f;
        NSDictionary *sample=@{@"time":@(now),@"fps_interval":@(fps),@"guest":s,@"memory":memory()};[self.history addObject:sample];if(self.history.count>360)[self.history removeObjectAtIndex:0];
        self.status.text=[NSString stringWithFormat:@"macOS guest → iOS Metal | %.1f FPS\nframes %@ · GPU errors %@ · drag to look",fps,s[@"frames"],s[@"gpu_errors"]];
    }
    self.report[@"bridge"]=arena_bridge_stats();[self save];
}
@end
@interface ArenaScene:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation ArenaScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {(void)session;(void)options;self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[ArenaController new];[self.window makeKeyAndVisible];}
@end
@interface ArenaApp:UIResponder<UIApplicationDelegate>@end
@implementation ArenaApp
- (UISceneConfiguration *)application:(UIApplication *)a configurationForConnectingSceneSession:(UISceneSession *)s options:(UISceneConnectionOptions *)o {(void)a;(void)o;UISceneConfiguration *c=[[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:s.role];c.delegateClass=ArenaScene.class;return c;}
@end
int main(int argc,char **argv){@autoreleasepool{setenv("MTL_DEBUG_LAYER","1",1);freopen([[documents() stringByAppendingPathComponent:@"metal-validation.log"] fileSystemRepresentation],"w",stderr);return UIApplicationMain(argc,argv,nil,NSStringFromClass(ArenaApp.class));}}
