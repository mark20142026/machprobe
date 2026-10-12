// AppKit behaviour SDL2's Cocoa backend needs beyond the Phase 5 shims, found
// by the selector survey (phase6/runtime/Survey.m). Shared adapter classes
// get categories; nothing here pretends a desktop-only service exists.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Lifecycle.h"
#import "Window.h"
#import "Input.h"
#import "Menu.h"
@implementation MPGameApplication (MPAppleMenu)
// iOS has no menu bar; the menu object is kept so the guest can read it back.
- (void)setAppleMenu:(id)menu {objc_setAssociatedObject(self,@selector(appleMenu),menu,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (id)appleMenu {return objc_getAssociatedObject(self,@selector(appleMenu));}
@end
@interface MPWeakBox:NSObject @property(nonatomic,weak) id value; @end
@implementation MPWeakBox @end
// AppKit subscribes a window's delegate to the window notifications whose
// delegate methods it implements (NSWindow.h). SDL learns keyboard focus from
// windowDidBecomeKey: this way. Resize/fullscreen are excluded: Window.m
// already calls those delegate methods directly.
static NSArray<NSString *> *delegateNotifications(void) {
    return @[@"DidBecomeKey",@"DidResignKey",@"DidBecomeMain",@"DidResignMain",@"DidMove",@"DidMiniaturize",@"DidDeminiaturize",
             @"WillClose",@"DidChangeBackingProperties",@"DidChangeScreen",@"DidExpose",@"DidEndLiveResize",@"WillStartLiveResize"];
}
static void (*originalSetDelegate)(id,SEL,id);
static void set_delegate(MPGameWindow *self,SEL _cmd,id delegate) {
    id old=self.delegate;
    if(old)for(NSString *n in delegateNotifications())[NSNotificationCenter.defaultCenter removeObserver:old name:[NSString stringWithFormat:@"NSWindow%@Notification",n] object:self];
    originalSetDelegate(self,_cmd,delegate);
    for(NSString *n in delegateNotifications()) {
        SEL selector=NSSelectorFromString([NSString stringWithFormat:@"window%@:",n]);
        if([delegate respondsToSelector:selector])[NSNotificationCenter.defaultCenter addObserver:delegate selector:selector name:[NSString stringWithFormat:@"NSWindow%@Notification",n] object:self];
    }
}
@implementation MPGameWindow (MPDelegateNotifications)
+ (void)load {
    Method m=class_getInstanceMethod(self,@selector(setDelegate:));
    originalSetDelegate=(void (*)(id,SEL,id))method_setImplementation(m,(IMP)set_delegate);
}
@end
@implementation MPGameWindow (MPScreenInit)
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)mask backing:(NSUInteger)backing defer:(BOOL)defer screen:(id)screen {
    // Single iOS screen: the screen argument can only name it.
    return [self initWithContentRect:rect styleMask:mask backing:backing defer:defer];
}
// Mouse grab: the adapter's virtual cursor is clamped to this rectangle
// (screen coordinates; the fullscreen window's frame is the screen).
- (void)setMouseConfinementRect:(CGRect)rect {objc_setAssociatedObject(self,@selector(mouseConfinementRect),[NSValue valueWithCGRect:rect],OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (CGRect)mouseConfinementRect {NSValue *v=objc_getAssociatedObject(self,@selector(mouseConfinementRect));return v?v.CGRectValue:CGRectZero;}
// Fullscreen window: window coordinates equal AppKit screen coordinates.
- (CGPoint)mouseLocationOutsideOfEventStream {return ((CGPoint(*)(id,SEL))objc_msgSend)(NSClassFromString(@"MPKeyEvent"),@selector(mouseLocation));}
- (BOOL)isKeyWindow {return mp_game_key_window()==self;}
- (BOOL)isMiniaturized {return NO;} // iOS scenes cannot be miniaturized.
// Borderless windows: content and frame coincide (Phase 5 geometry model).
- (void)setContentSize:(CGSize)size {CGRect f=self.frame;f.size=size;[self setFrame:f display:YES];}
- (void)setFrameOrigin:(CGPoint)origin {CGRect f=self.frame;f.origin=origin;[self setFrame:f display:YES];}
- (void)setOneShot:(BOOL)value {objc_setAssociatedObject(self,@selector(isOneShot),@(value),OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (BOOL)isOneShot {return [objc_getAssociatedObject(self,@selector(isOneShot)) boolValue];}
// Stable per-window number for the process (AppKit's window server number).
- (NSInteger)windowNumber {
    NSNumber *n=objc_getAssociatedObject(self,@selector(windowNumber));
    if(!n){static NSInteger next=1;n=@(next++);objc_setAssociatedObject(self,@selector(windowNumber),n,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    return n.integerValue;
}
- (void)setNextResponder:(id)responder {MPWeakBox *b=[MPWeakBox new];b.value=responder;objc_setAssociatedObject(self,@selector(mp_appKitNextResponder),b,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (id)mp_appKitNextResponder {return ((MPWeakBox *)objc_getAssociatedObject(self,@selector(mp_appKitNextResponder))).value;}
- (id)nextResponder {return [self mp_appKitNextResponder];}
// Removes the window from the screen without closing it; ordering it front
// again (makeKeyAndOrderFront:) shows the same content view.
- (void)orderOut:(id)sender {self.contentView.hidden=YES;}
- (void)orderFront:(id)sender {self.contentView.hidden=NO;}
- (CGFloat)backingScaleFactor {return UIScreen.mainScreen.nativeScale;}
- (void)setColorSpace:(id)space {objc_setAssociatedObject(self,@selector(colorSpace),space,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (id)colorSpace {return objc_getAssociatedObject(self,@selector(colorSpace));}
@end
// The iOS presentation surface is sRGB; this object names that space.
@interface MPColorSpace:NSObject @end
@implementation MPColorSpace
+ (instancetype)sRGBColorSpace {static MPColorSpace *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
+ (instancetype)genericRGBColorSpace {return [self sRGBColorSpace];}
- (NSString *)localizedName {return @"sRGB IEC61966-2.1";}
- (CGColorSpaceRef)CGColorSpace {static CGColorSpaceRef c;static dispatch_once_t once;dispatch_once(&once,^{c=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);});return c;}
@end
// No desktop OpenGL exists on iOS: there is never a current context, and
// creating one fails (init returns nil), so SDL's GL path reports an error.
@interface MPOpenGLContext:NSObject @end
@implementation MPOpenGLContext
+ (id)currentContext {return nil;}
+ (void)clearCurrentContext {}
- (instancetype)initWithFormat:(id)format shareContext:(id)share {return nil;}
@end
@interface MPOpenGLPixelFormat:NSObject @end
@implementation MPOpenGLPixelFormat
- (instancetype)initWithAttributes:(const uint32_t *)attributes {return nil;}
@end
// AppKit responder chain, kept separate from UIKit's real nextResponder so
// UIKit touch delivery is unchanged. Unretained, as in AppKit (weak here).
@implementation UIResponder (MPAppKitResponder)
- (void)setNextResponder:(id)responder {MPWeakBox *b=[MPWeakBox new];b.value=responder;objc_setAssociatedObject(self,@selector(mp_appKitNextResponder),b,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (id)mp_appKitNextResponder {return ((MPWeakBox *)objc_getAssociatedObject(self,@selector(mp_appKitNextResponder))).value;}
// AppKit backing store units: the iOS screen's native pixel scale.
- (CGSize)convertSizeToBacking:(CGSize)size {CGFloat k=UIScreen.mainScreen.nativeScale;return CGSizeMake(size.width*k,size.height*k);}
- (CGRect)convertRectToBacking:(CGRect)rect {CGFloat k=UIScreen.mainScreen.nativeScale;return CGRectMake(rect.origin.x*k,rect.origin.y*k,rect.size.width*k,rect.size.height*k);}
- (CGSize)convertSizeFromBacking:(CGSize)size {CGFloat k=UIScreen.mainScreen.nativeScale;return CGSizeMake(size.width/k,size.height/k);}
- (CGRect)convertRectFromBacking:(CGRect)rect {CGFloat k=UIScreen.mainScreen.nativeScale;return CGRectMake(rect.origin.x/k,rect.origin.y/k,rect.size.width/k,rect.size.height/k);}
// NSMouseInRect: origin edges inclusive, far edges exclusive, with the y
// edges swapped for unflipped (bottom-left origin) views.
- (BOOL)mouse:(CGPoint)p inRect:(CGRect)r {
    BOOL flipped=[self respondsToSelector:@selector(isFlipped)] && ((BOOL(*)(id,SEL))objc_msgSend)(self,@selector(isFlipped));
    if(p.x<CGRectGetMinX(r) || p.x>=CGRectGetMaxX(r))return NO;
    return flipped?(p.y>=CGRectGetMinY(r) && p.y<CGRectGetMaxY(r)):(p.y>CGRectGetMinY(r) && p.y<=CGRectGetMaxY(r));
}
// NSResponder text-input dispatch with AppKit's standard key bindings
// (StandardKeyBinding.dict) for the keys the input adapter produces: editing
// and navigation keys become command selectors, other characters become text.
- (void)interpretKeyEvents:(NSArray *)events {
    static NSDictionary<NSNumber *,NSString *> *commands;
    if(!commands)commands=@{@51:@"deleteBackward:",@117:@"deleteForward:",@36:@"insertNewline:",@76:@"insertNewline:",@48:@"insertTab:",
        @53:@"cancelOperation:",@123:@"moveLeft:",@124:@"moveRight:",@125:@"moveDown:",@126:@"moveUp:",@115:@"moveToBeginningOfLine:",@119:@"moveToEndOfLine:"};
    for(id event in events) {
        unsigned short code=[event respondsToSelector:@selector(keyCode)]?((unsigned short(*)(id,SEL))objc_msgSend)(event,@selector(keyCode)):0;
        NSUInteger flags=[event respondsToSelector:@selector(modifierFlags)]?((NSUInteger(*)(id,SEL))objc_msgSend)(event,@selector(modifierFlags)):0;
        NSString *command=commands[@(code)];
        if(command) {
            SEL selector=NSSelectorFromString(command);
            if([self respondsToSelector:@selector(doCommandBySelector:)])((void(*)(id,SEL,SEL))objc_msgSend)(self,@selector(doCommandBySelector:),selector);
            else if([self respondsToSelector:selector])((void(*)(id,SEL,id))objc_msgSend)(self,selector,nil);
            continue;
        }
        if(flags&((1UL<<18)|(1UL<<20)))continue; // Control/Command chords are shortcuts, not text.
        NSString *text=[event respondsToSelector:@selector(characters)]?((id(*)(id,SEL))objc_msgSend)(event,@selector(characters)):nil;
        if(!text.length)continue;
        if([self respondsToSelector:@selector(insertText:replacementRange:)])((void(*)(id,SEL,id,NSRange))objc_msgSend)(self,@selector(insertText:replacementRange:),text,NSMakeRange(NSNotFound,0));
        else if([self respondsToSelector:@selector(insertText:)])((void(*)(id,SEL,id))objc_msgSend)(self,@selector(insertText:),text);
    }
}
- (void)setAcceptsTouchEvents:(BOOL)value {objc_setAssociatedObject(self,@selector(acceptsTouchEvents),@(value),OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
- (BOOL)acceptsTouchEvents {return [objc_getAssociatedObject(self,@selector(acceptsTouchEvents)) boolValue];}
@end
// Outside a drawing pass AppKit has no current graphics context either.
@interface MPGraphicsContext:NSObject @end
@implementation MPGraphicsContext
+ (id)currentContext {return nil;}
+ (void)saveGraphicsState {}
+ (void)restoreGraphicsState {}
@end
// NSTrackingArea: records the region and owner; the adapter's pointer
// delivery already sends enter/exit/moved through the view's responders.
@interface MPTrackingArea:NSObject
@property CGRect rect;@property NSUInteger options;@property(nonatomic,weak) id owner;@property(copy) NSDictionary *userInfo;
@end
@implementation MPTrackingArea
- (instancetype)initWithRect:(CGRect)r options:(NSUInteger)o owner:(id)owner userInfo:(NSDictionary *)u {if((self=[super init])){_rect=r;_options=o;_owner=owner;_userInfo=[u copy];}return self;}
@end
@implementation UIView (MPTrackingAreas)
- (NSMutableArray *)mp_trackingAreas {NSMutableArray *a=objc_getAssociatedObject(self,@selector(mp_trackingAreas));if(!a){a=[NSMutableArray array];objc_setAssociatedObject(self,@selector(mp_trackingAreas),a,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}return a;}
- (void)addTrackingArea:(id)area {[[self mp_trackingAreas] addObject:area];}
- (void)removeTrackingArea:(id)area {[[self mp_trackingAreas] removeObject:area];}
- (NSArray *)trackingAreas {return [[self mp_trackingAreas] copy];}
- (void)updateTrackingAreas {}
@end
// NSWindowController: owns one window; shows it via the window adapter.
@interface MPWindowController:UIResponder
@property(nonatomic,strong) id window;
@end
@implementation MPWindowController
- (instancetype)initWithWindow:(id)window {if((self=[super init])){_window=window;[self windowDidLoad];}return self;}
- (void)windowDidLoad {}
- (void)showWindow:(id)sender {[self.window makeKeyAndOrderFront:sender];}
- (void)close {[self.window close];}
- (BOOL)isWindowLoaded {return self.window!=nil;}
@end
// NSWorkspace: the per-app notification centre and URL opening exist on iOS;
// other desktop workspace services are not provided.
@interface MPWorkspace:NSObject @property(nonatomic,strong) NSNotificationCenter *notificationCenter; @end
@implementation MPWorkspace
+ (instancetype)sharedWorkspace {static MPWorkspace *w;static dispatch_once_t once;dispatch_once(&once,^{w=[self new];w.notificationCenter=[NSNotificationCenter new];});return w;}
- (BOOL)openURL:(NSURL *)url {dispatch_async(dispatch_get_main_queue(),^{[UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];});return url!=nil;}
- (BOOL)accessibilityDisplayShouldReduceMotion {return UIAccessibilityIsReduceMotionEnabled();}
@end
Class mp_stk_appkit_class(const char *name) {
    if(!strcmp(name,"NSTrackingArea"))return MPTrackingArea.class;
    if(!strcmp(name,"NSWindowController"))return MPWindowController.class;
    if(!strcmp(name,"NSWorkspace"))return MPWorkspace.class;
    if(!strcmp(name,"NSGraphicsContext"))return MPGraphicsContext.class;
    if(!strcmp(name,"NSColorSpace"))return MPColorSpace.class;
    if(!strcmp(name,"NSOpenGLContext"))return MPOpenGLContext.class;
    if(!strcmp(name,"NSOpenGLPixelFormat"))return MPOpenGLPixelFormat.class;
    return Nil;
}

// iOS has no menu bar; it is never visible and cannot be shown.
@implementation MPGameMenu (MPMenuBar)
+ (void)setMenuBarVisible:(BOOL)visible {}
+ (BOOL)menuBarVisible {return NO;}
@end
