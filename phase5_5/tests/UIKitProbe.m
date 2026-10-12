#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "AppKitCompat.h"
#import "Window.h"
#import "Input.h"
#import "Lifecycle.h"
extern void *mp_display_symbol(const char *);
@interface MPProbeResponder:UIView
@property NSUInteger keys,pointers;
@property NSUInteger rightDown,rightUp,rightDrag;
@property NSInteger lastButton;
@property NSUInteger entered,exited;
@property void *trackingData;
@end
@implementation MPProbeResponder
- (BOOL)isFlipped {return YES;}
- (BOOL)acceptsFirstResponder {return YES;}
- (void)keyDown:(id)event {self.keys++;}
- (void)mouseDown:(id)event {self.pointers++;}
- (void)rightMouseDown:(MPKeyEvent *)event {self.rightDown++;self.lastButton=event.buttonNumber;}
- (void)rightMouseUp:(MPKeyEvent *)event {self.rightUp++;self.lastButton=event.buttonNumber;}
- (void)rightMouseDragged:(MPKeyEvent *)event {self.rightDrag++;self.lastButton=event.buttonNumber;}
- (void)mouseEntered:(MPKeyEvent *)event {self.entered++;self.trackingData=event.userData;}
- (void)mouseExited:(id)event {self.exited++;}
@end
NSDictionary *mp_uikit_probe(void) {
    NSMutableDictionary *checks=[NSMutableDictionary new];
    CFUUIDRef (*displayUUID)(uint32_t)=mp_display_symbol("_CGDisplayCreateUUIDFromDisplayID");
    uint32_t (*displayID)(CFUUIDRef)=mp_display_symbol("_CGDisplayGetDisplayIDFromUUID");
    CFUUIDRef first=displayUUID(1),second=displayUUID(1),unknown=CFUUIDCreate(NULL);
    checks[@"display_identity_roundtrip"]=@(first && second && CFEqual(first,second) && displayID(first)==1 && displayID(second)==1);
    checks[@"unknown_display_rejected"]=@(displayUUID(999)==NULL && displayID(unknown)==0 && displayID(NULL)==0);
    CFRelease(first);CFRelease(second);CFRelease(unknown);
    CFTypeRef (*copyMode)(uint32_t)=mp_display_symbol("_CGDisplayCopyDisplayMode");
    CFArrayRef (*copyModes)(uint32_t,CFDictionaryRef)=mp_display_symbol("_CGDisplayCopyAllDisplayModes");
    size_t (*modeWidth)(CFTypeRef)=mp_display_symbol("_CGDisplayModeGetPixelWidth");
    size_t (*modeHeight)(CFTypeRef)=mp_display_symbol("_CGDisplayModeGetPixelHeight");
    double (*modeRate)(CFTypeRef)=mp_display_symbol("_CGDisplayModeGetRefreshRate");
    CFTypeRef (*retainMode)(CFTypeRef)=mp_display_symbol("_CGDisplayModeRetain");
    void (*releaseMode)(CFTypeRef)=mp_display_symbol("_CGDisplayModeRelease");
    CFStringRef (*modeEncoding)(CFTypeRef)=mp_display_symbol("_CGDisplayModeCopyPixelEncoding");
    CFArrayRef modes=copyModes(1,NULL);CFTypeRef mode=retainMode(CFArrayGetValueAtIndex(modes,0));
    checks[@"single_current_display_mode"]=@(CFArrayGetCount(modes)==1);CFRelease(modes);
    checks[@"retained_mode_dimensions"]=@(modeWidth(mode)==(size_t)UIScreen.mainScreen.currentMode.size.width && modeHeight(mode)==(size_t)UIScreen.mainScreen.currentMode.size.height);
    checks[@"nominal_display_rate"]=@(modeRate(mode)==UIScreen.mainScreen.maximumFramesPerSecond && modeRate(mode)>0);
    CFStringRef encoding=modeEncoding(mode);checks[@"display_pixel_encoding"]=@(CFEqual(encoding,CFSTR("--------RRRRRRRRGGGGGGGGBBBBBBBB")));CFRelease(encoding);releaseMode(mode);
    checks[@"invalid_display_mode_rejected"]=@(copyMode(999)==NULL && copyModes(999,NULL)==NULL && modeWidth(NULL)==0 && retainMode(NULL)==NULL);
    releaseMode(NULL);
    Class viewClass=(__bridge Class)mp_game_appkit_symbol("_OBJC_CLASS_$_NSView");
    UIView *view=[[viewClass alloc] initWithFrame:CGRectMake(0,0,80,60)];
    __block unsigned notifications=0;
    id token=[NSNotificationCenter.defaultCenter addObserverForName:@"NSViewFrameDidChangeNotification" object:view queue:nil usingBlock:^(NSNotification *n){notifications++;}];
    ((void(*)(id,SEL,BOOL))objc_msgSend)(view,NSSelectorFromString(@"setPostsFrameChangedNotifications:"),YES);
    view.frame=CGRectMake(0,0,90,70);view.frame=CGRectMake(0,0,90,70);
    checks[@"one_notification_per_frame_change"]=@(notifications==1);
    ((void(*)(id,SEL,BOOL))objc_msgSend)(view,NSSelectorFromString(@"setPostsFrameChangedNotifications:"),NO);
    view.frame=CGRectMake(0,0,100,80);checks[@"disabled_notification"]=@(notifications==1);
    [NSNotificationCenter.defaultCenter removeObserver:token];
    ((void(*)(id,SEL,BOOL))objc_msgSend)(view,NSSelectorFromString(@"setWantsBestResolutionOpenGLSurface:"),YES);
    checks[@"screen_scale"]=@(view.contentScaleFactor==UIScreen.mainScreen.scale);
    id context=((id(*)(id,SEL))objc_msgSend)(view,NSSelectorFromString(@"inputContext"));
    checks[@"context_owns_correct_client"]=@([context valueForKey:@"client"]==view);
    checks[@"stable_context"]=@(context==((id(*)(id,SEL))objc_msgSend)(view,NSSelectorFromString(@"inputContext")));
    MPGameWindow *window=[[MPGameWindow alloc] initWithContentRect:view.frame styleMask:0 backing:2 defer:NO];
    MPProbeResponder *responder=[MPProbeResponder new];window.contentView=responder;window.initialFirstResponder=responder;
    responder.bounds=CGRectMake(0,0,100,80);
    checks[@"flipped_pointer_coordinates"]=@(CGPointEqualToPoint(mp_game_point_for_view(responder,CGPointMake(20,30)),CGPointMake(20,30)));
    checks[@"unflipped_pointer_coordinates"]=@(CGPointEqualToPoint(mp_game_point_for_view(view,CGPointMake(20,30)),CGPointMake(20,50)));
    [window makeKeyAndOrderFront:nil];checks[@"initial_responder"]=@(window.firstResponder==responder);
    mp_game_key(13,@"w",YES,0);mp_game_key(13,@"w",NO,0);mp_game_pointer(1,CGPointMake(3,4),CGPointZero);
    checks[@"input_reaches_responder"]=@(responder.keys==1 && responder.pointers==1);
    checks[@"released_key_state"]=@([mp_game_input_stats()[@"held"] count]==0);
    mp_game_pointer(3,CGPointMake(3,4),CGPointZero);mp_game_pointer(7,CGPointMake(4,5),CGPointMake(1,1));mp_game_pointer(4,CGPointMake(4,5),CGPointZero);
    checks[@"secondary_mouse_events"]=@(responder.rightDown==1 && responder.rightUp==1 && responder.rightDrag==1 && responder.lastButton==1);
    int cookie=42;
    NSInteger tag=((NSInteger(*)(id,SEL,CGRect,id,void *,BOOL))objc_msgSend)(view,NSSelectorFromString(@"addTrackingRect:owner:userData:assumeInside:"),CGRectMake(0,0,20,20),responder,&cookie,NO);
    mp_game_update_tracking(view,CGPointMake(2,3));mp_game_update_tracking(view,CGPointMake(4,5));mp_game_update_tracking(view,CGPointMake(40,50));
    checks[@"tracking_enter_exit"]=@(responder.entered==1 && responder.exited==1);
    checks[@"tracking_userdata"]=@(responder.trackingData==&cookie);
    ((void(*)(id,SEL,NSInteger))objc_msgSend)(view,NSSelectorFromString(@"removeTrackingRect:"),tag);
    mp_game_update_tracking(view,CGPointMake(2,3));checks[@"tracking_removal"]=@(responder.entered==1);
    NSArray *types=@[@"public.file-url"];[window registerForDraggedTypes:types];checks[@"drag_registration"]=@([window.registeredDraggedTypes isEqual:types]);
    [window unregisterDraggedTypes];checks[@"drag_unregistration"]=@(window.registeredDraggedTypes.count==0);
    CGRect rect=CGRectMake(4,5,60,70);CGRect content=((CGRect(*)(id,SEL,CGRect))objc_msgSend)(window,NSSelectorFromString(@"contentRectForFrameRect:"),rect);
    checks[@"borderless_geometry"]=@(CGRectEqualToRect(rect,content));
    MPKeyEvent *event=[MPKeyEvent new];event.keyCode=13;event.characters=@"w";event.locationInWindow=CGPointMake(8,9);event.deltaX=2;event.userData=&cookie;
    MPKeyEvent *copy=[event copy];event.characters=@"x";
    checks[@"event_copy_snapshot"]=@(copy!=event && copy.keyCode==13 && [copy.characters isEqual:@"w"] && copy.deltaX==2 && copy.userData==&cookie && CGPointEqualToPoint(copy.locationInWindow,CGPointMake(8,9)));
    checks[@"window_registry"]=@([mp_game_windows() containsObject:window]);
    mp_game_warp_cursor(CGPointMake(40,50));mp_game_associate_mouse(0);
    mp_game_pointer(1,CGPointMake(2,3),CGPointMake(7,8));
    checks[@"detached_cursor_position"]=@([mp_game_input_stats()[@"last_pointer"][@"point"] isEqual:NSStringFromCGPoint(CGPointMake(40,50))]);
    mp_game_associate_mouse(1);mp_game_pointer(1,CGPointMake(2,3),CGPointZero);
    checks[@"associated_cursor_position"]=@([mp_game_input_stats()[@"last_pointer"][@"point"] isEqual:NSStringFromCGPoint(CGPointMake(2,3))]);
    checks[@"invalid_cursor_warp"]=@(mp_game_warp_cursor(CGPointMake(NAN,0))!=0);
    id cursor=[(__bridge Class)mp_game_appkit_symbol("_OBJC_CLASS_$_NSCursor") performSelector:NSSelectorFromString(@"arrowCursor")];
    ((void(*)(id,SEL,CGRect,id))objc_msgSend)(view,NSSelectorFromString(@"addCursorRect:cursor:"),view.bounds,cursor);
    checks[@"cursor_rect_registration"]=@([[view valueForKey:@"guestCursorRects"] count]==1);
    ((void(*)(id,SEL))objc_msgSend)(view,NSSelectorFromString(@"discardCursorRects"));
    checks[@"cursor_rect_discard"]=@([[view valueForKey:@"guestCursorRects"] count]==0);
    [window close];checks[@"window_cleanup"]=@(window.contentView==nil && window.firstResponder==nil);
    BOOL passed=YES;for(NSNumber *value in checks.allValues)passed=passed&&value.boolValue;
    return @{@"passed":@(passed),@"checks":checks};
}
