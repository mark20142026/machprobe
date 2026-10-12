#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Concrete drawing operations from the supported AppKit subset, in top-left
// guest-window coordinates. The Metal presenter consumes these operations.
NSArray<NSDictionary *> *mp_gui_draw_list(void);
CGSize mp_gui_size(void);
BOOL mp_gui_touch(CGPoint point);
void mp_gui_set_invalidation(void (^callback)(void));
void *mp_appkit_resolve(const char *symbol);
