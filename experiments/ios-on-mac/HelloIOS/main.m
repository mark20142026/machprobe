#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [[UIViewController alloc] init];
    controller.view.backgroundColor = UIColor.systemBackgroundColor;

    UIStackView *labels = [[UIStackView alloc] init];
    labels.axis = UILayoutConstraintAxisVertical;
    labels.alignment = UIStackViewAlignmentCenter;
    labels.spacing = 12;
    labels.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *hello = [[UILabel alloc] init];
    hello.text = @"Hello from iOS ARM64";
    hello.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    UILabel *environment = [[UILabel alloc] init];
    environment.text = [NSString stringWithFormat:@"iOS app on Mac: %@",
                        NSProcessInfo.processInfo.isiOSAppOnMac ? @"YES" : @"NO"];

    [labels addArrangedSubview:hello];
    [labels addArrangedSubview:environment];
    [controller.view addSubview:labels];
    [NSLayoutConstraint activateConstraints:@[
        [labels.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
        [labels.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor],
        [labels.leadingAnchor constraintGreaterThanOrEqualToAnchor:controller.view.leadingAnchor constant:20],
        [labels.trailingAnchor constraintLessThanOrEqualToAnchor:controller.view.trailingAnchor constant:-20],
    ]];

    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
