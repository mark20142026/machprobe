#import "AppKitBridge.h"
#import <objc/message.h>

static void (^invalidate)(void);
static void changed(void) { if(invalidate)invalidate(); }
void mp_gui_set_invalidation(void (^callback)(void)) { invalidate=[callback copy]; }

@interface MPNSView : NSObject
@property CGRect frame;
@property(strong) NSMutableArray<MPNSView *> *children;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(MPNSView *)view;
@end
@implementation MPNSView
- (instancetype)initWithFrame:(CGRect)frame { if((self=[super init])){_frame=frame;_children=[NSMutableArray array];}return self; }
- (void)addSubview:(MPNSView *)view { [self.children addObject:view];changed(); }
@end

@interface MPNSButton : MPNSView
@property(copy) NSString *title;
@property NSInteger tag;
@property(weak) id target;
@property SEL action;
- (void)setBezelStyle:(NSUInteger)style;
@end
@implementation MPNSButton
- (void)setBezelStyle:(NSUInteger)style { (void)style; }
@end

@interface MPNSTextField : MPNSView
@property(nonatomic,copy) NSString *stringValue;
- (void)setEditable:(BOOL)value;
- (void)setBezeled:(BOOL)value;
- (void)setDrawsBackground:(BOOL)value;
@end
@implementation MPNSTextField
- (void)setStringValue:(NSString *)value { _stringValue=[value copy];changed(); }
- (void)setEditable:(BOOL)value { (void)value; }
- (void)setBezeled:(BOOL)value { (void)value; }
- (void)setDrawsBackground:(BOOL)value { (void)value; }
@end

@interface MPNSWindow : NSObject
@property(strong) MPNSView *contentView;
@property(copy) NSString *title;
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)style backing:(NSUInteger)backing defer:(BOOL)defer;
- (void)setReleasedWhenClosed:(BOOL)value;
- (void)center;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)close;
@end
static MPNSWindow *visibleWindow;
@implementation MPNSWindow
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)style backing:(NSUInteger)backing defer:(BOOL)defer {
    (void)style;(void)backing;(void)defer;
    if((self=[super init]))self.contentView=[[MPNSView alloc] initWithFrame:(CGRect){CGPointZero,rect.size}];return self;
}
- (void)setReleasedWhenClosed:(BOOL)value { (void)value; }
- (void)center {}
- (void)makeKeyAndOrderFront:(id)sender { (void)sender;visibleWindow=self;changed(); }
- (void)close { if(visibleWindow==self)visibleWindow=nil;changed(); }
@end

@interface MPNSApplication : NSObject
+ (instancetype)sharedApplication;
- (BOOL)setActivationPolicy:(NSInteger)policy;
- (void)activateIgnoringOtherApps:(BOOL)value;
- (void)run;
@end
@implementation MPNSApplication
+ (instancetype)sharedApplication { static MPNSApplication *app;static dispatch_once_t once;dispatch_once(&once,^{app=[self new];});return app; }
- (BOOL)setActivationPolicy:(NSInteger)policy { (void)policy;return YES; }
- (void)activateIgnoringOtherApps:(BOOL)value { (void)value; }
// UIKit already owns the event loop. Returning attaches the guest window to it.
- (void)run {}
@end

void *mp_appkit_resolve(const char *name) {
    if(!strcmp(name,"_OBJC_CLASS_$_NSApplication"))return (__bridge void *)MPNSApplication.class;
    if(!strcmp(name,"_OBJC_CLASS_$_NSWindow"))return (__bridge void *)MPNSWindow.class;
    if(!strcmp(name,"_OBJC_CLASS_$_NSView"))return (__bridge void *)MPNSView.class;
    if(!strcmp(name,"_OBJC_CLASS_$_NSButton"))return (__bridge void *)MPNSButton.class;
    if(!strcmp(name,"_OBJC_CLASS_$_NSTextField"))return (__bridge void *)MPNSTextField.class;
    return NULL;
}
CGSize mp_gui_size(void) { return visibleWindow?visibleWindow.contentView.frame.size:CGSizeMake(340,240); }
static CGRect topLeftRect(CGRect frame) {
    return CGRectMake(frame.origin.x,mp_gui_size().height-CGRectGetMaxY(frame),frame.size.width,frame.size.height);
}
NSArray<NSDictionary *> *mp_gui_draw_list(void) {
    if(!visibleWindow)return @[];
    NSMutableArray *items=[NSMutableArray array];
    [items addObject:@{@"rect":@[@0,@0,@(mp_gui_size().width),@28],@"text":visibleWindow.title?:@"",@"kind":@"title"}];
    for(MPNSView *view in visibleWindow.contentView.children) {
        CGRect r=topLeftRect(view.frame);
        NSString *text=@"",*kind=@"view";
        if([view isKindOfClass:MPNSButton.class]){text=((MPNSButton *)view).title?:@"";kind=@"button";}
        if([view isKindOfClass:MPNSTextField.class]){text=((MPNSTextField *)view).stringValue?:@"";kind=@"label";}
        [items addObject:@{@"rect":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)],@"text":text,@"kind":kind}];
    }
    return items;
}
BOOL mp_gui_touch(CGPoint point) {
    // Hit testing is AppKit compatibility behavior. The target/action method
    // belongs to the guest and computes all application state transitions.
    for(MPNSView *view in [visibleWindow.contentView.children reverseObjectEnumerator]) {
        if(![view isKindOfClass:MPNSButton.class] || !CGRectContainsPoint(topLeftRect(view.frame),point))continue;
        MPNSButton *button=(MPNSButton *)view;
        if(!button.target || !button.action)return NO;
        ((void (*)(id,SEL,id))objc_msgSend)(button.target,button.action,button);
        changed();return YES;
    }
    return NO;
}
