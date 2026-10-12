#import <UIKit/UIKit.h>
@interface MPKeyEvent:NSObject<NSCopying>
@property unsigned short keyCode;
@property NSUInteger type,modifierFlags;
@property BOOL isARepeat;
@property(copy) NSString *characters,*charactersIgnoringModifiers;
@property NSTimeInterval timestamp;
@property(nonatomic,weak) id window;
@property CGPoint locationInWindow;
@property CGFloat deltaX,deltaY;
@property NSInteger buttonNumber,clickCount;
@property NSInteger trackingNumber;
@property void *userData;
+ (id)addLocalMonitorForEventsMatchingMask:(unsigned long long)mask handler:(id(^)(id))handler;
+ (void)removeMonitor:(id)token;
@end
@interface MPInputController:UIViewController
- (void)installControls;
@end
@interface MPPhysicalWindow:UIWindow
@property CGPoint pointerLocation;
- (CGPoint)mouseLocationOutsideOfEventStream;
@end
@interface MPGameCursor:NSObject
@property(nonatomic,strong) id image;
@property CGPoint hotSpot;
- (instancetype)initWithImage:(id)image hotSpot:(CGPoint)hotSpot;
+ (void)hide;
+ (void)unhide;
@end
void mp_game_key(unsigned short code,NSString *characters,BOOL down,NSUInteger modifiers);
void mp_game_modifier(unsigned short code,BOOL down,NSUInteger modifiers);
unsigned short mp_mac_keycode(NSUInteger hid);
BOOL mp_is_modifier_keycode(unsigned short code);
NSDictionary *mp_game_input_stats(void);
void mp_game_dispatch_event(MPKeyEvent *event);
void mp_game_pointer(NSUInteger type,CGPoint location,CGPoint delta);
void mp_game_pointer_here(NSUInteger type,CGPoint delta);
// Touch in menus: drag = scroll wheel, tap = click on release (off by default).
extern BOOL mp_game_touch_scroll;
// Deliver locationInWindow in AppKit's bottom-left space for views that do not
// declare isFlipped (Cyberpunk's GameView computes height - y itself).
extern BOOL mp_game_appkit_points;
void mp_game_scroll(CGPoint location,CGPoint delta);
void mp_game_update_tracking(UIView *view,CGPoint point);
CGPoint mp_game_point_for_view(UIView *view,CGPoint point);
int mp_game_associate_mouse(uint32_t connected);
int mp_game_warp_cursor(CGPoint point);
