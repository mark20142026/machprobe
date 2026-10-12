#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "AppKitCompat.h"
#import "ImageShim.h"
// Rust/other clients can look classes up by name instead of importing class
// pointers. Apply the same compatibility map to both paths.
Class mp_guest_get_class(const char *name) {
    if(!name || strlen(name)>180)return Nil;
    Class native=objc_getClass(name);if(native)return native;
    char symbol[224];snprintf(symbol,sizeof symbol,"_OBJC_CLASS_$_%s",name);
    void *mapped=mp_game_appkit_symbol(symbol);
    if(!mapped)mapped=mp_ios_shim("/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",symbol);
    return (__bridge Class)mapped;
}
