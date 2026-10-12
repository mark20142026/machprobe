#import "Window.h"
#import "Lifecycle.h"
#import "AppKitCompat.h"
#import <objc/message.h>
#import "Observe.h"
static __weak MPGameWindow *keyWindow;
static NSHashTable<MPGameWindow *> *windows;
// A single-window guest that never asks to become key (Cyberpunk shows its
// window through NSWindowController) still owns keyboard and pointer input.
MPGameWindow *mp_game_key_window(void){return keyWindow?:windows.allObjects.firstObject;}
NSArray<MPGameWindow *> *mp_game_windows(void){return windows.allObjects?:@[];}
@interface MPGameWindow ()
@property(nonatomic,copy) void(^completion)(NSInteger);
@property(nonatomic,strong) MPGameWindow *sheet;
@property(nonatomic,copy,readwrite) NSArray<NSString *> *registeredDraggedTypes;
@property CGRect frameBeforeFullscreen;
@property BOOL fullscreenTransition;
@end
@implementation MPGameWindow
- (void)invalidateCursorRectsForView:(UIView *)view {
    __weak UIView *weakView=view;
    // AppKit invalidates now and rebuilds later; reentering the guest during
    // its cursor mutation can violate its borrow/initialization invariants.
    dispatch_async(dispatch_get_main_queue(),^{
        id target=weakView;
        for(NSString *name in @[@"discardCursorRects",@"resetCursorRects"]) {
            SEL selector=NSSelectorFromString(name);
            if([target respondsToSelector:selector])((void(*)(id,SEL))objc_msgSend)(target,selector);
        }
    });
}
- (void)registerForDraggedTypes:(NSArray<NSString *> *)types {self.registeredDraggedTypes=types;}
- (void)unregisterDraggedTypes {self.registeredDraggedTypes=@[];}
- (void)setLevel:(NSInteger)level {_level=level;self.contentView.layer.zPosition=level;}
- (void)toggleFullScreen:(id)sender {
    if(self.fullscreenTransition)return;
    self.fullscreenTransition=YES;
    dispatch_async(dispatch_get_main_queue(),^{
        BOOL entering=!(self.styleMask&(1UL<<14));
        NSString *direction=entering?@"Enter":@"Exit";
        for(NSString *timing in @[@"Will",@"Did"]) {
            NSString *name=[NSString stringWithFormat:@"NSWindow%@%@FullScreenNotification",timing,direction];
            SEL selector=NSSelectorFromString([NSString stringWithFormat:@"window%@%@FullScreen:",timing,direction]);
            NSNotification *notification=[NSNotification notificationWithName:name object:self];
            if([self.delegate respondsToSelector:selector])((void(*)(id,SEL,id))objc_msgSend)(self.delegate,selector,notification);
            [NSNotificationCenter.defaultCenter postNotification:notification];
            if([timing isEqual:@"Will"]) {
                if(entering){self.frameBeforeFullscreen=self.frame;self.styleMask|=1UL<<14;[self setFrame:UIScreen.mainScreen.bounds display:YES];}
                else {self.styleMask&=~(1UL<<14);[self setFrame:self.frameBeforeFullscreen display:YES];}
            }
        }
        self.fullscreenTransition=NO;
    });
}
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)mask backing:(NSUInteger)backing defer:(BOOL)defer {
    if((self=[super init])){_frame=rect;_styleMask=mask;if(!windows)windows=[NSHashTable weakObjectsHashTable];[windows addObject:self];mp_game_trace(@"guest window created");}return self;
}
- (void)setReleasedWhenClosed:(BOOL)value {
    // Guest ownership controls this NSObject-backed window. Auto-release-on-close
    // needs a separate ownership contract; never silently over-release it.
    if(value)[NSException raise:NSInvalidArgumentException format:@"automatic window release-on-close unsupported"];
}
- (id)screen {return [(__bridge id)mp_game_appkit_symbol("_OBJC_CLASS_$_NSScreen") performSelector:@selector(mainScreen)];}
- (CGFloat)backingScaleFactor {return UIScreen.mainScreen.scale;}
- (BOOL)isVisible {return self.contentView.window!=nil && !self.contentView.hidden;}
// Guest windows have no host-drawn title bar or border; frame and content
// coordinates coincide inside the UIKit presentation surface.
- (CGRect)contentRectForFrameRect:(CGRect)frame {return frame;}
- (CGRect)frameRectForContentRect:(CGRect)content {return content;}
- (void)setFrame:(CGRect)frame display:(BOOL)display {
    BOOL resized=!CGSizeEqualToSize(_frame.size,frame.size);_frame=frame;
    self.contentView.frame=(CGRect){CGPointZero,frame.size};
    if(display)[self.contentView setNeedsLayout];
    if(resized) {
        NSNotification *notification=[NSNotification notificationWithName:@"NSWindowDidResizeNotification" object:self];
        if([self.delegate respondsToSelector:@selector(windowDidResize:)])
            ((void(*)(id,SEL,id))objc_msgSend)(self.delegate,@selector(windowDidResize:),notification);
        [NSNotificationCenter.defaultCenter postNotification:notification];
        mp_game_trace([@"guest resize delivered: " stringByAppendingString:NSStringFromCGSize(frame.size)]);
    }
}
- (BOOL)makeFirstResponder:(id)responder {
    if(responder && ![responder isKindOfClass:UIResponder.class])return NO;
    SEL accepts=NSSelectorFromString(@"acceptsFirstResponder");
    if(responder && [responder respondsToSelector:accepts] && !((BOOL(*)(id,SEL))objc_msgSend)(responder,accepts))return NO;
    self.firstResponder=responder;return YES;
}
- (void)makeKeyAndOrderFront:(id)sender {
    UIView *parent=mp_game_host_view();
    keyWindow=self;self.contentView.hidden=NO; // Undo any orderOut:.
    [windows addObject:self];
    if(!self.firstResponder && self.initialFirstResponder)[self makeFirstResponder:self.initialFirstResponder];
    if(!parent){mp_game_trace(@"guest window awaiting UIKit scene");return;}
    mp_game_observe_view(self.contentView);
    self.contentView.frame=parent.bounds;self.contentView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [parent addSubview:self.contentView];mp_game_trace([@"guest window presented: " stringByAppendingString:self.title?:@""]);
    [NSNotificationCenter.defaultCenter postNotificationName:@"NSWindowDidBecomeKeyNotification" object:self];
}
- (void)center { /* UIKit's physical scene fixes the outer window position. */ }
- (void)beginSheet:(MPGameWindow *)sheet completionHandler:(void(^)(NSInteger))completion {
    self.sheet=sheet;sheet.completion=completion;keyWindow=sheet;
    UIView *parent=mp_game_host_view(),*content=sheet.contentView;content.backgroundColor=UIColor.systemBackgroundColor;
    CGSize size=sheet.frame.size;CGFloat available=parent.bounds.size.height-parent.safeAreaInsets.top-220;
    CGFloat scale=MIN(1,MIN((parent.bounds.size.width-16)/MAX(size.width,1),available/MAX(size.height,1)));
    content.bounds=(CGRect){CGPointZero,size};content.transform=CGAffineTransformMakeScale(scale,scale);
    content.center=CGPointMake(parent.bounds.size.width/2,parent.safeAreaInsets.top+available/2);[parent addSubview:content];
    mp_game_trace(@"guest sheet presented");
}
- (void)endSheet:(MPGameWindow *)sheet {
    if(sheet!=self.sheet)return;[sheet.contentView removeFromSuperview];keyWindow=self;void(^completion)(NSInteger)=sheet.completion;
    sheet.completion=nil;self.sheet=nil;if(completion)completion(0);mp_game_trace(@"guest sheet closed");
}
- (void)close {[self.contentView removeFromSuperview];self.contentView=nil;self.firstResponder=nil;[windows removeObject:self];if(keyWindow==self)keyWindow=nil;}
@end
