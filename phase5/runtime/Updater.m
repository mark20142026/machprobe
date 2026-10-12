#import <Foundation/Foundation.h>
#import "Lifecycle.h"
// Self-updating a desktop .app is outside the iOS container's capabilities.
// Preserve the controller object and expose that limitation; never download,
// replace, or report successful updates. This is not an implementation of Sparkle.
@interface MPUnsupportedUpdater:NSObject
@property(nonatomic,weak) id updaterDelegate,userDriverDelegate;
- (instancetype)initWithStartingUpdater:(BOOL)start updaterDelegate:(id)delegate userDriverDelegate:(id)driver;
- (void)checkForUpdates:(id)sender;
- (BOOL)canCheckForUpdates;
@end
@implementation MPUnsupportedUpdater
- (instancetype)initWithStartingUpdater:(BOOL)start updaterDelegate:(id)delegate userDriverDelegate:(id)driver {
    if((self=[super init])){_updaterDelegate=delegate;_userDriverDelegate=driver;mp_game_trace(@"desktop self-updater unsupported in iOS container; automatic start declined");}return self;
}
- (BOOL)canCheckForUpdates {return NO;}
- (void)checkForUpdates:(id)sender {mp_game_trace(@"desktop update request unavailable in iOS container");}
@end
Class mp_game_updater_class(void){return MPUnsupportedUpdater.class;}
