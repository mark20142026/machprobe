#include "Policy.h"
#include <string.h>
#include <TargetConditionals.h>
extern void *mp_guest_get_class(const char *);
extern void *mp_desktop_constant(const char *,const char *);
extern void *mp_deferred_import(const char *,const char *);
extern void *mp_display_symbol(const char *);
extern void *mp_legacy_copy_metal_devices(void);
extern void *mp_keyboard_symbol(const char *);
extern void *mp_audio_diagnostic_symbol(const char *);
static void *resolve(const char *library,const char *symbol) {
#if TARGET_OS_IPHONE
    if(strstr(library,"/Carbon.framework/") || strstr(library,"/CoreServices.framework/")){void *key=mp_keyboard_symbol(symbol);if(key)return key;}
    if(strstr(library,"/AudioToolbox.framework/") || strstr(library,"/CoreAudio.framework/")){void *audio=mp_audio_diagnostic_symbol(symbol);if(audio)return audio;}
    if(strstr(library,"/Metal.framework/") && !strcmp(symbol,"_MTLCopyAllDevices"))return (void *)&mp_legacy_copy_metal_devices;
    if(strstr(library,"/CoreGraphics.framework/") || strstr(library,"/ColorSync.framework/")){void *display=mp_display_symbol(symbol);if(display)return display;}
    if(strstr(library,"/libobjc.") && !strcmp(symbol,"_objc_getClass"))return (void *)&mp_guest_get_class;
    void *constant=mp_desktop_constant(library,symbol);if(constant)return constant;
    // Explicit compatibility profile baseline, not the iOS OS version.
    // SDK NSApplication.h gives macOS 11.0 AppKit version as 2022.
    static double appkit_version=2022;
    if(strstr(library,"/AppKit.framework/") && !strcmp(symbol,"_NSAppKitVersionNumber"))return &appkit_version;
#endif
    return game_policy()->resolve(library,symbol);
}
// Dependency admission is separate from API compatibility. These paths occur
// in the preserved ARM64 release; admitting one never manufactures its imports.
static int allowed(const char *name) {
    if(game_policy()->library_allowed(name))return 1;
    static const char *extra[]={
        "/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit",
        "/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox",
        "/System/Library/Frameworks/CoreAudio.framework/Versions/A/CoreAudio",
        "/System/Library/Frameworks/SystemConfiguration.framework/Versions/A/SystemConfiguration",
        "/System/Library/Frameworks/Security.framework/Versions/A/Security",
        "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices",
        "/System/Library/Frameworks/CoreVideo.framework/Versions/A/CoreVideo",
        "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon",
        "/usr/lib/libiconv.2.dylib",
        "/System/Library/Frameworks/ColorSync.framework/Versions/A/ColorSync",
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices"
    };
    for(unsigned i=0;i<sizeof extra/sizeof *extra;i++)if(!strcmp(name,extra[i]))return 1;
    return 0;
}
const MPExtensions *mp_large_game_policy(void) {
    static MPExtensions policy;
    policy=*game_policy();policy.max_image_bytes=128u*1024u*1024u;
    policy.max_fixups=1048576;policy.allow_thread_locals=1;policy.allow_weak_coalescing=1;policy.library_allowed=allowed;policy.resolve=resolve;
#if TARGET_OS_IPHONE
    policy.resolve_lazy=mp_deferred_import;
#endif
    return &policy;
}
