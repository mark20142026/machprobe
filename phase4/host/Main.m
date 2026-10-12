#import "Probe.h"
#import <UIKit/UIKit.h>
@interface Scene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation Scene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session;(void)options;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *view=[UIViewController new];self.window.rootViewController=view;[self.window makeKeyAndVisible];
    UITextView *text=[[UITextView alloc] initWithFrame:view.view.bounds];text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;text.editable=NO;text.font=[UIFont systemFontOfSize:18];[view.view addSubview:text];
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSDictionary *report=MPProbe(NSBundle.mainBundle.resourcePath,documents,YES);
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
    [data writeToFile:[documents stringByAppendingPathComponent:@"probe.json"] atomically:YES];
    text.text=[NSString stringWithFormat:@"Phase 4 binary diagnostics\n\nDashboardCalculator has NOT launched.\n\nARM64 load: %@\n\nStrong imports unavailable in host: %@\n\nThis is the diagnostic host, not a replacement calculator.",report[@"loader"][@"arm64"][@"error"],report[@"missing_strong"]];
}
@end
@interface App : UIResponder <UIApplicationDelegate>
@end
@implementation App
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app;(void)options;UISceneConfiguration *c=[[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];c.delegateClass=Scene.class;return c;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class));}}
