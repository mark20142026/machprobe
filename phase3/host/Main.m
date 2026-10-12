#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#include "runtime.h"
#include "guest_abi.h"
#include "checks.h"
#include "signature_probe.h"
#import "AppKitBridge.h"
#import "MetalGuestView.h"
#import "Audit.h"
#include <unistd.h>
#include <mach-o/getsect.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>

static NSString *hashData(NSData *data) {
 unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
 NSMutableString *s=[NSMutableString string]; for(unsigned i=0;i<sizeof digest;i++)[s appendFormat:@"%02x",digest[i]]; return s;
}
static NSString *documents(void) {return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;}
static void capture(void *context,const char *bytes,size_t size) {
 NSMutableString *s=(__bridge NSMutableString *)context;
 NSString *text=[[NSString alloc] initWithBytes:bytes length:size encoding:NSUTF8StringEncoding];if(text)[s appendString:text];
}
@interface ProbeView : UIViewController {
 MPImage *_image,*_guiImage; MPGuest _guest;
 int (*_guiCounter)(void);void (*_guiDestroy)(void);
}
@property(nonatomic,strong) UILabel *stateLabel;
@property(nonatomic,strong) UITextView *results;
@property(nonatomic,strong) NSMutableDictionary *report;
@property(nonatomic,strong) NSDictionary *manifest;
@property(nonatomic,strong) NSMutableArray<NSValue *> *containers;
@property(nonatomic,strong) NSMutableString *interactiveOutput;
@property(nonatomic,strong) MetalGuestView *guestView;
@property(nonatomic,strong) NSMutableString *guiOutput;
- (void)save;
@end
static void changed(void *context,MPState state,const char *message) {
 ProbeView *view=(__bridge ProbeView *)context;view.stateLabel.text=[NSString stringWithUTF8String:message];
 view.report[@"interactive_state"]=@{@"counter":@(state.counter),@"sequence":@(state.sequence),@"message":view.stateLabel.text};[view save];
}
@implementation ProbeView
- (void)save {
 NSData *data=[NSJSONSerialization dataWithJSONObject:self.report options:NSJSONWritingPrettyPrinted error:NULL];
 [data writeToFile:[documents() stringByAppendingPathComponent:@"probe.json"] atomically:YES];
}
- (NSString *)guest:(NSString *)name error:(NSString **)error {
 // Installer signing must never touch a guest executable. Base64 resources are
 // decoded inside the ordinary app container and checked against build hashes.
 NSData *encoded=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:name ofType:@"b64"]];
 NSData *data=[[NSData alloc] initWithBase64EncodedData:encoded options:0];
 NSString *expected=self.manifest[name][@"sha256"];
 if(!data || ![hashData(data) isEqualToString:expected]){*error=@"Guest resource hash mismatch";return nil;}
 NSString *directory=[documents() stringByAppendingPathComponent:@"guests"];
 if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]){*error=@"Guest directory creation failed";return nil;}
 NSString *path=[directory stringByAppendingPathComponent:name];
 if(![data writeToFile:path atomically:YES]){*error=@"Guest write failed";return nil;}
 if(![hashData([NSData dataWithContentsOfFile:path]) isEqualToString:expected]){*error=@"Extracted guest hash mismatch";return nil;}
 return path;
}
- (void)viewDidLoad {
 [super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;
 mp_set_appkit_resolver(mp_appkit_resolve);
 self.containers=[NSMutableArray array];
 UIStackView *stack=[[UIStackView alloc] init];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16]]];
 UILabel *title=[UILabel new];title.text=@"UIKit host / macOS guest";[stack addArrangedSubview:title];
 self.guestView=[[MetalGuestView alloc] initWithFrame:CGRectZero];[self.guestView.heightAnchor constraintEqualToConstant:260].active=YES;[stack addArrangedSubview:self.guestView];
 __weak ProbeView *weakSelf=self;
 mp_gui_set_invalidation(^{[weakSelf.guestView renderGuest];});
 self.guestView.inputObserved=^{ProbeView *v=weakSelf;if(v && v->_guiCounter){v.report[@"gui_counter"]=@(v->_guiCounter());if(!v.report[@"gui_touch_states"])v.report[@"gui_touch_states"]=[NSMutableArray array];[v.report[@"gui_touch_states"] addObject:@(v->_guiCounter())];[v save];}};
 self.stateLabel=[UILabel new];self.stateLabel.numberOfLines=0;self.stateLabel.text=@"Loading…";self.stateLabel.accessibilityIdentifier=@"guest-state";[stack addArrangedSubview:self.stateLabel];
 UIStackView *buttons=[UIStackView new];buttons.distribution=UIStackViewDistributionFillEqually;
 for(NSString *name in @[@"Increment",@"Decrement",@"Reset"]) {
 UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:name forState:UIControlStateNormal];b.tag=[@[@"Increment",@"Decrement",@"Reset"] indexOfObject:name]+1;
 [b addTarget:self action:@selector(input:) forControlEvents:UIControlEventTouchUpInside];[buttons addArrangedSubview:b];
 }[stack addArrangedSubview:buttons];
 self.results=[UITextView new];self.results.editable=NO;self.results.font=[UIFont systemFontOfSize:13];[stack addArrangedSubview:self.results];
 self.report=[@{@"environment":@"iOS VM; installation may add entitlements",@"pid":@(getpid()),@"run_id":NSUUID.UUID.UUIDString,@"ios":UIDevice.currentDevice.systemVersion,@"uid":@(getuid()),@"guests":[NSMutableDictionary dictionary]} mutableCopy];
 NSData *manifest=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"guests" ofType:@"json"]];self.manifest=[NSJSONSerialization JSONObjectWithData:manifest options:0 error:NULL];
 [self performSelector:@selector(run) withObject:nil afterDelay:0.1];
}
- (void)input:(UIButton *)button {
 if(!_guest.event)return; MPEvent event={sizeof event,(uint32_t)button.tag,0};MPState state;
 int result=_guest.event(_guest.context,&event,&state); if(result)self.stateLabel.text=[NSString stringWithFormat:@"Guest error %d",result];
}
- (void)run {
 // Compare the installed host, a byte-identical data-container copy, and an
 // ad-hoc signed iOS rebuild. This isolates admission from guest CPU execution.
 NSMutableDictionary *controls=[NSMutableDictionary dictionary];
 NSString *host=NSBundle.mainBundle.executablePath;
 controls[@"installed_ios_host"]=mp_signature_probe(host);
 NSData *hostBytes=[NSData dataWithContentsOfFile:host];
 NSString *copy=[documents() stringByAppendingPathComponent:@"host-copy"];
 if([hostBytes writeToFile:copy atomically:YES]) {
  controls[@"copied_ios_host"]=mp_signature_probe(copy);
  controls[@"host_copy_hash_matches"]=@([hashData(hostBytes) isEqualToString:hashData([NSData dataWithContentsOfFile:copy])]);
 }
 NSData *encoded=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"hello-ios" ofType:@"b64"]];
 NSData *native=[[NSData alloc] initWithBase64EncodedData:encoded options:0];
 NSString *nativePath=[documents() stringByAppendingPathComponent:@"hello-ios"];
 if([native writeToFile:nativePath atomically:YES])controls[@"recompiled_ios_hello"]=mp_signature_probe(nativePath);
 self.report[@"admission_controls"]=controls;[self save];
 self.report[@"stress"]=mp_runtime_audit(self.manifest);[self save];
 NSMutableString *summary=[NSMutableString string];
 for(NSString *name in @[@"hello",@"interactive",@"file_io",@"framework",@"foundation",@"metal_info",@"metal_compute",@"appkit_gui"]) {
  NSMutableDictionary *record=[NSMutableDictionary dictionary];self.report[@"guests"][name]=record;record[@"stage"]=@"extract";[self save];
  NSString *extractError=nil;NSString *path=[self guest:name error:&extractError];
  if(!path){record[@"error"]=extractError;[summary appendFormat:@"%@: %@\n",name,extractError];[self save];continue;}
  record[@"sha256"]=hashData([NSData dataWithContentsOfFile:path]);record[@"bytes_match_original"]=@YES;record[@"stage"]=@"load";[self save];
  NSMutableString *output=[NSMutableString string];char error[256];
  MPImage *im=mp_image_open(path.fileSystemRepresentation,(MPServices){(__bridge void *)output,capture},error);
  if(!im) {
   record[@"standalone_error"]=[NSString stringWithUTF8String:error];
   NSString *section=self.manifest[name][@"section"];unsigned long length=0;
   NSString *container=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:self.manifest[name][@"container"]];
   record[@"stage"]=@"load signed container";[self save];
   void *handle=dlopen(container.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
   if(handle)[self.containers addObject:[NSValue valueWithPointer:handle]];
   const struct mach_header_64 *header=NULL;
   if(handle)for(uint32_t i=0;i<_dyld_image_count();i++)if(!strcmp(_dyld_get_image_name(i),container.fileSystemRepresentation))header=(const struct mach_header_64 *)_dyld_get_image_header(i);
   const uint8_t *bytes=header?getsectiondata(header,section.UTF8String,"__guest",&length):NULL;
   length=[self.manifest[name][@"size"] unsignedLongValue];
   NSData *embedded=bytes?[NSData dataWithBytes:bytes length:length]:nil;
   record[@"embedded_size"]=@(length);record[@"embedded_sha256"]=embedded?hashData(embedded):@"missing";
   BOOL matches=embedded && [hashData(embedded) isEqualToString:self.manifest[name][@"sha256"]];
   record[@"embedded_bytes_match_original"]=@(matches);record[@"admission_mode"]=@"prepackaged guest inside signed iOS dylib";
   if(matches)im=mp_image_open_embedded(container.fileSystemRepresentation,section.UTF8String,(void *)bytes,length,(MPServices){(__bridge void *)output,capture},error);
   else {const char *failure=handle?"Embedded guest hash mismatch":dlerror();snprintf(error,sizeof error,"%s",failure?:"Container load failed");}
  }
  record[@"loads"]=@(im!=NULL);
  if(!im){NSString *failure=[NSString stringWithUTF8String:error];record[@"error"]=failure;[summary appendFormat:@"%@: %@\n\n",name,failure];if([name isEqualToString:@"interactive"])self.stateLabel.text=failure;[self save];continue;}
  record[@"stage"]=@"execute";[self save];
  if([name isEqualToString:@"interactive"]) {
   _image=im;self.interactiveOutput=output;MPOpenGuest open=(MPOpenGuest)mp_image_symbol(im,"_mp_guest_open");MPHost host={sizeof host,MP_ABI_VERSION,(__bridge void *)self,changed};_guest.size=sizeof _guest;
   int status=open?open(&host,&_guest):-1;record[@"open_status"]=@(status);
   BOOL pass=status==0 && _guest.event;NSMutableArray *states=[NSMutableArray array];
   if(pass) {unsigned types[]={MP_INCREMENT,MP_DECREMENT,MP_DECREMENT,MP_RESET};int expected[]={1,0,-1,0};
    for(unsigned i=0;i<4;i++){MPEvent ev={sizeof ev,types[i],0};MPState state={0};int rc=_guest.event(_guest.context,&ev,&state);[states addObject:@{@"rc":@(rc),@"counter":@(state.counter),@"sequence":@(state.sequence)}];pass=pass && rc==0 && state.counter==expected[i] && state.sequence==i+1;}}
   record[@"input_passed"]=@(pass);record[@"states"]=states;[summary appendFormat:@"interactive input: %@\n",pass?@"passed":@"failed"];
  } else if([name isEqualToString:@"appkit_gui"]) {
   _guiImage=im;self.guiOutput=output;
   _guiCounter=mp_image_symbol(im,"_mp_gui_counter");_guiDestroy=mp_image_symbol(im,"_mp_gui_destroy");
   uintptr_t (*actionAddress)(void)=mp_image_symbol(im,"_mp_gui_action_address");
   if(actionAddress)record[@"guest_action_address"]=@(actionAddress());
   int result=-1;char *argv[]={(char *)path.fileSystemRepresentation,NULL};mp_image_main(im,1,argv,&result);
   record[@"exit"]=@(result);record[@"draw_list"]=mp_gui_draw_list();
   NSMutableArray *states=[NSMutableArray array];BOOL pass=result==0 && _guiCounter && _guiDestroy;
   CGPoint points[]={{275,157},{65,157},{65,157},{170,157},{275,157}};int expected[]={0,1,2,1,0};
   if(pass)for(unsigned i=0;i<5;i++){BOOL hit=mp_gui_touch(points[i]);int value=_guiCounter();[states addObject:@(value)];pass=pass && hit && value==expected[i];}
   record[@"states"]=states;record[@"passed"]=@(pass);record[@"metal_renderer"]=[self.guestView verifyRenderer];
   record[@"passed"]=@(pass && [record[@"metal_renderer"][@"passed"] boolValue]);
   [self.guestView renderGuest];[summary appendFormat:@"AppKit GUI → Metal: %@\n",[record[@"passed"] boolValue]?@"passed":@"failed"];
  } else {
   int result=-1;char *argv[]={(char *)path.fileSystemRepresentation,(char *)NSTemporaryDirectory().fileSystemRepresentation,NULL};mp_image_main(im,[name isEqualToString:@"file_io"]?2:1,argv,&result);
   record[@"exit"]=@(result);record[@"output"]=output;
   BOOL pass=result==0;
   if([name isEqualToString:@"hello"])pass=pass && [output isEqualToString:@"Hello from macOS ARM64\n"];
   if([name isEqualToString:@"file_io"])pass=pass && [output isEqualToString:@"File I/O round trip OK\n"];
   if([name isEqualToString:@"framework"])pass=pass && [output isEqualToString:@"CoreFoundation string length: 11\n"];
   if([name isEqualToString:@"foundation"])pass=pass && [output isEqualToString:@"FOUNDATION_RESULT weak=cleared class=NSString selector=length length=17 count=2 value=phase2-foundation|PHASE2-FOUNDATION\n"];
   if([name isEqualToString:@"metal_info"])pass=pass && [output hasPrefix:@"Metal device: "] && [output containsString:@"Registry ID: "];
   if([name isEqualToString:@"metal_compute"])pass=pass && mp_check_compute_output(output.UTF8String);
   record[@"passed"]=@(pass);[summary appendFormat:@"%@: %@\n%@\n",name,pass?@"passed":@"failed",output];mp_image_close(im);
  }
  record[@"stage"]=@"finished";[self save];
 }
 self.results.text=summary;self.report[@"complete"]=@YES;[self save];
}
- (void)dealloc {mp_gui_set_invalidation(nil);if(_guiDestroy)_guiDestroy();mp_image_close(_guiImage);if(_guest.destroy)_guest.destroy(_guest.context);mp_image_close(_image);for(NSValue *handle in self.containers)dlclose(handle.pointerValue);}
@end
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
 (void)session;(void)options;if(![scene isKindOfClass:UIWindowScene.class])return;
 self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[ProbeView new];[self.window makeKeyAndVisible];
}
@end
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation AppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
 (void)application;(void)options;UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];configuration.delegateClass=SceneDelegate.class;return configuration;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}
