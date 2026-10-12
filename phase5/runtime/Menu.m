#import "Menu.h"
#import "Lifecycle.h"
#import <objc/message.h>
@implementation MPGameMenuItem
- (instancetype)init {return [self initWithTitle:@"" action:NULL keyEquivalent:@""];}
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key {
    if((self=[super init])){_title=[title copy];_action=action;_keyEquivalent=[key copy];_enabled=YES;_keyEquivalentModifierMask=1UL<<20;}return self;
}
+ (instancetype)separatorItem {MPGameMenuItem *item=[self new];item.separatorItem=YES;return item;}
@end
@implementation MPGameMenu
- (instancetype)init {return [self initWithTitle:@""];}
- (instancetype)initWithTitle:(NSString *)title {if((self=[super init])){_title=[title copy];_itemArray=[NSMutableArray new];}return self;}
- (void)addItem:(MPGameMenuItem *)item {if(item)[_itemArray addObject:item];}
- (MPGameMenuItem *)addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key {
    MPGameMenuItem *item=[[MPGameMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];[self addItem:item];return item;
}
- (UIMenu *)hostMenu {
    NSMutableArray *children=[NSMutableArray new];
    for(MPGameMenuItem *item in self.itemArray) {
        if(item.separatorItem)continue;
        if(item.submenu){[children addObject:[item.submenu hostMenu]];continue;}
        UIAction *action=[UIAction actionWithTitle:item.title image:nil identifier:nil handler:^(UIAction *a){
            id target=item.target;
            if(!target){MPGameApplication *app=[MPGameApplication sharedApplication];target=[app.delegate respondsToSelector:item.action]?app.delegate:app;}
            if(![target respondsToSelector:item.action]){mp_game_trace([@"unsupported menu action: " stringByAppendingString:NSStringFromSelector(item.action)]);return;}
            mp_game_trace([@"guest menu action: " stringByAppendingString:NSStringFromSelector(item.action)]);
            ((void(*)(id,SEL,id))objc_msgSend)(target,item.action,item);
        }];
        if(!item.enabled)action.attributes=UIMenuElementAttributesDisabled;[children addObject:action];
    }
    return [UIMenu menuWithTitle:self.title children:children];
}
@end
