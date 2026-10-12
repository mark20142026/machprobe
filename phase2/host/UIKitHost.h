#pragma once
#if __has_include(<UIKit/UIKit.h>) && !defined(MP_MINIMAL_UIKIT)
#import <UIKit/UIKit.h>
#else
#import "../../experiments/inprocess-hello/HarnessUIKit.h"
@interface UIControl : UIView
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events;
@end
@interface UIButton : UIControl
+ (instancetype)buttonWithType:(NSInteger)type;
- (void)setTitle:(NSString *)title forState:(NSUInteger)state;
@end
#endif
