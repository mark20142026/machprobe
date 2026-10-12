#import "UIKitMinimal.h"

@interface TinyDelegate : NSObject
@property(nonatomic, strong) UIWindow *window;
@end
@implementation TinyDelegate
- (BOOL)application:(id)application didFinishLaunchingWithOptions:(id)options {
    (void)application; (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [[UIViewController alloc] init];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(30, 80, 600, 120)];
    label.numberOfLines = 3;
    label.text = [NSString stringWithFormat:@"Hello from iOS ARM64\niOS app on Mac: %@",
                  NSProcessInfo.processInfo.isiOSAppOnMac ? @"YES" : @"NO"];
    [controller.view addSubview:label];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(TinyDelegate.class)); }
}
