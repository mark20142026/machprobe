#import "UIKitHost.h"
#include "runtime.h"
#include "guest_abi.h"
#include "checks.h"
#include <string.h>

@interface GuestView : UIViewController {
    MPImage *_image;
    MPGuest _guest;
}
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *stateLabel;
@property(nonatomic,strong) UILabel *checkLabel;
@property(nonatomic,strong) UIView *guestWindow;
@property(nonatomic,strong) UIButton *incrementButton;
@property(nonatomic,strong) UIButton *decrementButton;
@property(nonatomic,strong) UIButton *resetButton;
- (void)start;
@end
static UILabel *label(NSString *text) {
 UILabel *v=[[UILabel alloc] initWithFrame:CGRectMake(0,0,100,40)];v.text=text;v.numberOfLines=0;
 v.font=[UIFont systemFontOfSize:20];v.textColor=[UIColor whiteColor];return v;
}
static void state_changed(void *context,MPState state,const char *message) {
 (void)state;GuestView *view=(__bridge GuestView *)context;
 // UI presents the guest's callback. It contains no counter arithmetic.
 view.stateLabel.text=[NSString stringWithUTF8String:message];
}
static void output(void *context,const char *bytes,size_t n) {
 NSMutableString *text=(__bridge NSMutableString *)context;
 NSString *chunk=[[NSString alloc] initWithBytes:bytes length:n encoding:NSUTF8StringEncoding];if(chunk)[text appendString:chunk];
}
@implementation GuestView
- (void)sendEvent:(uint32_t)type {
 if(!_guest.event)return;MPEvent event={sizeof event,type,0};MPState state;
 int result=_guest.event(_guest.context,&event,&state);
 if(result)self.stateLabel.text=[NSString stringWithFormat:@"Guest error: %d",result];
}
- (void)increment { [self sendEvent:MP_INCREMENT]; }
- (void)decrement { [self sendEvent:MP_DECREMENT]; }
- (void)reset { [self sendEvent:MP_RESET]; }
- (UIButton *)button:(NSString *)title action:(SEL)action {
 UIButton *b=[UIButton buttonWithType:1];[b setTitle:title forState:0];
 [b addTarget:self action:action forControlEvents:1<<6];[self.guestWindow addSubview:b];return b;
}
- (void)start {
 self.view.backgroundColor=[UIColor lightGrayColor];
 self.titleLabel=label(@"UIKit host — macOS guest");self.titleLabel.textColor=[UIColor blackColor];[self.view addSubview:self.titleLabel];
 self.guestWindow=[[UIView alloc] initWithFrame:CGRectMake(0,0,100,100)];self.guestWindow.backgroundColor=[UIColor darkGrayColor];[self.view addSubview:self.guestWindow];
 self.stateLabel=label(@"Loading guest…");[self.guestWindow addSubview:self.stateLabel];
 self.checkLabel=label(@"Running framework checks…");self.checkLabel.font=[UIFont systemFontOfSize:15];[self.guestWindow addSubview:self.checkLabel];
 self.incrementButton=[self button:@"Increment" action:@selector(increment)];
 self.decrementButton=[self button:@"Decrement" action:@selector(decrement)];
 self.resetButton=[self button:@"Reset" action:@selector(reset)];
 char error[256];NSString *path=[NSBundle.mainBundle pathForResource:@"interactive" ofType:nil];
 _image=mp_image_open(path.fileSystemRepresentation,(MPServices){0},error);
 if(!_image){self.stateLabel.text=[NSString stringWithUTF8String:error];return;}
 MPOpenGuest open=(MPOpenGuest)mp_image_symbol(_image,"_mp_guest_open");
 MPHost host={sizeof host,MP_ABI_VERSION,(__bridge void *)self,state_changed};_guest.size=sizeof _guest;
 if(!open || open(&host,&_guest)){self.stateLabel.text=@"Guest ABI rejected";return;}
 NSMutableString *summary=[NSMutableString string];
 for(NSString *name in @[@"hello",@"file_io",@"framework",@"foundation",@"metal_info",@"metal_compute"]) {
  NSMutableString *captured=[NSMutableString string];NSString *file=[NSBundle.mainBundle pathForResource:name ofType:nil];
  MPImage *im=mp_image_open(file.fileSystemRepresentation,(MPServices){(__bridge void *)captured,output},error);
  int result=-1;
  if(im){char *args[]={(char *)file.fileSystemRepresentation,(char *)NSTemporaryDirectory().fileSystemRepresentation,NULL};mp_image_main(im,[name isEqualToString:@"file_io"]?2:1,args,&result);mp_image_close(im);}
  BOOL passed=im && result==0;
  if([name isEqualToString:@"hello"])passed=passed && [captured isEqualToString:@"Hello from macOS ARM64\n"];
  if([name isEqualToString:@"file_io"])passed=passed && [captured isEqualToString:@"File I/O round trip OK\n"];
  if([name isEqualToString:@"framework"])passed=passed && [captured isEqualToString:@"CoreFoundation string length: 11\n"];
  if([name isEqualToString:@"foundation"])passed=passed && [captured isEqualToString:@"FOUNDATION_RESULT weak=cleared class=NSString selector=length length=17 count=2 value=phase2-foundation|PHASE2-FOUNDATION\n"];
  if([name isEqualToString:@"metal_info"])passed=passed && [captured hasPrefix:@"Metal device: "] && [captured containsString:@"Registry ID: "] && [captured containsString:@"Unified memory: "];
  if([name isEqualToString:@"metal_compute"])passed=passed && mp_check_compute_output(captured.UTF8String);
  if([name isEqualToString:@"metal_info"] && passed)[summary appendString:captured];
  else if([name isEqualToString:@"metal_compute"] && passed)[summary appendString:@"Metal compute: 16 verified values, checksum 472\n"];
  else [summary appendFormat:@"%@: %@\n",name,passed?@"passed":(im?@"guest failed":[NSString stringWithUTF8String:error])];
 }
 self.checkLabel.text=summary;
}
- (void)viewDidLayoutSubviews {
 [super viewDidLayoutSubviews];CGSize s=self.view.bounds.size;
 CGFloat w=MAX(260,MIN(s.width-40,700));
 self.titleLabel.frame=CGRectMake(20,48,s.width-40,40);
 self.guestWindow.frame=CGRectMake((s.width-w)/2,110,w,430);
 self.stateLabel.frame=CGRectMake(20,20,w-40,60);
 CGFloat bw=(w-40)/3;
 self.incrementButton.frame=CGRectMake(20,90,bw,48);
 self.decrementButton.frame=CGRectMake(20+bw,90,bw,48);
 self.resetButton.frame=CGRectMake(20+2*bw,90,bw,48);
 self.checkLabel.frame=CGRectMake(20,155,w-40,260);
}
- (void)dealloc {if(_guest.destroy)_guest.destroy(_guest.context);mp_image_close(_image);}
@end
@interface AppDelegate : NSObject
@property(nonatomic,strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(id)application didFinishLaunchingWithOptions:(id)options {
 (void)application;(void)options;self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
 GuestView *v=[GuestView new];self.window.rootViewController=v;[v start];[self.window makeKeyAndVisible];return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}
