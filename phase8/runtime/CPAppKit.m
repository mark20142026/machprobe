// AppKit methods Cyberpunk 2077 sends to the Phase 5 stand-ins (NSScreen,
// NSWindow, NSApplication, NSEvent) beyond what SDL games needed. Found by the
// MP_SEL_SURVEY run on the iPhone.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdatomic.h>
#import "Lifecycle.h"
#import "Window.h"
#import "Input.h"
#import "ImageShim.h"
@interface MPGameScreen:NSObject @end
@implementation MPGameScreen (MPCyberpunk)
// SDR on purpose: an EDR headroom above 1 makes the game render and present
// HDR (wider formats, more bandwidth) — costly on a phone. MP_HDR=1 reports
// the panel's real headroom instead.
static CGFloat headroom(BOOL potential) {
    if(!getenv("MP_HDR"))return 1;
    if(@available(iOS 16.0,*))return potential?UIScreen.mainScreen.potentialEDRHeadroom:UIScreen.mainScreen.currentEDRHeadroom;
    return 1;
}
- (CGFloat)maximumExtendedDynamicRangeColorComponentValue {return headroom(NO);}
- (CGFloat)maximumPotentialExtendedDynamicRangeColorComponentValue {return headroom(YES);}
- (CGFloat)maximumReferenceExtendedDynamicRangeColorComponentValue {return headroom(YES);}
- (NSInteger)maximumFramesPerSecond {return UIScreen.mainScreen.maximumFramesPerSecond;}
- (NSTimeInterval)minimumRefreshInterval {return 1.0/UIScreen.mainScreen.maximumFramesPerSecond;}
- (NSTimeInterval)maximumRefreshInterval {return 1.0/24;}
- (NSTimeInterval)displayUpdateGranularity {return 0;}
- (NSString *)localizedName {return UIDevice.currentDevice.model;}
- (id)colorSpace {return nil;}
@end
@implementation MPGameWindow (MPCyberpunk)
- (CGRect)contentLayoutRect {return CGRectMake(0,0,self.frame.size.width,self.frame.size.height);}
- (CGPoint)convertPointFromScreen:(CGPoint)p {return CGPointMake(p.x-self.frame.origin.x,p.y-self.frame.origin.y);}
- (CGPoint)convertPointToScreen:(CGPoint)p {return CGPointMake(p.x+self.frame.origin.x,p.y+self.frame.origin.y);}
- (void)makeMainWindow {}
- (NSUInteger)occlusionState {return 1UL<<1;} // NSWindowOcclusionStateVisible
- (void)performMiniaturize:(id)sender {}
- (void)setContentAspectRatio:(CGSize)ratio {}
- (void)setIsVisible:(BOOL)visible {}
- (void)setFrame:(CGRect)frame display:(BOOL)display animate:(BOOL)animate {[self setFrame:frame display:display];}
- (void)setMinSize:(CGSize)size {}
- (void)setMaxSize:(CGSize)size {}
- (void)setContentMinSize:(CGSize)size {}
@end
@implementation MPGameApplication (MPCyberpunk)
- (id)mainWindow {extern MPGameWindow *mp_game_key_window(void);return mp_game_key_window();}
- (id)keyWindow {extern MPGameWindow *mp_game_key_window(void);return mp_game_key_window();}
- (NSUInteger)occlusionState {return 1UL<<1;} // NSApplicationOcclusionStateVisible
- (void)hide:(id)sender {}
- (void)hideOtherApplications:(id)sender {}
- (void)terminate:(id)sender {exit(0);}
- (NSUInteger)presentationOptions {return 0;}
- (void)setPresentationOptions:(NSUInteger)options {}
- (NSUInteger)currentSystemPresentationOptions {return 0;}
@end
@implementation MPKeyEvent (MPCyberpunk)
- (BOOL)hasPreciseScrollingDeltas {return NO;} // Touch scrolling is delivered as wheel lines.
- (CGFloat)scrollingDeltaX {return self.deltaX;}
- (CGFloat)scrollingDeltaY {return self.deltaY;}
+ (void)setMouseCoalescingEnabled:(BOOL)enabled {}
+ (BOOL)isMouseCoalescingEnabled {return YES;}
@end
@implementation MPCompatImage (MPCyberpunk)
- (instancetype)initWithSize:(CGSize)size { // Blank image (the game builds its hidden cursor from one).
    if(!(self=[self init]))return nil;
    if(size.width>0 && size.height>0)self.uiImage=[[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *c){}];
    return self;
}
- (void)lockFocus {}
- (void)drawInRect:(CGRect)rect fromRect:(CGRect)from operation:(NSUInteger)op fraction:(CGFloat)fraction respectFlipped:(BOOL)flipped hints:(id)hints {
    [self.uiImage drawInRect:rect blendMode:kCGBlendModeNormal alpha:fraction];
}
- (void)unlockFocus {}
@end
// NSView layer hosting: AppKit lets a view adopt any layer (the game sets its
// CAMetalLayer); a UIView's backing layer is fixed. The adopted layer becomes
// a full-size sublayer, resized with the view. The game keeps its own pointer
// to the CAMetalLayer and renders through that.
static char hostedKey;
@implementation UIView (MPHostedLayer)
- (void)setLayer:(CALayer *)layer {
    CALayer *old=objc_getAssociatedObject(self,&hostedKey);if(old==layer)return;
    [old removeFromSuperlayer];objc_setAssociatedObject(self,&hostedKey,layer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(!layer)return;
    layer.frame=self.bounds;layer.contentsScale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    [self.layer addSublayer:layer];
}
- (BOOL)wantsLayer {return YES;}
- (void)setWantsLayer:(BOOL)wants {}
- (void)setLayerContentsRedrawPolicy:(NSInteger)policy {}
- (void)setLayerContentsPlacement:(NSInteger)placement {}
@end
static void (*layoutSublayers)(UIView *,SEL,CALayer *);
static void hostedLayout(UIView *self,SEL _cmd,CALayer *layer) {
    layoutSublayers(self,_cmd,layer);
    CALayer *hosted=objc_getAssociatedObject(self,&hostedKey);
    if(hosted && layer==self.layer && !CGRectEqualToRect(hosted.frame,self.bounds)){[CATransaction begin];[CATransaction setDisableActions:YES];hosted.frame=self.bounds;[CATransaction commit];}
}
__attribute__((constructor)) static void install_hosted_layout(void) {
    Method m=class_getInstanceMethod(UIView.class,@selector(layoutSublayersOfLayer:));
    layoutSublayers=(void *)method_getImplementation(m);method_setImplementation(m,(IMP)hostedLayout);
}
// Safety net: a message a stand-in does not implement goes (via
// forwardingTargetForSelector:) to MPZero, which answers every selector with
// zero in x0 and d0-d3 (covers ids, integers, BOOL, CGFloat, CGPoint/Size/Rect)
// and logs it once. respondsToSelector: stays truthful, so the game's own
// feature checks are unaffected. Each log line is a method to implement.
__attribute__((naked)) static void zero(void) {
    __asm__("mov x0, #0\n movi d0, #0\n movi d1, #0\n movi d2, #0\n movi d3, #0\n ret");
}
@interface MPZero:NSObject @end
@implementation MPZero
+ (BOOL)resolveInstanceMethod:(SEL)sel {class_addMethod(self,sel,(IMP)zero,"@@:");return YES;}
+ (instancetype)shared {static MPZero *z;static dispatch_once_t once;dispatch_once(&once,^{z=[self new];});return z;}
@end
// Logged once per (class, selector) through a small lock-free hash, so a
// selector the game sends every frame costs only a few loads here.
static _Atomic uintptr_t seenSlots[1024];
static id forward(id self,SEL _cmd,SEL sel) {
    Class cls=object_getClass(self);uintptr_t key=((uintptr_t)cls*31)^(uintptr_t)sel;if(!key)key=1;
    for(unsigned i=0,h=(unsigned)((key>>4)*2654435761u)&1023;i<1024;i++,h=(h+1)&1023) {
        uintptr_t v=seenSlots[h];
        if(v==key)return MPZero.shared;
        if(!v){uintptr_t expect=0;
            if(atomic_compare_exchange_strong(&seenSlots[h],&expect,key)){fprintf(stderr,"[appkit] unimplemented %c[%s %s] -> 0\n",class_isMetaClass(cls)?'+':'-',class_getName(cls),sel_getName(sel));return MPZero.shared;}
            if(expect==key)return MPZero.shared;}
    }
    return MPZero.shared;
}
__attribute__((constructor)) static void install_safety_net(void) {
    for(NSString *name in @[@"MPGameApplication",@"MPGameWindow",@"MPGameScreen",@"MPKeyEvent",@"MPGameCursor",@"MPWindowController",
                            @"MPWorkspace",@"MPTrackingArea",@"MPColorSpace",@"MPGraphicsContext",@"MPOpenGLContext",@"MPGameMenu",@"MPGameRunningApplication",@"UIView",@"MPCompatImage",@"MPGamePasteboard",@"MPGameMenuItem",@"MPCompatNumberFormatter",@"MPCompatSound",@"MPGameView"]) {
        Class c=NSClassFromString(name);if(!c)continue;
        class_addMethod(c,@selector(forwardingTargetForSelector:),(IMP)forward,"@@::");
        class_addMethod(object_getClass(c),@selector(forwardingTargetForSelector:),(IMP)forward,"@@::");
    }
}

// Focus: Cyberpunk's GameWindowController learns it has focus only from
// windowDidBecomeKey: (sets m_windowFocus, makes GameView first responder, hides
// the system cursor); without it the game ignores the pointer. Our first
// "became key" can precede its observers, so it is re-sent once the window is
// on screen and whenever the app becomes active again, as macOS does on
// activation.
static NSHashTable *controllers;
static id (*origInitWithWindow)(id,SEL,id);
static id trackedInitWithWindow(id self,SEL _cmd,id window){self=origInitWithWindow(self,_cmd,window);if(self)[controllers addObject:self];return self;}
extern MPGameWindow *mp_game_key_window(void);
void mp_cp_refocus(void) {
    MPGameWindow *w=mp_game_key_window();if(!w){fprintf(stderr,"[focus] no guest window yet\n");return;}
    NSNotification *n=[NSNotification notificationWithName:@"NSWindowDidBecomeKeyNotification" object:w];
    // Controllers reachable from the content view tree (GameView.m_windowController).
    NSMutableArray<UIView *> *views=w.contentView?[NSMutableArray arrayWithObject:w.contentView]:[NSMutableArray array];
    while(views.count){UIView *v=views.firstObject;[views removeObjectAtIndex:0];[views addObjectsFromArray:v.subviews];
        SEL get=NSSelectorFromString(@"m_windowController");
        if([v respondsToSelector:get]){id c=((id(*)(id,SEL))objc_msgSend)(v,get);if(c)[controllers addObject:c];}}
    for(id c in controllers.allObjects)
        if([c respondsToSelector:@selector(windowDidBecomeKey:)])
            ((void(*)(id,SEL,id))objc_msgSend)(c,@selector(windowDidBecomeKey:),n);
    [NSNotificationCenter.defaultCenter postNotification:[NSNotification notificationWithName:@"NSApplicationDidBecomeActiveNotification" object:[MPGameApplication sharedApplication]]];
    // The game tracks visibility in a static flag (+[GameWindow isWindowVisible],
    // fed by windowDidChangeOcclusionState:) and ignores the pointer while it
    // is NO. On iOS the window is visible whenever the app is active.
    Class gameWindow=NSClassFromString(@"GameWindow");SEL setVisible=NSSelectorFromString(@"setIsWindowVisible:"),visible=NSSelectorFromString(@"isWindowVisible");
    if([gameWindow respondsToSelector:setVisible]){
        if(!((BOOL(*)(id,SEL))objc_msgSend)(gameWindow,visible)){((void(*)(id,SEL,BOOL))objc_msgSend)(gameWindow,setVisible,YES);fprintf(stderr,"[focus] GameWindow isWindowVisible 0 -> 1\n");}
    }
    for(id c in controllers.allObjects)if([c respondsToSelector:NSSelectorFromString(@"m_windowFocus")])
        fprintf(stderr,"[focus] %s m_windowFocus=%d\n",class_getName([c class]),((BOOL(*)(id,SEL))objc_msgSend)(c,NSSelectorFromString(@"m_windowFocus")));
}
__attribute__((constructor)) static void install_focus(void) {
    controllers=[NSHashTable weakObjectsHashTable];
    Method m=class_getInstanceMethod(NSClassFromString(@"MPWindowController"),@selector(initWithWindow:));
    if(m){origInitWithWindow=(void *)method_getImplementation(m);method_setImplementation(m,(IMP)trackedInitWithWindow);}
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){mp_cp_refocus();}];
}

// MP_CURSOR_TRACE: what the game sees of the pointer — +[NSEvent mouseLocation]
// values, its focus check (isWindowActive), GameView's converted position, and
// cursor warps. Changes only, to keep the log readable.
static IMP origMouseLocation,origWindowActive,origConvert;
static CGPoint traced_mouseLocation(id self,SEL _cmd){CGPoint p=((CGPoint(*)(id,SEL))origMouseLocation)(self,_cmd);static CGPoint last={-1,-1};
    if(!CGPointEqualToPoint(p,last)){fprintf(stderr,"[cursor] mouseLocation %.0f,%.0f\n",p.x,p.y);last=p;}return p;}
static BOOL traced_windowActive(id self,SEL _cmd){BOOL r=((BOOL(*)(id,SEL))origWindowActive)(self,_cmd);static int last=-1;
    if(r!=last){fprintf(stderr,"[cursor] -[%s isWindowActive] = %d\n",class_getName(object_getClass(self)),r);last=r;}return r;}
static CGPoint traced_convert(id self,SEL _cmd){CGPoint p=((CGPoint(*)(id,SEL))origConvert)(self,_cmd);static CGPoint last={-1,-1};
    if(!CGPointEqualToPoint(p,last)){fprintf(stderr,"[cursor] game position %.1f,%.1f\n",p.x,p.y);last=p;}return p;}
void mp_cp_cursor_trace_install(void) {
    if(!getenv("MP_CURSOR_TRACE"))return;
    static dispatch_once_t once;dispatch_once(&once,^{
        Method m=class_getClassMethod(MPKeyEvent.class,@selector(mouseLocation));origMouseLocation=method_setImplementation(m,(IMP)traced_mouseLocation);
        Class gv=NSClassFromString(@"GameView");
        if(gv && (m=class_getInstanceMethod(gv,NSSelectorFromString(@"convertMousePosToGame"))))origConvert=method_setImplementation(m,(IMP)traced_convert);
        unsigned n=0;Class *all=objc_copyClassList(&n);
        for(unsigned i=0;i<n;i++){Method w=class_getInstanceMethod(all[i],NSSelectorFromString(@"isWindowActive"));
            if(w && !origWindowActive && !strcmp(class_getName(all[i]),"GameWindowDelegate")){fprintf(stderr,"[cursor] isWindowActive implemented by %s\n",class_getName(all[i]));origWindowActive=method_setImplementation(w,(IMP)traced_windowActive);}}
        free(all);
    });
}

// MP_CURSOR_TRACE: the engine's input state (object at guest 0x107c63220:
// +0x39 flag, +0x3c/+0x40 floats, +0x44 mode), logged on change.
extern uintptr_t mp_guest_base(unsigned);
void mp_cp_engine_cursor_trace(void) {
    if(!getenv("MP_CURSOR_TRACE"))return;
    uintptr_t base=mp_guest_base(0);if(!base)return;
    unsigned char *engine=(unsigned char *)(base+(0x107c63220-0x100000000));
    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){
        static float lx=-1,ly=-1;static int lf=-1,lm=-1;
        float x,y;int m;memcpy(&x,engine+0x3c,4);memcpy(&y,engine+0x40,4);memcpy(&m,engine+0x44,4);int f=engine[0x39];
        if(x!=lx||y!=ly||f!=lf||m!=lm){fprintf(stderr,"[engine] flag39=%d f3c=%.2f f40=%.2f mode44=%d\n",f,x,y,m);lx=x;ly=y;lf=f;lm=m;}
    }];
}

// Every touch start: the game's pointer gates (focus, visibility, pointer in
// view) are re-asserted, since the game may create or reset them at any time.
void mp_game_touch_began(void) {
    static BOOL busy;if(busy)return;busy=YES;
    MPGameWindow *w=mp_game_key_window();
    if(w) {
        NSMutableArray<UIView *> *views=w.contentView?[NSMutableArray arrayWithObject:w.contentView]:[NSMutableArray array];
        while(views.count){UIView *v=views.firstObject;[views removeObjectAtIndex:0];[views addObjectsFromArray:v.subviews];
            SEL getIn=NSSelectorFromString(@"cursorInView"),setIn=NSSelectorFromString(@"setCursorInView:"),getC=NSSelectorFromString(@"m_windowController");
            if([v respondsToSelector:setIn] && !((BOOL(*)(id,SEL))objc_msgSend)(v,getIn))((void(*)(id,SEL,BOOL))objc_msgSend)(v,setIn,YES);
            if([v respondsToSelector:getC]){id c=((id(*)(id,SEL))objc_msgSend)(v,getC);SEL f=NSSelectorFromString(@"m_windowFocus");
                if(c && [c respondsToSelector:f] && !((BOOL(*)(id,SEL))objc_msgSend)(c,f))mp_cp_refocus();}}
        Class gw=NSClassFromString(@"GameWindow");SEL vis=NSSelectorFromString(@"isWindowVisible");
        if([gw respondsToSelector:vis] && !((BOOL(*)(id,SEL))objc_msgSend)(gw,vis))((void(*)(id,SEL,BOOL))objc_msgSend)(gw,NSSelectorFromString(@"setIsWindowVisible:"),YES);
    }
    busy=NO;
}

// Always-on input diagnosis (changes only): the engine keyboard's held flags
// for W A S D Space (engine at guest 0x107c63220, keyboard = *(engine+0x20),
// flag = keyboard[0x20+mac keycode]) — shows whether keys reach the engine.
void mp_cp_key_state_log(void) {
    if(!getenv("MP_CURSOR_TRACE"))return;
    uintptr_t base=mp_guest_base(0);if(!base)return;
    unsigned char *engine=(unsigned char *)(base+(0x107c63220-0x100000000));
    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t){
        unsigned char *kb=*(unsigned char **)(engine+0x20);if(!kb)return;
        static char last[6]="?????";char now[6]={kb[0x20+13]?'W':'-',kb[0x20+0]?'A':'-',kb[0x20+1]?'S':'-',kb[0x20+2]?'D':'-',kb[0x20+49]?' ':'_',0};
        if(memcmp(now,last,5)){fprintf(stderr,"[keys] engine held: %s\n",now);memcpy(last,now,6);}
    }];
}
