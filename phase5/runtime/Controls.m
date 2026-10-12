#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "Input.h"
#import "Window.h"
@interface MPTrackingRect:NSObject
@property CGRect rect;
@property(nonatomic,weak) id owner;
@property void *userData;
@property BOOL inside;
@end
@implementation MPTrackingRect
@end
@interface MPGamePasteboard:NSObject
@property(nonatomic,strong) UIPasteboard *native;
@end
@implementation MPGamePasteboard
+ (instancetype)generalPasteboard {
    static MPGamePasteboard *board;static dispatch_once_t once;
    dispatch_once(&once,^{board=[self new];board.native=UIPasteboard.generalPasteboard;});return board;
}
- (NSInteger)changeCount {return self.native.changeCount;}
- (NSInteger)clearContents {self.native.items=@[];return self.changeCount;}
- (NSString *)stringForType:(NSString *)type {
    id value=[self.native valueForPasteboardType:type];
    if([value isKindOfClass:NSString.class])return value;
    return [value isKindOfClass:NSData.class]?[[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding]:nil;
}
- (BOOL)setString:(NSString *)string forType:(NSString *)type {
    if(!string || !type)return NO;[self.native setValue:string forPasteboardType:type];return YES;
}
@end
@interface MPTextInputContext:NSObject
@property(nonatomic,weak) id client;
@end
@implementation MPTextInputContext
- (NSString *)selectedKeyboardInputSource {
    // Identifier for our HID/Unicode adapter, not a claimed installed macOS IME.
    return @"research.machprobe.keyboard.hardware";
}
@end
@interface MPGameView:UIView
@property BOOL postsFrameChangedNotifications;
@property(nonatomic) BOOL wantsBestResolutionOpenGLSurface;
@property(nonatomic,strong) MPTextInputContext *guestInputContext;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,MPTrackingRect *> *guestTrackingRects;
@property NSInteger nextTrackingTag;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *guestCursorRects;
@end
@implementation MPGameView
- (void)addCursorRect:(CGRect)rect cursor:(id)cursor {
    if(!cursor)return;
    if(!self.guestCursorRects)self.guestCursorRects=[NSMutableArray new];
    [self.guestCursorRects addObject:@{@"rect":[NSValue valueWithCGRect:rect],@"cursor":cursor}];
}
- (void)discardCursorRects {[self.guestCursorRects removeAllObjects];}
- (void)resetCursorRects {[self discardCursorRects];}
- (BOOL)isFlipped {return NO;}
- (NSInteger)addTrackingRect:(CGRect)rect owner:(id)owner userData:(void *)data assumeInside:(BOOL)inside {
    if(!self.guestTrackingRects)self.guestTrackingRects=[NSMutableDictionary new];
    MPTrackingRect *entry=[MPTrackingRect new];entry.rect=rect;entry.owner=owner;entry.userData=data;entry.inside=inside;
    NSInteger tag=++self.nextTrackingTag;self.guestTrackingRects[@(tag)]=entry;return tag;
}
- (void)removeTrackingRect:(NSInteger)tag {[self.guestTrackingRects removeObjectForKey:@(tag)];}
- (BOOL)wantsLayer {return YES;}
- (void)setWantsLayer:(BOOL)value {
    // UIView is always layer backed. Opting into AppKit backing needs no new
    // allocation; opting out cannot remove UIKit's required presentation layer.
    if(!value)[NSException raise:NSInvalidArgumentException format:@"unbacked AppKit views unsupported on UIKit"];
}
- (void)setWantsBestResolutionOpenGLSurface:(BOOL)value {
    _wantsBestResolutionOpenGLSurface=value;
    self.contentScaleFactor=value?UIScreen.mainScreen.scale:1;
    self.layer.contentsScale=self.contentScaleFactor;
}
- (id)inputContext {
    if(!self.guestInputContext){self.guestInputContext=[MPTextInputContext new];self.guestInputContext.client=self;}
    return self.guestInputContext;
}
- (void)setFrame:(CGRect)frame {
    CGRect previous=self.frame;[super setFrame:frame];
    if(self.postsFrameChangedNotifications && !CGRectEqualToRect(previous,self.frame))
        [NSNotificationCenter.defaultCenter postNotificationName:@"NSViewFrameDidChangeNotification" object:self];
}
@end
void mp_game_update_tracking(UIView *view,CGPoint point) {
    if(![view isKindOfClass:MPGameView.class])return;
    MPGameView *guest=(MPGameView *)view;
    for(NSDictionary *region in guest.guestCursorRects)if(CGRectContainsPoint([region[@"rect"] CGRectValue],point)) {
        id cursor=region[@"cursor"];SEL set=NSSelectorFromString(@"set");
        if([cursor respondsToSelector:set])((void(*)(id,SEL))objc_msgSend)(cursor,set);
    }
    for(NSNumber *tag in guest.guestTrackingRects.allKeys) {
        MPTrackingRect *entry=guest.guestTrackingRects[tag];BOOL inside=CGRectContainsPoint(entry.rect,point);
        if(inside==entry.inside)continue;entry.inside=inside;
        SEL selector=NSSelectorFromString(inside?@"mouseEntered:":@"mouseExited:");
        id owner=entry.owner;if(![owner respondsToSelector:selector])continue;
        MPKeyEvent *event=[MPKeyEvent new];event.type=inside?8:9;event.trackingNumber=tag.integerValue;event.userData=entry.userData;
        event.locationInWindow=point;event.window=mp_game_key_window();event.timestamp=NSProcessInfo.processInfo.systemUptime;
        ((void(*)(id,SEL,id))objc_msgSend)(owner,selector,event);
    }
}
@interface MPTextField:UILabel
+ (instancetype)labelWithString:(NSString *)text;
+ (instancetype)wrappingLabelWithString:(NSString *)text;
@property(copy) NSString *stringValue;
@end
@implementation MPTextField
+ (instancetype)labelWithString:(NSString *)text {MPTextField *label=[self new];label.text=text;return label;}
+ (instancetype)wrappingLabelWithString:(NSString *)text {MPTextField *label=[self labelWithString:text];label.numberOfLines=0;return label;}
- (NSString *)stringValue {return self.text;}
- (void)setStringValue:(NSString *)text {self.text=text;}
@end
@interface MPButton:UIButton
@property(nonatomic,weak) id target;
@property SEL action;
@property(copy) NSString *title,*keyEquivalent;
@property NSUInteger bezelStyle;
+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action;
@end
@implementation MPButton
+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    MPButton *button=[self buttonWithType:UIButtonTypeSystem];button.title=title;button.target=target;button.action=action;
    [button addTarget:button action:@selector(invoke:) forControlEvents:UIControlEventTouchUpInside];return button;
}
- (NSString *)title {return self.currentTitle;}
- (void)setTitle:(NSString *)title {[self setTitle:title forState:UIControlStateNormal];}
- (void)invoke:(id)sender {if(self.action && [self.target respondsToSelector:self.action])((void(*)(id,SEL,id))objc_msgSend)(self.target,self.action,self);}
@end
@interface MPStackView:UIStackView
@property NSInteger orientation;
+ (instancetype)stackViewWithViews:(NSArray *)views;
@end
@implementation MPStackView
+ (instancetype)stackViewWithViews:(NSArray *)views {return [[self alloc] initWithArrangedSubviews:views];}
- (NSInteger)orientation {return self.axis;}
- (void)setOrientation:(NSInteger)value {self.axis=value;}
- (void)setAlignment:(UIStackViewAlignment)value {
    // NSStackView takes NSLayoutAttribute; UIStackView takes its own enum.
    switch((NSInteger)value){case 1:case 3:case 5:value=UIStackViewAlignmentLeading;break;case 2:case 4:case 6:value=UIStackViewAlignmentTrailing;break;case 9:case 10:value=UIStackViewAlignmentCenter;break;case 11:value=UIStackViewAlignmentFirstBaseline;break;case 12:value=UIStackViewAlignmentLastBaseline;break;default:value=UIStackViewAlignmentFill;break;}
    [super setAlignment:value];
}
@end
@interface MPBox:UIView
@property(nonatomic) NSInteger boxType;
@end
@implementation MPBox
- (void)setBoxType:(NSInteger)value {_boxType=value;self.backgroundColor=UIColor.separatorColor;[self invalidateIntrinsicContentSize];}
- (CGSize)intrinsicContentSize {return self.boxType==2?CGSizeMake(UIViewNoIntrinsicMetric,1):CGSizeMake(UIViewNoIntrinsicMetric,UIViewNoIntrinsicMetric);}
@end
void *mp_game_control_class(const char *name){
    if(!strcmp(name,"NSPasteboard"))return (__bridge void *)MPGamePasteboard.class;
    NSDictionary *classes=@{@"NSTextField":MPTextField.class,@"NSButton":MPButton.class,@"NSStackView":MPStackView.class,@"NSBox":MPBox.class,@"NSView":MPGameView.class,@"NSFont":UIFont.class,@"NSColor":UIColor.class};
    return (__bridge void *)classes[@(name)];
}
