#import "AppKitCompat.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Lifecycle.h"
#import "Menu.h"
#import "Window.h"
#import "Input.h"
#include <string.h>
#include "runtime.h"
// AppKit's NSApp is nil until the first +sharedApplication, so a statically
// compiled subclass (SDLApplication) becomes the shared instance with its
// own overrides. Lifecycle.m's +sharedApplication publishes it here.
__strong id mp_game_nsapp;
// Values measured from the installed macOS AppKit; these are data imports.
static NSString *strings[]={@"ApplicationName",@"Credits",@"NSDeviceRGBColorSpace",@"NSFont",@"NSColor",@"NSImageHintInterpolation",@"NSParagraphStyle",@"NSWindowDidBecomeKeyNotification"};
static const char *names[]={"_NSAboutPanelOptionApplicationName","_NSAboutPanelOptionCredits","_NSDeviceRGBColorSpace","_NSFontAttributeName","_NSForegroundColorAttributeName","_NSImageHintInterpolation","_NSParagraphStyleAttributeName","_NSWindowDidBecomeKeyNotification"};
static CGFloat weights[]={0.40000000596046448,0.23000000417232513,0,0.30000001192092896};
@interface MPGameScreen:NSObject
+ (instancetype)mainScreen;
+ (NSArray *)screens;
- (CGRect)frame;
- (CGRect)visibleFrame;
- (CGFloat)backingScaleFactor;
@end
@implementation MPGameScreen
+ (instancetype)mainScreen {static MPGameScreen *screen;static dispatch_once_t once;dispatch_once(&once,^{screen=[self new];});return screen;}
+ (NSArray *)screens {return @[[self mainScreen]];}
- (CGRect)frame {return UIScreen.mainScreen.bounds;}
- (CGRect)visibleFrame {return self.frame;}
- (CGFloat)backingScaleFactor {return UIScreen.mainScreen.scale;}
- (NSDictionary *)deviceDescription {return @{@"NSScreenNumber":@1};}
@end
// A declared but not yet implemented class can participate in image linking.
// It deliberately raises on every unsupported message, rather than pretending
// that a missing UI operation succeeded. Runtime traces drive its implementation.
static Class declaration(const char *name){
    NSString *className=[@"MPDeclared" stringByAppendingString:@(name)];
    Class cls=objc_getClass(className.UTF8String);if(!cls){cls=objc_allocateClassPair(NSObject.class,className.UTF8String,0);objc_registerClassPair(cls);}return cls;
}
extern const MPExtensions *arena_policy(void);
extern Class mp_game_updater_class(void);
extern void *mp_game_control_class(const char *name);
void *mp_game_appkit_symbol(const char *symbol){
    for(unsigned i=0;i<8;i++)if(!strcmp(symbol,names[i]))return &strings[i];
    const char *weightNames[]={"_NSFontWeightBold","_NSFontWeightMedium","_NSFontWeightRegular","_NSFontWeightSemibold"};
    for(unsigned i=0;i<4;i++)if(!strcmp(symbol,weightNames[i]))return &weights[i];
    if(!strcmp(symbol,"_NSApp"))return &mp_game_nsapp;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSApplication"))return (__bridge void *)MPGameApplication.class;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSRunningApplication"))return (__bridge void *)MPGameRunningApplication.class;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSEvent"))return (__bridge void *)MPKeyEvent.class;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSCursor"))return (__bridge void *)MPGameCursor.class;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSMenu"))return (__bridge void *)MPGameMenu.class;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSMenuItem"))return (__bridge void *)MPGameMenuItem.class;
    if(!strcmp(symbol,"_OBJC_CLASS_$_SPUStandardUpdaterController"))return (__bridge void *)mp_game_updater_class();
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSScreen"))return (__bridge void *)MPGameScreen.class;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSWindow"))return (__bridge void *)MPGameWindow.class;
    if(!strcmp(symbol,"_OBJC_METACLASS_$_NSWindow"))return (__bridge void *)object_getClass(MPGameWindow.class);
    const char *prefix="_OBJC_CLASS_$_";
    if(!strncmp(symbol,prefix,strlen(prefix))){
        void *control=mp_game_control_class(symbol+strlen(prefix));if(control)return control;
        const char *name=symbol+strlen(prefix);Class native=objc_getClass(name);if(native)return (__bridge void *)native;
        const char *declared[]={"NSButton","NSAlert","NSBitmapImageRep","NSBox","NSColor","NSCursor","NSFont","NSGraphicsContext","NSMenu","NSMenuItem","NSRunningApplication","NSSlider","NSStackView","NSTextField","NSView","SPUStandardUpdaterController"};
        for(unsigned i=0;i<sizeof declared/sizeof *declared;i++)if(!strcmp(name,declared[i]))return (__bridge void *)declaration(name);
    }
    return NULL;
}
