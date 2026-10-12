#import "Lifecycle.h"
#import "GameBridge.h"
#import <objc/message.h>
#import "Menu.h"
#import "Input.h"
#import "Window.h"
static __weak UIView *hostView;
extern __strong id mp_game_nsapp;
// Guests that own their main loop (SDL games) are entered from the run loop
// once the scene exists, as SDL's iOS backend enters SDL_main; they call
// -finishLaunching themselves. Without a hook, the AppKit run path is used.
static void (^launchHook)(void);
void mp_game_set_launch_hook(void (^hook)(void)){launchHook=hook;}
int mp_game_run_uikit(void){
    char *arguments[]={"GameHost",NULL};
    return UIApplicationMain(1,arguments,nil,@"MPGameHostDelegate");
}
static __weak MPInputController *inputController;
extern void mp_game_sample(void);
UIView *mp_game_host_view(void){return hostView;}
@implementation MPGameRunningApplication
+ (instancetype)currentApplication {static id app;static dispatch_once_t once;dispatch_once(&once,^{app=[self new];});return app;}
- (NSString *)bundleIdentifier {return NSBundle.mainBundle.bundleIdentifier;}
- (BOOL)activateWithOptions:(NSUInteger)options {
    // Activation is limited to our own UIKit scene; no other process is raised.
    UIWindow *window=hostView.window;[window makeKeyAndVisible];return window.isKeyWindow;
}
@end
@interface MPGameScene : UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation MPGameScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window=[[MPPhysicalWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    MPInputController *controller=[MPInputController new];inputController=controller;
    controller.view.backgroundColor=UIColor.blackColor;
    self.window.rootViewController=controller;
    [self.window makeKeyAndVisible];
    arena_attach_surface(controller.view);
    hostView=controller.view;
    [mp_game_key_window() makeKeyAndOrderFront:nil];
    UIApplication.sharedApplication.idleTimerDisabled=YES;
    // Enter from a run-loop timer, not a main-queue block: the main dispatch
    // queue is serial, so a guest loop running inside a main-queue block
    // would starve every later dispatch_async(main) (SDL waits on those).
    // SDL's own iOS backend enters SDL_main the same way.
    if(launchHook){void (^hook)(void)=launchHook;launchHook=nil;[NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *t){hook();}];return;}
    // AppKit's launch callback follows host scene creation so a guest window
    // can immediately attach its own content to the physical presentation view.
    [[MPGameApplication sharedApplication] finishLaunching];
}
@end
@interface MPGameHostDelegate : UIResponder<UIApplicationDelegate>@end
@implementation MPGameHostDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"Guest" sessionRole:session.role];
    configuration.delegateClass=MPGameScene.class;return configuration;
}
@end
@implementation MPGameApplication
- (NSArray *)windows {return mp_game_windows();}
+ (instancetype)sharedApplication {
    // The first receiver's class wins, as in AppKit (e.g. SDLApplication).
    static MPGameApplication *app;static dispatch_once_t once;
    dispatch_once(&once,^{app=[self new];mp_game_nsapp=app;});return app;
}
// AppKit event pump for guests that own their main loop (SDL's
// Cocoa_PumpEvents). Input adapters deliver events synchronously through
// -sendEvent: while the run loop spins, so the queue handed back is empty.
__attribute__((weak)) void mp_watchdog_beat(void){} // phase6 Watchdog.m overrides.
BOOL mp_game_queue_events;
static NSMutableArray *queued;
void mp_game_post(id event) {
    if(!mp_game_queue_events){[[MPGameApplication sharedApplication] sendEvent:event];return;}
    if(!queued)queued=[NSMutableArray new];
    // Mouse coalescing, as AppKit does: a move/drag/scroll directly after one of
    // the same type merges into it (latest position, summed deltas), so a 120 Hz
    // touch stream never queues up behind a 30 fps game loop.
    NSUInteger type=((NSUInteger(*)(id,SEL))objc_msgSend)(event,@selector(type));
    id previous=queued.lastObject;
    if(previous && (type==5||type==6||type==7||type==22) && ((NSUInteger(*)(id,SEL))objc_msgSend)(previous,@selector(type))==type) {
        MPKeyEvent *a=previous,*b=event;
        a.locationInWindow=b.locationInWindow;a.deltaX+=b.deltaX;a.deltaY+=b.deltaY;a.timestamp=b.timestamp;a.modifierFlags=b.modifierFlags;
        return;
    }
    if(queued.count<512)[queued addObject:event];
    CFRunLoopWakeUp(CFRunLoopGetMain());
}
static id take(unsigned long long mask,BOOL dequeue) {
    for(NSUInteger i=0;i<queued.count;i++) {
        id event=queued[i];NSUInteger type=((NSUInteger(*)(id,SEL))objc_msgSend)(event,@selector(type));
        if(type<64 && !(mask&(1ULL<<type)))continue;
        if(dequeue)[queued removeObjectAtIndex:i];
        return event;
    }
    return nil;
}
- (id)nextEventMatchingMask:(unsigned long long)mask untilDate:(NSDate *)date inMode:(NSString *)mode dequeue:(BOOL)dequeue {
    mp_watchdog_beat();
    id event=take(mask,dequeue);if(event)return event;
    NSTimeInterval wait=date?MAX(0,date.timeIntervalSinceNow):0;
    // Polling (no wait): service every ready source once, so all pending
    // touches reach the queue this frame rather than one per call.
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,wait,wait>0 || !mp_game_queue_events);
    return take(mask,dequeue);
}
- (void)discardEventsMatchingMask:(unsigned long long)mask beforeEvent:(id)last {
    for(NSInteger i=(NSInteger)queued.count-1;i>=0;i--){NSUInteger type=((NSUInteger(*)(id,SEL))objc_msgSend)(queued[i],@selector(type));if(type>=64 || (mask&(1ULL<<type)))[queued removeObjectAtIndex:i];}
}
- (void)postEvent:(id)event atStart:(BOOL)start {if(!queued)queued=[NSMutableArray new];if(start)[queued insertObject:event atIndex:0];else [queued addObject:event];}
- (void)updateWindows {}
- (BOOL)isRunning {return mp_game_host_view()!=nil;}
- (BOOL)setActivationPolicy:(NSInteger)policy {return policy>=0 && policy<=2;}
- (void)activateIgnoringOtherApps:(BOOL)value {mp_game_trace(@"application activation requested");}
- (void)sendEvent:(id)event {
    id previous=self.currentEvent;self.currentEvent=event;
    @try {mp_game_dispatch_event(event);} @finally {self.currentEvent=previous;}
}
- (void)run {
    // A guest entered from the run loop (launch hook) that then calls -run:
    // UIKit is already running, so keep servicing its run loop, as AppKit's
    // -run never returns.
    if(mp_game_host_view()){mp_game_trace(@"guest -run inside UIKit: servicing run loop");for(;;)CFRunLoopRunInMode(kCFRunLoopDefaultMode,1e10,false);}
    mp_game_trace(@"entering UIKit lifecycle");
    char *arguments[]={"GameHost",NULL};UIApplicationMain(1,arguments,nil,NSStringFromClass(MPGameHostDelegate.class));
}
- (void)finishLaunching {
    static BOOL launched;if(launched)return;launched=YES;
    for(NSString *name in @[@"NSApplicationWillFinishLaunchingNotification",@"NSApplicationDidFinishLaunchingNotification"]) {
        SEL selector=NSSelectorFromString([name containsString:@"Will"]?@"applicationWillFinishLaunching:":@"applicationDidFinishLaunching:");
        NSNotification *notification=[NSNotification notificationWithName:name object:self];
        if([self.delegate respondsToSelector:selector]) {
            mp_game_trace(NSStringFromSelector(selector));
            ((void(*)(id,SEL,id))objc_msgSend)(self.delegate,selector,notification);
        }
        [NSNotificationCenter.defaultCenter postNotification:notification];
    }
    mp_game_trace(@"guest launch callback returned");
    [inputController installControls];
    [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){mp_game_sample();}];
    if(self.mainMenu){
        UIButton *menu=[UIButton buttonWithType:UIButtonTypeSystem];[menu setTitle:@"Menu" forState:UIControlStateNormal];
        menu.menu=[self.mainMenu hostMenu];menu.showsMenuAsPrimaryAction=YES;
        menu.frame=CGRectMake(8,hostView.safeAreaInsets.top+8,60,36);menu.backgroundColor=UIColor.secondarySystemBackgroundColor;
        [hostView addSubview:menu];
    }
}
@end
