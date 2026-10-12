// SuperTuxKart 1.5 group policy: the Phase 5.5 large-game policy plus guest
// dylib members, compiled categories and the exact system dependencies found
// in the preserved release (otool -L of all 19 arm64 slices). Admission of a
// path never manufactures its API on iOS; unsupported calls still fail.
#include "runtime.h"
#include "Extended.h"
#include <string.h>
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
extern void *mp_stk_desktop_symbol(const char *library,const char *symbol);
#endif
extern const MPExtensions *mp_large_game_policy(void);
static int allowed(const char *name) {
    if(mp_large_game_policy()->library_allowed(name))return 1;
    static const char *extra[]={
        "/System/Library/Frameworks/CoreHaptics.framework/Versions/A/CoreHaptics",
        "/System/Library/Frameworks/ForceFeedback.framework/Versions/A/ForceFeedback",
        "/System/Library/Frameworks/IOBluetooth.framework/Versions/A/IOBluetooth",
        "/System/Library/Frameworks/IOSurface.framework/Versions/A/IOSurface",
        "/usr/lib/libresolv.9.dylib",
        "/usr/lib/libsqlite3.dylib"
    };
    for(unsigned i=0;i<sizeof extra/sizeof *extra;i++)if(!strcmp(name,extra[i]))return 1;
    return 0;
}
static void *resolve(const char *library,const char *symbol) {
#if TARGET_OS_IPHONE
    void *desktop=mp_stk_desktop_symbol(library,symbol);if(desktop)return desktop;
#endif
    return mp_large_game_policy()->resolve(library,symbol);
}
const MPExtensions *mp_stk_policy(void) {
    static MPExtensions policy;
    policy=*mp_large_game_policy();
    policy.library_allowed=allowed;policy.resolve=resolve;
    policy.allow_guest_dylibs=1;policy.allow_categories=1;policy.allow_weak_imports=1;
    policy.register_metadata=mp_register_metadata;
    return &policy;
}
