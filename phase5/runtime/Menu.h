#import <UIKit/UIKit.h>
@class MPGameMenu;
@interface MPGameMenuItem:NSObject
@property(copy) NSString *title,*keyEquivalent;
@property(nonatomic) SEL action;
@property(nonatomic,weak) id target;
@property(nonatomic,strong) MPGameMenu *submenu;
@property NSUInteger keyEquivalentModifierMask;
@property BOOL enabled,separatorItem;
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key;
+ (instancetype)separatorItem;
@end
@interface MPGameMenu:NSObject
@property(copy) NSString *title;
@property(nonatomic,strong,readonly) NSMutableArray<MPGameMenuItem *> *itemArray;
- (instancetype)initWithTitle:(NSString *)title;
- (void)addItem:(MPGameMenuItem *)item;
- (MPGameMenuItem *)addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key;
- (UIMenu *)hostMenu;
@end
