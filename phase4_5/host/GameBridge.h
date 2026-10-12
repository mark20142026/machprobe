#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#include "runtime.h"
void arena_attach_surface(UIView *parent);
void arena_key(NSString *characters,BOOL down);
void arena_drag(CGPoint delta);
void arena_clear_input(void);
NSDictionary *arena_bridge_stats(void);
MTKView *arena_surface(void);
const MPExtensions *arena_policy(void);
