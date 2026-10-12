#import <Metal/Metal.h>
id<MTLDevice> mp_game_metal_device(void);
id<MTLDevice> mp_game_wrap_metal_device(id<MTLDevice> native);
NSDictionary *mp_game_metal_stats(void);
