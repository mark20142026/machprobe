#import "GameBridge.h"
#import <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <string.h>
static __weak UIView *parent;
static __weak MTKView *surface;
static id (^eventMonitor)(id);
static uint64_t inputCalls,windowCalls;static double inputSeconds;
@interface ArenaEvent:NSObject
@property NSUInteger type;
@property(copy) NSString *charactersIgnoringModifiers;
@property double deltaX,deltaY;
@property BOOL isARepeat;
+ (id)addLocalMonitorForEventsMatchingMask:(unsigned long long)mask handler:(id(^)(id))handler;
+ (void)removeMonitor:(id)token;
@end
@implementation ArenaEvent
+ (id)addLocalMonitorForEventsMatchingMask:(unsigned long long)mask handler:(id(^)(id))handler {
    (void)mask;eventMonitor=[handler copy];return eventMonitor;
}
+ (void)removeMonitor:(id)token {if(token==eventMonitor)eventMonitor=nil;}
@end
static void deliver(ArenaEvent *e){double begin=CACurrentMediaTime();if(eventMonitor)eventMonitor(e);inputCalls++;inputSeconds+=CACurrentMediaTime()-begin;}
void arena_key(NSString *s,BOOL down){ArenaEvent *e=[ArenaEvent new];e.type=down?10:11;e.charactersIgnoringModifiers=s;deliver(e);}
void arena_drag(CGPoint p){ArenaEvent *e=[ArenaEvent new];e.type=6;e.deltaX=p.x;e.deltaY=p.y;deliver(e);}
void arena_clear_input(void){for(NSString *s in @[@"w",@"a",@"s",@"d",@"j",@"l",@" "])arena_key(s,NO);}
void arena_attach_surface(UIView *p){parent=p;}
MTKView *arena_surface(void){return surface;}
NSDictionary *arena_bridge_stats(void){return @{@"input_calls":@(inputCalls),@"input_seconds_including_guest":@(inputSeconds),@"window_calls":@(windowCalls),@"monitor_alive":@(eventMonitor!=nil),@"surface_alive":@(surface!=nil),@"render_translation_calls_per_frame":@0,@"pixel_copies_per_frame":@0};}
@interface ArenaWindow:NSObject
@property(nonatomic,strong) MTKView *contentView;
@property(copy) NSString *title;
- (id)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)mask backing:(NSUInteger)backing defer:(BOOL)defer;
- (void)setReleasedWhenClosed:(BOOL)value;
- (void)center;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)close;
@end
@implementation ArenaWindow
- (id)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)mask backing:(NSUInteger)backing defer:(BOOL)defer {(void)rect;(void)mask;(void)backing;(void)defer;windowCalls++;return [super init];}
- (void)setReleasedWhenClosed:(BOOL)value {(void)value;}
- (void)center {}
- (void)makeKeyAndOrderFront:(id)sender {
    (void)sender;surface=self.contentView;surface.frame=parent.bounds;
    surface.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    // Logical display scaling is a host presentation policy, not a guest renderer.
    surface.contentScaleFactor=1;[parent addSubview:surface];windowCalls++;
}
- (void)close {[self.contentView removeFromSuperview];self.contentView=nil;surface=nil;windowCalls++;}
@end
@interface ArenaApplication:NSObject
+ (instancetype)sharedApplication;
- (BOOL)setActivationPolicy:(NSInteger)policy;
- (void)activateIgnoringOtherApps:(BOOL)value;
- (void)run;
@end
@implementation ArenaApplication
+ (instancetype)sharedApplication {static ArenaApplication *app;static dispatch_once_t once;dispatch_once(&once,^{app=[self new];});return app;}
- (BOOL)setActivationPolicy:(NSInteger)policy {(void)policy;return YES;}
- (void)activateIgnoringOtherApps:(BOOL)value {(void)value;}
// UIKit owns the physical application loop; MTKView schedules guest draw callbacks.
- (void)run {}
@end
@interface ArenaSound:NSObject
+ (void)beep;
@end
@implementation ArenaSound
+ (void)beep {AudioServicesPlaySystemSound(1104);}
@end
static void beep(void){AudioServicesPlaySystemSound(1104);}
static int allowed(const char *name) {
    return !strcmp(name,"/System/Library/Frameworks/MetalKit.framework/Versions/A/MetalKit") || !strcmp(name,"/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore");
}
static void *resolve(const char *library,const char *name){
    if(strstr(library,"/AppKit.framework/")){
        if(!strcmp(name,"_NSBeep"))return (void *)&beep;
        if(!strcmp(name,"_OBJC_CLASS_$_NSApplication"))return (__bridge void *)ArenaApplication.class;
        if(!strcmp(name,"_OBJC_CLASS_$_NSWindow"))return (__bridge void *)ArenaWindow.class;
        if(!strcmp(name,"_OBJC_CLASS_$_NSEvent"))return (__bridge void *)ArenaEvent.class;
        if(!strcmp(name,"_OBJC_CLASS_$_NSSound"))return (__bridge void *)ArenaSound.class;
        return NULL;
    }
    if(name[0]!='_')return NULL;
    char path[256];snprintf(path,sizeof path,"%s",library);const char *v=strstr(library,".framework/Versions/");
    if(v)snprintf(path,sizeof path,"%.*s/%s",(int)(v-library+10),library,strrchr(library,'/')+1);
    // Only load-time resolution: no proxy/forwarder on Metal's per-frame calls.
    void *h=dlopen(path,RTLD_NOW|RTLD_LOCAL);if(!h)return NULL;void *result=dlsym(h,name+1);dlclose(h);return result;
}
const MPExtensions *arena_policy(void){static MPExtensions p={0,0,allowed,resolve};return &p;}
