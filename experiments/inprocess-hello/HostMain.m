#import "HarnessUIKit.h"
#import "loader.h"

@interface LoaderDelegate : NSObject
@property(nonatomic, strong) UIWindow *window;
@end

static UILabel *makeLabel(CGRect frame, NSString *text, UIColor *color, UIFont *font,
                          NSInteger lines) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.textColor = color;
    label.font = font;
    label.numberOfLines = lines;
    return label;
}

@interface GuestController : UIViewController
@property(nonatomic, strong) UILabel *hostTitle;
@property(nonatomic, strong) UIView *guestWindow;
@property(nonatomic, strong) UILabel *windowBar;
@property(nonatomic, strong) UILabel *guestTitle;
@property(nonatomic, strong) UILabel *guestOutput;
@end

@implementation GuestController
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    CGFloat width = MAX(180, MIN(760, size.width - 48));
    CGFloat height = MAX(160, MIN(340, size.height - 120));
    self.hostTitle.frame = CGRectMake(24, 52, size.width - 48, 34);
    self.guestWindow.frame = CGRectMake((size.width - width) / 2,
        MAX(70, (size.height - height) / 2), width, height);
    self.windowBar.frame = CGRectMake(0, 0, width, 42);
    self.guestTitle.frame = CGRectMake(90, 8, width - 108, 26);
    self.guestOutput.frame = CGRectMake(18, 58, width - 36, height - 76);
}
@end

@implementation LoaderDelegate
- (BOOL)application:(id)application didFinishLaunchingWithOptions:(id)options {
    (void)application; (void)options;
    NSString *target = [NSBundle.mainBundle pathForResource:@"hello-macos" ofType:nil];
    MPHelloResult result = {0};
    int status = target ? mp_run_hello(target.fileSystemRepresentation, &result) : -1;

    CGRect bounds = UIScreen.mainScreen.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;
    CGFloat margin = 18;
    CGFloat guestWidth = width > 796 ? 760 : width - 36;
    CGFloat guestHeight = height > 420 ? 340 : height - 140;
    CGFloat guestX = (width - guestWidth) / 2;
    CGFloat guestY = (height - guestHeight) / 2 + 18;

    self.window = [[UIWindow alloc] initWithFrame:bounds];
    GuestController *controller = [[GuestController alloc] init];
    controller.view.backgroundColor = [UIColor lightGrayColor];

    UILabel *hostTitle = makeLabel(CGRectMake(margin, margin, width - margin * 2, 34),
        @"UIKit host", [UIColor blackColor], [UIFont systemFontOfSize:23], 1);
    [controller.view addSubview:hostTitle];

    CGRect guestFrame = CGRectMake(guestX, guestY, guestWidth, guestHeight);
    UIView *guestWindow = [[UIView alloc] initWithFrame:guestFrame];
    guestWindow.backgroundColor = [UIColor blackColor];
    UILabel *windowBar = makeLabel(CGRectMake(0, 0, guestWidth, 42), @"",
        [UIColor lightGrayColor], [UIFont systemFontOfSize:14], 1);
    windowBar.backgroundColor = [UIColor darkGrayColor];
    [guestWindow addSubview:windowBar];
    [guestWindow addSubview:makeLabel(CGRectMake(12, 7, 22, 28), @"●", [UIColor redColor],
        [UIFont systemFontOfSize:14], 1)];
    [guestWindow addSubview:makeLabel(CGRectMake(34, 7, 22, 28), @"●", [UIColor yellowColor],
        [UIFont systemFontOfSize:14], 1)];
    [guestWindow addSubview:makeLabel(CGRectMake(56, 7, 22, 28), @"●", [UIColor greenColor],
        [UIFont systemFontOfSize:14], 1)];
    UILabel *guestTitle = makeLabel(CGRectMake(90, 8, guestWidth - 180, 26),
        @"macOS hello", [UIColor whiteColor], [UIFont systemFontOfSize:14], 1);
    [guestWindow addSubview:guestTitle];

    NSString *guestText = status == 0
        ? [NSString stringWithUTF8String:result.output]
        : (target ? [NSString stringWithFormat:@"Guest load failed: %s", result.error]
                  : @"Guest load failed: bundled macOS executable is missing.");
    UILabel *guestOutput = makeLabel(CGRectMake(18, 58, guestWidth - 36, guestHeight - 76),
        guestText, [UIColor whiteColor], [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightRegular], 0);
    [guestWindow addSubview:guestOutput];
    [controller.view addSubview:guestWindow];

    controller.hostTitle = hostTitle;
    controller.guestWindow = guestWindow;
    controller.windowBar = windowBar;
    controller.guestTitle = guestTitle;
    controller.guestOutput = guestOutput;
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(LoaderDelegate.class)); }
}
