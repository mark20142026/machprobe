#import <UIKit/UIKit.h>
@interface MetalGuestView : UIView
@property(copy) void (^inputObserved)(void);
- (void)renderGuest;
- (NSDictionary *)verifyRenderer;
@end
