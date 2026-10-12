#pragma once

// Small declaration surface for the layout and typography used by HostMain.m.
// The experiment is compiled without a full iOS SDK or UIKit umbrella header.
#import "../ios-on-mac/HelloIOS/UIKitMinimal.h"

@class UIColor, UIFont;

typedef NS_OPTIONS(NSUInteger, UIViewAutoresizing) {
    UIViewAutoresizingNone = 0,
    UIViewAutoresizingFlexibleWidth = 1 << 1,
    UIViewAutoresizingFlexibleHeight = 1 << 4,
};

@interface UIView (HarnessLayout)
@property(nonatomic) CGRect frame;
@property(nonatomic, readonly) CGRect bounds;
@property(nonatomic) UIViewAutoresizing autoresizingMask;
@property(nonatomic, strong) UIColor *backgroundColor;
@end

@interface UILabel (HarnessStyle)
@property(nonatomic, strong) UIColor *textColor;
@property(nonatomic, strong) UIFont *font;
@end

@interface UIColor : NSObject
@property(class, nonatomic, readonly) UIColor *whiteColor;
@property(class, nonatomic, readonly) UIColor *blackColor;
@property(class, nonatomic, readonly) UIColor *lightGrayColor;
@property(class, nonatomic, readonly) UIColor *darkGrayColor;
@property(class, nonatomic, readonly) UIColor *redColor;
@property(class, nonatomic, readonly) UIColor *yellowColor;
@property(class, nonatomic, readonly) UIColor *greenColor;
@end

@interface UIFont : NSObject
+ (UIFont *)monospacedSystemFontOfSize:(CGFloat)fontSize weight:(CGFloat)weight;
+ (UIFont *)systemFontOfSize:(CGFloat)fontSize;
@end

FOUNDATION_EXPORT const CGFloat UIFontWeightRegular;

@interface UIViewController (HarnessLifecycle)
- (void)viewDidLayoutSubviews;
@end
