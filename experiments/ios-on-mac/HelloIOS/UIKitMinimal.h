// Experimental declarations for the small API surface used below, checked against
// installed UIKit headers. This is not an iOS SDK or a general UIKit replacement.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CGGeometry.h>
@interface UIView : NSObject
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
@end
@interface UILabel : UIView
@property(nonatomic, copy) NSString *text;
@property(nonatomic) NSInteger numberOfLines;
@end
@interface UIViewController : NSObject
@property(nonatomic, strong) UIView *view;
@end
@interface UIScreen : NSObject
@property(class, nonatomic, readonly) UIScreen *mainScreen;
@property(nonatomic, readonly) CGRect bounds;
@end
@interface UIWindow : UIView
@property(nonatomic, strong) UIViewController *rootViewController;
- (void)makeKeyAndVisible;
@end
FOUNDATION_EXPORT int UIApplicationMain(int argc, char *argv[], NSString *principalClassName, NSString *delegateClassName);
