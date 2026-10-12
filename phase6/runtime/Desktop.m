// Desktop APIs imported by SuperTuxKart 1.5's SDL2 and Wiimote code, found by
// the link-only import probe (evidence/phase6-import-probe). Constant values
// were measured on macOS (docs/evidence/phase6-desktop-constants.txt).
// Display functions model the single iOS screen already exposed by Phase 5.5
// (display ID 1). Operations iOS cannot perform (display capture, mode
// switching, gamma, force feedback, Bluetooth inquiry) fail with the
// framework's own error codes; nothing reports a success it did not achieve.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>
#import "Input.h"
extern void *mp_game_appkit_symbol(const char *symbol);
extern void mp_game_trace(NSString *event);
static void note(const char *what){mp_game_trace([NSString stringWithFormat:@"desktop adapter: %s",what]);}

// ---- Constants --------------------------------------------------------------
static NSString *const notificationNames[]={@"NSApplicationDidBecomeActiveNotification",@"NSBackingPropertyOldScaleFactorKey",
    @"NSWindowDidChangeBackingPropertiesNotification",@"NSWindowDidChangeScreenNotification",@"NSWindowDidChangeScreenProfileNotification",
    @"NSWindowDidDeminiaturizeNotification",@"NSWindowDidEndLiveResizeNotification",@"NSWindowDidEnterFullScreenNotification",
    @"NSWindowDidExitFullScreenNotification",@"NSWindowDidExposeNotification",@"NSWindowDidMiniaturizeNotification",@"NSWindowDidMoveNotification",
    @"NSWindowDidResignKeyNotification",@"NSWindowDidResizeNotification",@"NSWindowWillCloseNotification",@"NSWindowWillEnterFullScreenNotification",
    @"NSWindowWillExitFullScreenNotification",@"NSWindowWillStartLiveResizeNotification"};
static NSString *notificationValues[18];
static CFStringRef showDuplicateModes=CFSTR("kCGDisplayResolution");

// ---- Classes ------------------------------------------------------------------
// macOS Apple Events never arrive on iOS. Registration is recorded so the
// guest's bookkeeping works; no handler is ever invoked.
@interface MPAppleEventManager:NSObject @end
@implementation MPAppleEventManager
+ (instancetype)sharedAppleEventManager {static MPAppleEventManager *shared;static dispatch_once_t once;dispatch_once(&once,^{shared=[self new];});return shared;}
- (void)setEventHandler:(id)handler andSelector:(SEL)selector forEventClass:(uint32_t)eventClass andEventID:(uint32_t)eventID {note("Apple Event handler registered; iOS never delivers Apple Events");}
- (void)removeEventHandlerForEventClass:(uint32_t)eventClass andEventID:(uint32_t)eventID {}
- (id)currentAppleEvent {return nil;}
@end
// No Bluetooth host controller or inquiry is available to the guest on iOS
// (IOBluetooth is macOS-only); factories return nil as when no radio exists.
@interface MPBluetoothHostController:NSObject @end
@implementation MPBluetoothHostController
+ (id)defaultController {note("IOBluetooth host controller unavailable on iOS");return nil;}
@end
@interface MPBluetoothDeviceInquiry:NSObject @end
@implementation MPBluetoothDeviceInquiry
+ (id)inquiryWithDelegate:(id)delegate {note("IOBluetooth device inquiry unavailable on iOS");return nil;}
- (instancetype)initWithDelegate:(id)delegate {return nil;}
@end
static Class declared(const char *name,Class superclass) {
    NSString *className=[@"MPDeclared" stringByAppendingString:@(name)];
    Class cls=objc_getClass(className.UTF8String);
    if(!cls){cls=objc_allocateClassPair(superclass,className.UTF8String,0);objc_registerClassPair(cls);}
    return cls;
}
extern Class mp_stk_appkit_class(const char *name);
static Class desktop_class(const char *name) {
    Class extra=mp_stk_appkit_class(name);if(extra)return extra;
    if(!strcmp(name,"NSResponder"))return UIResponder.class; // NSView already maps to a UIView.
    if(!strcmp(name,"NSAppleEventManager"))return MPAppleEventManager.class;
    if(!strcmp(name,"IOBluetoothHostController"))return MPBluetoothHostController.class;
    if(!strcmp(name,"IOBluetoothDeviceInquiry"))return MPBluetoothDeviceInquiry.class;
    // Declared only: SDL subclasses or references these on paths the Vulkan
    // renderer does not take. Any message to them fails visibly.
    const char *declarations[]={"NSBezierPath"};
    for(unsigned i=0;i<1;i++)if(!strcmp(name,declarations[i]))return declared(name,NSObject.class);
    return Nil;
}

// ---- CoreGraphics display management (single iOS screen, ID 1) ---------------
typedef uint32_t Display;typedef int32_t CGErr;
enum {kErrFailure=1000,kErrCannotComplete=1004};
static CGErr online_displays(uint32_t max,Display *displays,uint32_t *count) {
    if(displays && max>0)displays[0]=1;
    if(count)*count=max>0 || !displays?1:0;
    return 0;
}
static int is_main(Display d){return d==1;}
static Display mirrors(Display d){return 0;} // kCGNullDirectDisplay: no mirroring.
static size_t pixels_wide(Display d){return d==1?(size_t)UIScreen.mainScreen.bounds.size.width:0;}
static size_t pixels_high(Display d){return d==1?(size_t)UIScreen.mainScreen.bounds.size.height:0;}
static CGSize screen_size(Display d){return CGSizeZero;} // Physical size unknown (macOS returns zero without EDID).
static uint32_t io_service_port(Display d){return 0;}     // No IOKit display service on iOS.
static uint32_t gl_display_mask(Display d){return 0;}     // No CGL; the guest renders via Metal/Vulkan.
// The Phase 5.5 single-mode object: width/height in pixels of the current mode.
static size_t mode_dimension(CFTypeRef mode,NSString *key){
    if(!mode || CFGetTypeID(mode)!=CFDictionaryGetTypeID())return 0;
    NSDictionary *m=(__bridge NSDictionary *)mode;return [m[@"mp_display_mode"] boolValue]?[m[key] unsignedLongValue]:0;
}
// CGDisplayModeGetWidth reports points; the iOS current mode is in pixels.
// Host-listed 1x modes carry their logical size (= pixels).
static size_t mode_width(CFTypeRef mode){size_t l=mode_dimension(mode,@"logical_width");if(l)return l;size_t px=mode_dimension(mode,@"pixel_width");return px?(size_t)(px/UIScreen.mainScreen.nativeScale):0;}
static size_t mode_height(CFTypeRef mode){size_t l=mode_dimension(mode,@"logical_height");if(l)return l;size_t px=mode_dimension(mode,@"pixel_height");return px?(size_t)(px/UIScreen.mainScreen.nativeScale):0;}
static uint32_t mode_io_flags(CFTypeRef mode){return mode_dimension(mode,@"pixel_width")?0x3:0;} // kDisplayModeValidFlag|kDisplayModeSafeFlag
static int mode_usable(CFTypeRef mode){return mode_dimension(mode,@"pixel_width")!=0;}
static CGErr set_display_mode(Display d,CFTypeRef mode,CFDictionaryRef options){note("display mode switch refused (iOS owns the display)");return kErrFailure;}
static CGErr capture(Display d){note("display capture refused (iOS owns the display)");return kErrFailure;}
static CGErr capture_all(void){note("display capture refused (iOS owns the display)");return kErrFailure;}
static CGErr release_display(Display d){return 0;}   // Nothing was captured.
static CGErr release_all(void){return 0;}
static int32_t shielding_level(void){return 2147483628;} // Measured on macOS.
static CGErr acquire_fade(float seconds,uint32_t *token){if(token)*token=0;return kErrCannotComplete;}
static CGErr display_fade(uint32_t token,float duration,float start,float end,float r,float g,float b,int sync){return kErrCannotComplete;}
static CGErr release_fade(uint32_t token){return kErrCannotComplete;}
static CGErr get_gamma(Display d,uint32_t capacity,float *red,float *green,float *blue,uint32_t *count){if(count)*count=0;return kErrCannotComplete;}
static CGErr set_gamma(Display d,uint32_t size,const float *red,const float *green,const float *blue){return kErrCannotComplete;}
static CGErr move_cursor(Display d,CGPoint point){return mp_game_warp_cursor(point);}

// ---- CoreVideo display link ---------------------------------------------------
// SDL queries the nominal refresh period of the screen; the link reports the
// UIScreen maximum frame rate. Output callbacks are an OpenGL-path feature
// that this adapter does not implement, so start/callback fail explicitly.
typedef struct {int64_t timeValue,timeScale;int32_t flags;} CVTimeValue;
enum {kCVSuccess=0,kCVUnsupported=-6663};
static int32_t link_create(void **link){static int token;if(link)*link=&token;return kCVSuccess;}
static int32_t link_create_display(Display d,void **link){return link_create(link);}
static CVTimeValue link_period(void *link){return (CVTimeValue){1,UIScreen.mainScreen.maximumFramesPerSecond,0};}
static void link_release(void *link){}
static int32_t link_unsupported(void){note("CVDisplayLink output callbacks unsupported");return kCVUnsupported;}

// ---- Remaining desktop functions -------------------------------------------------
static int32_t ff_none(void){return (int32_t)0x80004002;} // FFERR_NOINTERFACE: device has no force feedback.
static uint32_t keyboard_layout_type(int16_t type){return 0x414e5349;} // kKeyboardANSI, matching the Phase 5.5 ANSI-US keyboard.
static int32_t open_url(CFURLRef url,CFURLRef *launched){
    if(launched)*launched=NULL;if(!url)return -50;
    NSURL *target=(__bridge NSURL *)url;
    dispatch_async(dispatch_get_main_queue(),^{[UIApplication.sharedApplication openURL:target options:@{} completionHandler:nil];});
    return 0;
}
static CFDictionaryRef display_info(uint32_t service,uint32_t options){return CFDictionaryCreate(NULL,NULL,NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);}
static void rect_fill(CGRect rect){UIRectFill(rect);}
static id bluetooth_address_string(const void *address){return nil;}

void *mp_stk_desktop_symbol(const char *library,const char *symbol) {
    for(unsigned i=0;i<18;i++)if(!strcmp(symbol+1,notificationNames[i].UTF8String) && strstr(library,"/AppKit.framework/")) {
        notificationValues[i]=notificationNames[i];return &notificationValues[i];
    }
    if(!strcmp(symbol,"_kCGDisplayShowDuplicateLowResolutionModes"))return &showDuplicateModes;
    const char *classPrefix="_OBJC_CLASS_$_",*metaPrefix="_OBJC_METACLASS_$_";
    if(!strncmp(symbol,classPrefix,strlen(classPrefix))){Class c=desktop_class(symbol+strlen(classPrefix));if(c)return (__bridge void *)c;}
    if(!strncmp(symbol,metaPrefix,strlen(metaPrefix))) {
        // Statically compiled subclasses (SDL's NSApplication/NSView/NSResponder/
        // NSOpenGLContext subclasses) import the superclass metaclass too.
        const char *name=symbol+strlen(metaPrefix);Class c=desktop_class(name);
        if(!c){char cls[256];snprintf(cls,sizeof cls,"%s%s",classPrefix,name);c=(__bridge Class)mp_game_appkit_symbol(cls);}
        if(c)return (__bridge void *)object_getClass(c);
    }
    static const struct {const char *name;void *function;} functions[]={
        {"_CGGetOnlineDisplayList",(void *)online_displays},{"_CGDisplayIsMain",(void *)is_main},{"_CGDisplayMirrorsDisplay",(void *)mirrors},
        {"_CGDisplayPixelsWide",(void *)pixels_wide},{"_CGDisplayPixelsHigh",(void *)pixels_high},{"_CGDisplayScreenSize",(void *)screen_size},
        {"_CGDisplayIOServicePort",(void *)io_service_port},{"_CGDisplayIDToOpenGLDisplayMask",(void *)gl_display_mask},
        {"_CGDisplayModeGetWidth",(void *)mode_width},{"_CGDisplayModeGetHeight",(void *)mode_height},{"_CGDisplayModeGetIOFlags",(void *)mode_io_flags},
        {"_CGDisplayModeIsUsableForDesktopGUI",(void *)mode_usable},{"_CGDisplaySetDisplayMode",(void *)set_display_mode},
        {"_CGDisplayCapture",(void *)capture},{"_CGCaptureAllDisplays",(void *)capture_all},{"_CGDisplayRelease",(void *)release_display},
        {"_CGReleaseAllDisplays",(void *)release_all},{"_CGShieldingWindowLevel",(void *)shielding_level},
        {"_CGAcquireDisplayFadeReservation",(void *)acquire_fade},{"_CGDisplayFade",(void *)display_fade},{"_CGReleaseDisplayFadeReservation",(void *)release_fade},
        {"_CGGetDisplayTransferByTable",(void *)get_gamma},{"_CGSetDisplayTransferByTable",(void *)set_gamma},{"_CGDisplayMoveCursorToPoint",(void *)move_cursor},
        {"_CVDisplayLinkCreateWithActiveCGDisplays",(void *)link_create},{"_CVDisplayLinkCreateWithCGDisplay",(void *)link_create_display},
        {"_CVDisplayLinkGetNominalOutputVideoRefreshPeriod",(void *)link_period},{"_CVDisplayLinkRelease",(void *)link_release},
        {"_CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext",(void *)link_unsupported},{"_CVDisplayLinkSetOutputCallback",(void *)link_unsupported},
        {"_CVDisplayLinkStart",(void *)link_unsupported},
        {"_FFIsForceFeedback",(void *)ff_none},{"_FFCreateDevice",(void *)ff_none},{"_FFDeviceCreateEffect",(void *)ff_none},
        {"_FFDeviceGetForceFeedbackCapabilities",(void *)ff_none},{"_FFDeviceGetForceFeedbackProperty",(void *)ff_none},{"_FFDeviceReleaseEffect",(void *)ff_none},
        {"_FFDeviceSendForceFeedbackCommand",(void *)ff_none},{"_FFDeviceSetForceFeedbackProperty",(void *)ff_none},{"_FFEffectGetEffectStatus",(void *)ff_none},
        {"_FFEffectSetParameters",(void *)ff_none},{"_FFEffectStart",(void *)ff_none},{"_FFEffectStop",(void *)ff_none},{"_FFReleaseDevice",(void *)ff_none},
        {"_KBGetLayoutType",(void *)keyboard_layout_type},{"_LSOpenCFURLRef",(void *)open_url},{"_IODisplayCreateInfoDictionary",(void *)display_info},
        {"_NSRectFill",(void *)rect_fill},{"_IOBluetoothNSStringFromDeviceAddress",(void *)bluetooth_address_string},
    };
    for(unsigned i=0;i<sizeof functions/sizeof *functions;i++)if(!strcmp(symbol,functions[i].name))return functions[i].function;
    return NULL;
}
