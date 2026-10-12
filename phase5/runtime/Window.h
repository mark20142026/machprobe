#import <UIKit/UIKit.h>
@interface MPGameWindow:NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,weak) id delegate,firstResponder,initialFirstResponder;
@property(copy) NSString *title;
@property NSUInteger collectionBehavior,styleMask;
@property BOOL acceptsMouseMovedEvents;
@property(getter=isZoomed) BOOL zoomed;
@property(nonatomic) NSInteger level;
@property CGRect frame;
@property(nonatomic,copy,readonly) NSArray<NSString *> *registeredDraggedTypes;
- (void)registerForDraggedTypes:(NSArray<NSString *> *)types;
- (void)unregisterDraggedTypes;
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)mask backing:(NSUInteger)backing defer:(BOOL)defer;
- (id)screen;
- (void)setReleasedWhenClosed:(BOOL)value;
- (void)setFrame:(CGRect)frame display:(BOOL)display;
- (BOOL)makeFirstResponder:(id)responder;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)center;
- (void)close;
- (void)beginSheet:(MPGameWindow *)sheet completionHandler:(void(^)(NSInteger))completion;
- (void)endSheet:(MPGameWindow *)sheet;
@end
MPGameWindow *mp_game_key_window(void);
NSArray<MPGameWindow *> *mp_game_windows(void);
