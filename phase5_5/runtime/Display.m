#import <UIKit/UIKit.h>
#include <string.h>
#import "Input.h"
// Public iOS UIScreen objects replace macOS WindowServer display IDs. This
// namespace belongs to the adapter; ID 1 always identifies the primary screen.
static uint32_t main_display(void) {return 1;}
static CGRect display_bounds(uint32_t display) {return display==1?UIScreen.mainScreen.bounds:CGRectZero;}
static CFUUIDRef display_uuid(uint32_t display) {
    if(display!=1)return NULL;
    // Persistent identity for the adapter's primary display, not a hardware ID.
    return CFUUIDCreateFromString(kCFAllocatorDefault,CFSTR("A6548631-60B9-450E-AEA1-01B12D84CA10"));
}
static uint32_t display_from_uuid(CFUUIDRef uuid) {
    if(!uuid || CFGetTypeID(uuid)!=CFUUIDGetTypeID())return 0;
    CFUUIDRef primary=display_uuid(1);BOOL matches=CFEqual(primary,uuid);CFRelease(primary);
    return matches?1:0;
}
// By default the adapter exposes only the current UIKit presentation mode. A
// host may instead list render resolutions (mp_display_set_modes): 1x modes in
// pixels at the panel's aspect ratio, the first being the current mode. The
// guest renders at the chosen size and the layer scales it to the panel.
static NSArray<NSValue *> *customModes;
void mp_display_set_modes(const CGSize *pixels,unsigned count) {
    NSMutableArray *a=[NSMutableArray array];for(unsigned i=0;i<count;i++)[a addObject:[NSValue valueWithCGSize:pixels[i]]];customModes=a;
}
static NSDictionary *mode_for(CGSize px,BOOL logicalPixels) {
    UIScreen *screen=UIScreen.mainScreen;
    NSMutableDictionary *m=[@{@"mp_display_mode":@YES,@"pixel_width":@(px.width),@"pixel_height":@(px.height),@"nominal_rate":@(screen.maximumFramesPerSecond)} mutableCopy];
    if(logicalPixels){m[@"logical_width"]=@(px.width);m[@"logical_height"]=@(px.height);}
    return m;
}
static CFDictionaryRef copy_mode(uint32_t display) {
    if(display!=1)return NULL;
    if(customModes.count)return CFBridgingRetain(mode_for(customModes.firstObject.CGSizeValue,YES));
    return CFBridgingRetain(mode_for(UIScreen.mainScreen.currentMode.size,NO));
}
static CFArrayRef copy_modes(uint32_t display,CFDictionaryRef options) {
    if(display!=1)return NULL;
    NSMutableArray *modes=[NSMutableArray array];
    if(customModes.count)for(NSValue *v in customModes)[modes addObject:mode_for(v.CGSizeValue,YES)];
    else [modes addObject:mode_for(UIScreen.mainScreen.currentMode.size,NO)];
    return CFBridgingRetain(modes);
}
static double mode_value(CFDictionaryRef mode,NSString *key) {
    if(!mode || CFGetTypeID(mode)!=CFDictionaryGetTypeID())return 0;
    NSDictionary *value=(__bridge NSDictionary *)mode;
    return [value[@"mp_display_mode"] boolValue]?[value[key] doubleValue]:0;
}
static size_t mode_width(CFDictionaryRef mode){return (size_t)mode_value(mode,@"pixel_width");}
static size_t mode_height(CFDictionaryRef mode){return (size_t)mode_value(mode,@"pixel_height");}
static double mode_rate(CFDictionaryRef mode){return mode_value(mode,@"nominal_rate");}
static CFTypeRef mode_retain(CFTypeRef mode){return mode?CFRetain(mode):NULL;}
static void mode_release(CFTypeRef mode){if(mode)CFRelease(mode);}
static CFStringRef mode_encoding(CFDictionaryRef mode) {
    if(!mode_width(mode))return NULL;
    // IOGraphicsTypes.h IO32BitDirectPixels describes our 8-bit RGB surface.
    return CFStringCreateCopy(NULL,CFSTR("--------RRRRRRRRGGGGGGGGBBBBBBBB"));
}
void *mp_display_symbol(const char *symbol) {
    if(!strcmp(symbol,"_CGMainDisplayID"))return (void *)&main_display;
    if(!strcmp(symbol,"_CGDisplayBounds"))return (void *)&display_bounds;
    if(!strcmp(symbol,"_CGDisplayCreateUUIDFromDisplayID"))return (void *)&display_uuid;
    if(!strcmp(symbol,"_CGDisplayGetDisplayIDFromUUID"))return (void *)&display_from_uuid;
    if(!strcmp(symbol,"_CGDisplayCopyDisplayMode"))return (void *)&copy_mode;
    if(!strcmp(symbol,"_CGDisplayCopyAllDisplayModes"))return (void *)&copy_modes;
    if(!strcmp(symbol,"_CGDisplayModeGetPixelWidth"))return (void *)&mode_width;
    if(!strcmp(symbol,"_CGDisplayModeGetPixelHeight"))return (void *)&mode_height;
    if(!strcmp(symbol,"_CGDisplayModeGetRefreshRate"))return (void *)&mode_rate;
    if(!strcmp(symbol,"_CGDisplayModeCopyPixelEncoding"))return (void *)&mode_encoding;
    if(!strcmp(symbol,"_CGDisplayModeRetain"))return (void *)&mode_retain;
    if(!strcmp(symbol,"_CGDisplayModeRelease"))return (void *)&mode_release;
    if(!strcmp(symbol,"_CGAssociateMouseAndMouseCursorPosition"))return (void *)&mp_game_associate_mouse;
    if(!strcmp(symbol,"_CGWarpMouseCursorPosition"))return (void *)&mp_game_warp_cursor;
    return NULL;
}
