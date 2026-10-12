#include "Policy.h"
#include "Extended.h"
#include <string.h>
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
extern const MPExtensions *arena_policy(void);
extern void *mp_game_appkit_symbol(const char *symbol);
extern void *mp_game_metal_device(void);
extern void *mp_game_audio_engine_class(void);
#endif
static int allowed(const char *name) {
    if(mp_extended_policy()->library_allowed(name))return 1;
    static const char *extra[]={"/System/Library/Frameworks/Cocoa.framework/Versions/A/Cocoa","/System/Library/Frameworks/MetalKit.framework/Versions/A/MetalKit","/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore","/System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation","/System/Library/Frameworks/AVFAudio.framework/Versions/A/AVFAudio","/System/Library/Frameworks/GameController.framework/Versions/A/GameController","/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics","/System/Library/Frameworks/CoreText.framework/Versions/A/CoreText","@rpath/Sparkle.framework/Versions/B/Sparkle"};
    for(unsigned i=0;i<sizeof extra/sizeof *extra;i++)if(!strcmp(name,extra[i]))return 1;
    return 0;
}
static void *resolve(const char *library,const char *name) {
#if TARGET_OS_IPHONE
    if(strstr(library,"/Metal.framework/") && !strcmp(name,"_MTLCreateSystemDefaultDevice"))return (void *)&mp_game_metal_device;
    if((strstr(library,"/AVFAudio.framework/") || strstr(library,"/AVFoundation.framework/")) && !strcmp(name,"_OBJC_CLASS_$_AVAudioEngine"))return mp_game_audio_engine_class();
    if(strstr(library,"/AppKit.framework/") || strstr(library,"/Cocoa.framework/") || strstr(library,"Sparkle.framework/")) {
        void *result=mp_game_appkit_symbol(name);if(result)return result;
        result=arena_policy()->resolve("/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",name);if(result)return result;
    }
#endif
    return mp_extended_policy()->resolve(library,name);
}
const MPExtensions *game_policy(void) {
    static MPExtensions policy;policy=*mp_extended_policy();policy.allow_chained_fixups=1;policy.library_allowed=allowed;policy.resolve=resolve;return &policy;
}
