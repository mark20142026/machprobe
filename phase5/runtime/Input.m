#import "Input.h"
#import "Window.h"
#import "Lifecycle.h"
#import <objc/message.h>
#include <math.h>
static NSMutableDictionary *monitors;
static BOOL mouseAssociated=YES,virtualCursorValid;
static BOOL secondaryTouch;
static CGPoint virtualCursor;
static __weak MPInputController *pointerController;
int mp_game_associate_mouse(uint32_t connected) {
    if(mouseAssociated==(connected!=0))return 0;
    mouseAssociated=connected!=0;
    [pointerController setNeedsUpdateOfPrefersPointerLocked];
    mp_game_trace(mouseAssociated?@"guest cursor association enabled":@"guest cursor detached for relative input");
    return 0;
}
int mp_game_warp_cursor(CGPoint point) {
    if(!isfinite(point.x) || !isfinite(point.y))return 1001;
    // Move only the guest's virtual cursor. Never warp the user's host pointer.
    static int trace=-1;if(trace<0)trace=getenv("MP_CURSOR_TRACE")!=NULL;if(trace)fprintf(stderr,"[cursor] warp to %.0f,%.0f\n",point.x,point.y);
    virtualCursor=point;virtualCursorValid=YES;return 0;
}
CGPoint mp_game_point_for_view(UIView *view,CGPoint point) {
    // UIKit conversion is already top-left based. A guest view declaring
    // isFlipped must not have its Y coordinate inverted a second time.
    SEL flipped=NSSelectorFromString(@"isFlipped");
    if([view respondsToSelector:flipped] && !((BOOL(*)(id,SEL))objc_msgSend)(view,flipped))point.y=view.bounds.size.height-point.y;
    return point;
}
// Global input state behind NSEvent's class queries (SDL reads these at
// keyboard/mouse init and for its global mouse state). Updated by the same
// paths that deliver events to the guest.
static NSUInteger currentModifiers,pressedButtons;
static CGPoint lastPointerLocation;
@implementation MPKeyEvent
+ (NSUInteger)modifierFlags {return currentModifiers;}
+ (NSUInteger)pressedMouseButtons {return pressedButtons;}
// Screen coordinates with AppKit's bottom-left origin.
+ (CGPoint)mouseLocation {return CGPointMake(lastPointerLocation.x,UIScreen.mainScreen.bounds.size.height-lastPointerLocation.y);}
- (id)copyWithZone:(NSZone *)zone {
    MPKeyEvent *copy=[[[self class] allocWithZone:zone] init];
    copy.keyCode=self.keyCode;copy.type=self.type;copy.modifierFlags=self.modifierFlags;copy.isARepeat=self.isARepeat;
    copy.characters=self.characters;copy.charactersIgnoringModifiers=self.charactersIgnoringModifiers;
    copy.timestamp=self.timestamp;copy.window=self.window;copy.locationInWindow=self.locationInWindow;
    copy.deltaX=self.deltaX;copy.deltaY=self.deltaY;copy.buttonNumber=self.buttonNumber;copy.clickCount=self.clickCount;
    copy.trackingNumber=self.trackingNumber;copy.userData=self.userData;return copy;
}
+ (id)addLocalMonitorForEventsMatchingMask:(unsigned long long)mask handler:(id(^)(id))handler {
    if(!monitors)monitors=[NSMutableDictionary new];NSString *token=NSUUID.UUID.UUIDString;monitors[token]=@[@(mask),[handler copy]];return token;
}
+ (void)removeMonitor:(id)token {if(token)[monitors removeObjectForKey:token];}
@end
BOOL mp_game_cursor_hidden(void);
void mp_game_pointer_to(NSUInteger type,CGPoint p);
// A guest adapter may refresh pointer focus state when a touch starts.
__attribute__((weak)) void mp_game_touch_began(void){}
@implementation MPPhysicalWindow
- (instancetype)initWithWindowScene:(UIWindowScene *)scene {if((self=[super initWithWindowScene:scene]))_pointerLocation=CGPointMake(-1,-1);return self;}
- (void)sendEvent:(UIEvent *)event {
    UITouch *touch=event.allTouches.anyObject;
    if(touch) {
        CGPoint previous=self.pointerLocation;self.pointerLocation=[touch locationInView:self];
        MPGameWindow *guest=mp_game_key_window();UIView *content=guest.contentView;
        if(content && [touch.view isDescendantOfView:content]) {
            NSUInteger kind=touch.phase==UITouchPhaseBegan?1:touch.phase==UITouchPhaseMoved?6:
                (touch.phase==UITouchPhaseEnded || touch.phase==UITouchPhaseCancelled)?2:0;
            if(kind && mp_game_touch_scroll) {
                // Trackpad-style touch for guests that draw their own cursor:
                // one finger moves the cursor under it and taps click on
                // release; two fingers scroll and a two-finger tap right-clicks.
                static CGPoint start,last;static BOOL moved;static NSUInteger fingers;
                NSUInteger active=0;CGPoint sum=CGPointZero;
                for(UITouch *t in event.allTouches)if(t.phase!=UITouchPhaseEnded && t.phase!=UITouchPhaseCancelled){active++;CGPoint q=[t locationInView:content];sum.x+=q.x;sum.y+=q.y;}
                CGPoint p=mp_game_point_for_view(content,[touch locationInView:content]);
                CGPoint centre=active?mp_game_point_for_view(content,CGPointMake(sum.x/active,sum.y/active)):p;
                if(kind==1 && event.allTouches.count==1){mp_game_touch_began();start=last=p;moved=NO;fingers=1;mp_game_pointer_to(5,p);}
                if(event.allTouches.count>fingers){fingers=event.allTouches.count;last=centre;}
                if(kind==6) {
                    CGPoint at=fingers>=2?centre:p;
                    if(!moved && hypot(at.x-start.x,at.y-start.y)>8)moved=YES;
                    if(fingers>=2){if(moved)mp_game_scroll(at,CGPointMake(at.x-last.x,at.y-last.y));}
                    else mp_game_pointer_to(5,p);
                    last=at;
                }
                if(active==0) {
                    if(fingers>=2 && !moved){mp_game_pointer_to(5,start);mp_game_pointer_to(3,start);mp_game_pointer_to(4,start);}
                    else if(fingers==1 && !moved){mp_game_pointer_to(5,p);mp_game_pointer_to(1,p);mp_game_pointer_to(2,p);}
                    fingers=0;
                }
                kind=0;
            }
            if(kind) {
                CGPoint p=mp_game_point_for_view(content,[touch locationInView:content]);
                CGPoint before=mp_game_point_for_view(content,[content convertPoint:previous fromView:self]);
                CGPoint delta=kind==1?CGPointZero:CGPointMake(p.x-before.x,p.y-before.y);
                // A touch begins at a new cursor position without a preceding
                // hover. Deliver that position before the mouse-button event.
                if(kind==1)mp_game_pointer(5,p,CGPointZero);
                if(secondaryTouch)kind=kind==1?3:kind==2?4:7;
                mp_game_pointer(kind,p,delta);
            }
        }
    }
    [super sendEvent:event];
}
// MTKView uses the UIKit coordinate system on this host. Keep its window point
// and convertPoint:fromView: in the same space; full AppKit flipped-view mapping
// remains a separate, unimplemented capability.
- (CGPoint)mouseLocationOutsideOfEventStream {return self.pointerLocation;}
@end
@implementation MPGameCursor
- (instancetype)initWithImage:(id)image hotSpot:(CGPoint)hotSpot {
    if(!image)return nil;if((self=[super init])){_image=image;_hotSpot=hotSpot;}return self;
}
static NSUInteger hideDepth;
BOOL mp_game_cursor_hidden(void){return hideDepth>0;}
+ (instancetype)arrowCursor {static MPGameCursor *cursor;static dispatch_once_t once;dispatch_once(&once,^{cursor=[self new];});return cursor;}
static MPGameCursor *currentCursor;
// The default UIKit pointer supplies the arrow role; the guest's choice is
// recorded so +currentCursor reports what it set.
- (void)set {currentCursor=self;}
+ (instancetype)currentCursor {return currentCursor?:[self arrowCursor];}
+ (void)hide {hideDepth++;}
+ (void)unhide {if(hideDepth)hideDepth--;}
// Touch has no persistent visible cursor. These track balanced guest requests;
// physical pointer styling is not claimed by the current touch adapter.
@end
static NSMutableSet<NSNumber *> *held;
static NSUInteger delivered,pointerDelivered;
static NSDictionary *lastPointer;
// USB HID keyboard usage (UIKeyboardHIDUsage) to Apple virtual-key codes
// (HIToolbox Events.h kVK_*): the full ANSI/ISO keyboard, function and
// navigation keys, keypad and modifiers. 65535 = no Mac equivalent.
unsigned short mp_mac_keycode(NSUInteger hid) {
    static const unsigned short letters[]={0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6};
    static const unsigned short digits[]={18,19,20,21,23,22,26,28,25,29};
    static const unsigned short fkeys[]={122,120,99,118,96,97,98,100,101,109,103,111}; // F1-F12
    static const unsigned short fkeys2[]={105,107,113,106,64,79,80,90};                 // F13-F20
    static const unsigned short keypad[]={83,84,85,86,87,88,89,91,92,82};               // KP1-9, KP0
    if(hid>=4 && hid<=29)return letters[hid-4];
    if(hid>=30 && hid<=39)return digits[hid-30];
    if(hid>=58 && hid<=69)return fkeys[hid-58];
    if(hid>=104 && hid<=111)return fkeys2[hid-104];
    if(hid>=89 && hid<=98)return keypad[hid-89];
    switch(hid){
    case 40:return 36;  case 41:return 53;  case 42:return 51;  case 43:return 48;  case 44:return 49; // Return Esc Delete Tab Space
    case 45:return 27;  case 46:return 24;  case 47:return 33;  case 48:return 30;  case 49:return 42; // - = [ ] backslash
    case 50:return 42;  case 51:return 41;  case 52:return 39;  case 53:return 50;  case 54:return 43; // non-US # ; ' ` ,
    case 55:return 47;  case 56:return 44;  case 57:return 57;                                          // . / CapsLock
    case 73:return 114; case 74:return 115; case 75:return 116; case 76:return 117; case 77:return 119; // Help/Insert Home PgUp FwdDel End
    case 78:return 121; case 79:return 124; case 80:return 123; case 81:return 125; case 82:return 126; // PgDn Right Left Down Up
    case 83:return 71;  case 84:return 75;  case 85:return 67;  case 86:return 78;  case 87:return 69; // Clear KP/ KP* KP- KP+
    case 88:return 76;  case 99:return 65;  case 100:return 10; case 103:return 81;                    // KPEnter KP. ISOSection KP=
    case 224:return 59; case 225:return 56; case 226:return 58; case 227:return 55;                    // LCtrl LShift LOption LCmd
    case 228:return 62; case 229:return 60; case 230:return 61; case 231:return 54;                    // RCtrl RShift ROption RCmd
    }
    return 65535;
}
BOOL mp_is_modifier_keycode(unsigned short code){return (code>=54 && code<=62) || code==57;}
// AppKit reports modifier keys as NSEventTypeFlagsChanged (12) carrying the
// new modifier state, never as key down/up.
void mp_game_modifier(unsigned short code,BOOL down,NSUInteger modifiers) {
    // AppKit sends the state AFTER the change. NSEventModifierFlags bits:
    // CapsLock 1<<16, Shift 1<<17, Control 1<<18, Option 1<<19, Command 1<<20.
    NSUInteger flag=(code==56||code==60)?1UL<<17:(code==59||code==62)?1UL<<18:(code==58||code==61)?1UL<<19:(code==55||code==54)?1UL<<20:0;
    if(code==57)currentModifiers=(currentModifiers&~(1UL<<16))|(modifiers&(1UL<<16)); // Caps Lock toggles.
    else if(down)currentModifiers|=flag;else currentModifiers&=~flag;
    modifiers=currentModifiers;
    MPKeyEvent *event=[MPKeyEvent new];event.type=12;event.keyCode=code;event.modifierFlags=modifiers;
    event.timestamp=NSProcessInfo.processInfo.systemUptime;event.window=mp_game_key_window();
    delivered++;mp_game_trace([NSString stringWithFormat:@"guest modifier %@ %u",down?@"down":@"up",code]);
    mp_game_post(event);
}
void mp_game_key(unsigned short code,NSString *characters,BOOL down,NSUInteger modifiers) {
    if(!held)held=[NSMutableSet new];
    currentModifiers=modifiers;
    MPKeyEvent *event=[MPKeyEvent new];event.type=down?10:11;event.keyCode=code;event.modifierFlags=modifiers;
    event.characters=characters;event.charactersIgnoringModifiers=characters;
    event.timestamp=NSProcessInfo.processInfo.systemUptime;event.isARepeat=down && [held containsObject:@(code)];
    if(down)[held addObject:@(code)];else [held removeObject:@(code)];
    delivered++;mp_game_trace([NSString stringWithFormat:@"guest key %@ %u",down?@"down":@"up",code]);
    event.window=mp_game_key_window();
    mp_game_post(event);
}
void mp_game_dispatch_event(MPKeyEvent *event) {
    // AppKit: with no first responder the window itself responds (and passes
    // unhandled events along its nextResponder, e.g. SDL's window listener).
    id responder=mp_game_key_window().firstResponder?:mp_game_key_window();
    SEL selector=NULL;
    switch(event.type) {
        case 10:selector=@selector(keyDown:);break;case 11:selector=@selector(keyUp:);break;
        case 1:selector=@selector(mouseDown:);break;case 2:selector=@selector(mouseUp:);break;
        case 3:selector=@selector(rightMouseDown:);break;case 4:selector=@selector(rightMouseUp:);break;
        case 7:selector=@selector(rightMouseDragged:);break;
        case 5:selector=@selector(mouseMoved:);break;case 6:selector=@selector(mouseDragged:);break;
        case 12:selector=@selector(flagsChanged:);break;
        case 22:selector=@selector(scrollWheel:);break;
    }
    if(!selector){mp_game_trace([NSString stringWithFormat:@"unsupported application event type %lu",(unsigned long)event.type]);return;}
    for(NSArray *entry in monitors.allValues)if([entry[0] unsignedLongLongValue]&(1ULL<<event.type)){id(^handler)(id)=entry[1];MPKeyEvent *in=event;event=handler(event);
        if(!event){if(in.type>=10){static int n;if(n++<20)fprintf(stderr,"[keys] monitor consumed %s %u\n",in.type==10?"down":in.type==11?"up":"flags",in.keyCode);}return;}}
    // AppKit forwards unhandled events along nextResponder (SDL chains its
    // view to its window listener); follow that chain when it was set.
    for(unsigned depth=0;responder && ![responder respondsToSelector:selector] && depth<8;depth++)
        responder=[responder respondsToSelector:@selector(mp_appKitNextResponder)]?[responder performSelector:@selector(mp_appKitNextResponder)]:nil;
    if(![responder respondsToSelector:selector]) {
        // No first responder handles it (e.g. Cyberpunk's GameView becomes
        // first responder only from a key-window callback): use the first
        // view in the key window that accepts first responder and implements
        // the event, and keep it as first responder, as AppKit's key view would.
        MPGameWindow *window=mp_game_key_window()?:mp_game_windows().firstObject;
        NSMutableArray<UIView *> *views=window.contentView?[NSMutableArray arrayWithObject:window.contentView]:[NSMutableArray array];
        responder=nil;
        while(views.count && !responder){UIView *v=views.firstObject;[views removeObjectAtIndex:0];
            BOOL accepts=[v respondsToSelector:@selector(acceptsFirstResponder)] && ((BOOL(*)(id,SEL))objc_msgSend)(v,@selector(acceptsFirstResponder));
            if(accepts && [v respondsToSelector:selector] && ![v isKindOfClass:UIControl.class])responder=v;else [views addObjectsFromArray:v.subviews];}
        if(!responder){mp_game_trace(@"keyboard event has no guest responder");return;}
        mp_game_trace([NSString stringWithFormat:@"first responder fallback: %@",NSStringFromClass([responder class])]);
        if(window && event.type>=10)[window makeFirstResponder:responder];
    }
    if(event.type<10 && pointerDelivered<24)mp_game_trace([NSString stringWithFormat:@"deliver %@ to %@ at %@",NSStringFromSelector(selector),NSStringFromClass([responder class]),NSStringFromCGPoint(event.locationInWindow)]);
    ((void(*)(id,SEL,id))objc_msgSend)(responder,selector,event);
}
void mp_game_pointer(NSUInteger type,CGPoint location,CGPoint delta) {
    MPGameWindow *window=mp_game_key_window();if(!window)return;
    if(mouseAssociated || !virtualCursorValid){virtualCursor=location;virtualCursorValid=YES;}
    else location=virtualCursor;
    // Honour an AppKit mouse confinement rectangle when the guest set one.
    if([window respondsToSelector:@selector(mouseConfinementRect)]) {
        CGRect r=((CGRect(*)(id,SEL))objc_msgSend)(window,@selector(mouseConfinementRect));
        if(!CGRectIsEmpty(r)){location.x=MIN(MAX(location.x,CGRectGetMinX(r)),CGRectGetMaxX(r)-1);location.y=MIN(MAX(location.y,CGRectGetMinY(r)),CGRectGetMaxY(r)-1);}
    }
    mp_game_update_tracking(window.contentView,location);
    if(type==5 && !window.acceptsMouseMovedEvents)return;
    // NSEventType: 1/2 left down/up, 3/4 right down/up.
    if(type==1)pressedButtons|=1;else if(type==2)pressedButtons&=~1u;else if(type==3)pressedButtons|=2;else if(type==4)pressedButtons&=~2u;
    lastPointerLocation=location;
    MPKeyEvent *event=[MPKeyEvent new];event.type=type;event.window=window;event.modifierFlags=currentModifiers;
    event.locationInWindow=mp_game_appkit_points?CGPointMake(location.x,window.contentView.bounds.size.height-location.y):location;event.deltaX=delta.x;event.deltaY=delta.y;
    lastPointer=@{@"point":NSStringFromCGPoint(location),@"view_frame":NSStringFromCGRect(window.contentView.frame),@"view_bounds":NSStringFromCGRect(window.contentView.bounds),@"window_frame":NSStringFromCGRect(window.frame)};
    event.buttonNumber=(type==3 || type==4 || type==7)?1:0;event.clickCount=1;event.timestamp=NSProcessInfo.processInfo.systemUptime;
    pointerDelivered++;mp_game_post(event);
}
BOOL mp_game_touch_scroll,mp_game_appkit_points;
// Pointer event at the cursor's current position, moved by delta: for controls
// that have no screen position of their own (buttons, camera-look pads).
void mp_game_pointer_here(NSUInteger type,CGPoint delta) {
    CGPoint at=virtualCursorValid?virtualCursor:lastPointerLocation;
    if(mouseAssociated){
        UIView *content=mp_game_key_window().contentView;CGSize size=content?content.bounds.size:UIScreen.mainScreen.bounds.size;
        at=CGPointMake(MIN(MAX(at.x+delta.x,0),size.width-1),MIN(MAX(at.y+delta.y,0),size.height-1));
        virtualCursor=at;virtualCursorValid=YES;
    }
    mp_game_pointer(type,at,delta);
}
// Absolute pointer for a guest in relative mode (cursor detached): the guest
// moves its own cursor by event deltas from where it last warped it, so send
// exactly the motion that puts that cursor under the finger.
void mp_game_pointer_to(NSUInteger type,CGPoint p) {
    CGPoint delta=CGPointZero;
    if(!mouseAssociated && virtualCursorValid){delta=CGPointMake(p.x-virtualCursor.x,p.y-virtualCursor.y);virtualCursor=p;}
    mp_game_pointer(type,p,delta);
}
// NSEventTypeScrollWheel (22) with precise (trackpad-style) deltas in points.
void mp_game_scroll(CGPoint location,CGPoint delta) {
    MPGameWindow *window=mp_game_key_window();if(!window)return;
    // Wheel lines, not trackpad pixels: one line per 6 points of finger travel
    // (the game scales precise deltas far down). Remainders carry over.
    static CGFloat accX,accY;const CGFloat pointsPerLine=6;
    accX+=delta.x/pointsPerLine;accY+=delta.y/pointsPerLine;
    delta=CGPointMake(trunc(accX),trunc(accY));accX-=delta.x;accY-=delta.y;
    if(delta.x==0 && delta.y==0)return;
    MPKeyEvent *event=[MPKeyEvent new];event.type=22;event.window=window;event.modifierFlags=currentModifiers;
    event.locationInWindow=mp_game_appkit_points?CGPointMake(location.x,window.contentView.bounds.size.height-location.y):location;event.deltaX=delta.x;event.deltaY=delta.y;event.timestamp=NSProcessInfo.processInfo.systemUptime;
    pointerDelivered++;mp_game_post(event);
}
NSDictionary *mp_game_input_stats(void){return @{@"cursor_hidden":@(mp_game_cursor_hidden()),@"delivered":@(delivered),@"pointer_delivered":@(pointerDelivered),@"last_pointer":lastPointer?:@{},@"held":held.allObjects?:@[]};}
@interface MPInputController ()
@property(nonatomic,strong) UIStackView *virtualKeys;
@end
@implementation MPInputController
- (BOOL)prefersStatusBarHidden {return YES;}
- (BOOL)prefersPointerLocked {return !mouseAssociated;}
- (BOOL)canBecomeFirstResponder {return YES;}
- (void)installControls {
    pointerController=self;
    // Generic virtual keys; labels and scan codes describe a keyboard, not game actions.
    NSArray *rows=@[@[@[@"Enter",@36,@"\r"],@[@"Esc",@53,@"\x1b"],@[@"Space",@49,@" "]],
      @[@[@"←",@123,@""],@[@"↑",@126,@""],@[@"↓",@125,@""],@[@"→",@124,@""]],
      @[@[@"W",@13,@"w"],@[@"A",@0,@"a"],@[@"S",@1,@"s"],@[@"D",@2,@"d"]],
      @[@[@"I",@34,@"i"],@[@"E",@14,@"e"],@[@"B",@11,@"b"],@[@"V",@9,@"v"]]];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=4;stack.translatesAutoresizingMaskIntoConstraints=NO;
    self.virtualKeys=stack;
    [self.view addSubview:stack];[NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-8],[stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]]];
    for(NSArray *row in rows){UIStackView *line=[UIStackView new];line.distribution=UIStackViewDistributionFillEqually;line.spacing=4;[stack addArrangedSubview:line];[line.heightAnchor constraintEqualToConstant:40].active=YES;
        for(NSArray *key in row){UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:key[0] forState:UIControlStateNormal];button.tag=[key[1] integerValue];button.accessibilityValue=key[2];button.accessibilityIdentifier=[@"key-" stringByAppendingString:key[0]];button.backgroundColor=UIColor.secondarySystemBackgroundColor;
            [button addTarget:self action:@selector(down:) forControlEvents:UIControlEventTouchDown];[button addTarget:self action:@selector(up:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];[line addArrangedSubview:button];}}
    UIButton *toggle=[UIButton buttonWithType:UIButtonTypeSystem];
    [toggle setTitle:@"Hide keys" forState:UIControlStateNormal];toggle.accessibilityIdentifier=@"toggle-virtual-keys";
    toggle.backgroundColor=UIColor.secondarySystemBackgroundColor;toggle.translatesAutoresizingMaskIntoConstraints=NO;
    [toggle addTarget:self action:@selector(toggleKeys:) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:toggle];
    [NSLayoutConstraint activateConstraints:@[[toggle.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8],
        [toggle.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:52],
        [toggle.widthAnchor constraintEqualToConstant:92],[toggle.heightAnchor constraintEqualToConstant:36]]];
    UIButton *mouse=[UIButton buttonWithType:UIButtonTypeSystem];[mouse setTitle:@"Click: left" forState:UIControlStateNormal];
    mouse.accessibilityIdentifier=@"toggle-mouse-button";mouse.backgroundColor=UIColor.secondarySystemBackgroundColor;mouse.translatesAutoresizingMaskIntoConstraints=NO;
    [mouse addTarget:self action:@selector(toggleMouse:) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:mouse];
    [NSLayoutConstraint activateConstraints:@[[mouse.leadingAnchor constraintEqualToAnchor:toggle.leadingAnchor],[mouse.topAnchor constraintEqualToAnchor:toggle.bottomAnchor constant:4],
        [mouse.widthAnchor constraintEqualToConstant:92],[mouse.heightAnchor constraintEqualToConstant:36]]];
    [self.view addGestureRecognizer:[[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(hover:)]];
    [self becomeFirstResponder];
}
- (void)toggleMouse:(UIButton *)button {secondaryTouch=!secondaryTouch;[button setTitle:secondaryTouch?@"Click: right":@"Click: left" forState:UIControlStateNormal];}
- (void)toggleKeys:(UIButton *)button {
    // Release any held virtual buttons before removing their touch targets.
    for(UIStackView *row in self.virtualKeys.arrangedSubviews)for(UIButton *key in row.arrangedSubviews)
        if([held containsObject:@(key.tag)])[self up:key];
    self.virtualKeys.hidden=!self.virtualKeys.hidden;
    [button setTitle:self.virtualKeys.hidden?@"Show keys":@"Hide keys" forState:UIControlStateNormal];
}
- (void)hover:(UIHoverGestureRecognizer *)recognizer {
    static CGPoint previous;
    UIView *content=mp_game_key_window().contentView;if(!content)return;
    if(recognizer.state==UIGestureRecognizerStateEnded || recognizer.state==UIGestureRecognizerStateCancelled) {
        mp_game_update_tracking(content,CGPointMake(-CGFLOAT_MAX,-CGFLOAT_MAX));return;
    }
    CGPoint point=[recognizer locationInView:self.view];
    UIView *hit=[self.view hitTest:point withEvent:nil];if(![hit isDescendantOfView:content])return;
    CGPoint p=mp_game_point_for_view(content,[recognizer locationInView:content]);
    CGPoint delta=recognizer.state==UIGestureRecognizerStateBegan?CGPointZero:CGPointMake(p.x-previous.x,p.y-previous.y);
    previous=p;
    if(recognizer.state==UIGestureRecognizerStateBegan || recognizer.state==UIGestureRecognizerStateChanged)mp_game_pointer(5,p,delta);
}
- (void)down:(UIButton *)button {mp_game_key((unsigned short)button.tag,button.accessibilityValue,YES,0);}
- (void)up:(UIButton *)button {mp_game_key((unsigned short)button.tag,button.accessibilityValue,NO,0);}
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {[self forward:presses down:YES];}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {[self forward:presses down:NO];}
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {[self forward:presses down:NO];}
- (void)forward:(NSSet<UIPress *> *)presses down:(BOOL)down {
    for(UIPress *press in presses){UIKey *key=press.key;if(!key)continue;
        unsigned short code=mp_mac_keycode(key.keyCode);if(code==65535)continue;
        if(mp_is_modifier_keycode(code))mp_game_modifier(code,down,key.modifierFlags);
        else mp_game_key(code,key.characters.length?key.characters:key.charactersIgnoringModifiers,down,key.modifierFlags);
    }
}
@end
