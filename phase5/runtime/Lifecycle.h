#import <UIKit/UIKit.h>
@class MPGameMenu;
@interface MPGameRunningApplication:NSObject
+ (instancetype)currentApplication;
- (BOOL)activateWithOptions:(NSUInteger)options;
@end
@interface MPGameApplication : NSObject
@property(nonatomic,weak) id delegate;
@property(nonatomic,strong) MPGameMenu *mainMenu,*windowsMenu,*servicesMenu;
+ (instancetype)sharedApplication;
- (BOOL)setActivationPolicy:(NSInteger)policy;
- (void)activateIgnoringOtherApps:(BOOL)value;
- (void)run;
- (void)finishLaunching;
- (void)sendEvent:(id)event;
@property(nonatomic,strong) id currentEvent;
@end
void mp_game_trace(NSString *event);
// Input events from UIKit adapters. By default they are dispatched at once
// (-sendEvent:). Guests that drain AppKit's queue themselves (nextEventMatching
// Mask:, then -sendEvent: per event) set mp_game_queue_events: events wait in
// a queue that -nextEventMatchingMask: hands out, as on macOS.
extern BOOL mp_game_queue_events;
void mp_game_post(id event);
UIView *mp_game_host_view(void);
void mp_game_set_launch_hook(void (^hook)(void));
int mp_game_run_uikit(void);
