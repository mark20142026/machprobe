// Diagnostics only (marker file Documents/run-selector-survey): messages that
// adapter classes do not implement are recorded and answered with zero
// instead of raising, so one run lists every missing AppKit method. Results
// from a survey run are not evidence of working behaviour; normal runs never
// install this.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
static NSMutableSet *missing;
static NSLock *lock;
NSArray *mp_selector_survey_results(void){[lock lock];NSArray *r=missing.allObjects;[lock unlock];return [r sortedArrayUsingSelector:@selector(compare:)];}
static NSMethodSignature *signature(id self,SEL _cmd,SEL selector) {
    Class cls=object_getClass(self); // Metaclass for class messages.
    Method m=class_getInstanceMethod(cls,selector);
    if(m)return [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    [lock lock];[missing addObject:[NSString stringWithFormat:@"%s%s %@",class_isMetaClass(cls)?"+":"-",class_getName(class_isMetaClass(cls)?(Class)self:cls),NSStringFromSelector(selector)]];[lock unlock];
    return [NSMethodSignature signatureWithObjCTypes:"@@:@@@@"]; // Extra arguments are ignored.
}
static void forward(id self,SEL _cmd,NSInvocation *invocation) {id zero=nil;[invocation setReturnValue:&zero];}
static void install(Class cls) {
    if(!cls)return;
    Method sig=class_getInstanceMethod(NSObject.class,@selector(methodSignatureForSelector:));
    Method fwd=class_getInstanceMethod(NSObject.class,@selector(forwardInvocation:));
    for(Class c in @[cls,object_getClass(cls)]) {
        // Only add to the exact class; its own implementation (if any) wins.
        class_addMethod(c,@selector(methodSignatureForSelector:),(IMP)signature,method_getTypeEncoding(sig));
        class_addMethod(c,@selector(forwardInvocation:),(IMP)forward,method_getTypeEncoding(fwd));
    }
}
void mp_selector_survey_install(void) {
    missing=[NSMutableSet set];lock=[NSLock new];
    for(NSString *name in @[@"MPGameApplication",@"MPGameWindow",@"MPGameView",@"MPGameScreen",@"MPKeyEvent",@"MPGameCursor",@"MPGameMenu",@"MPGameMenuItem",
                            @"MPGameRunningApplication",@"MPDeclaredNSOpenGLContext",@"MPDeclaredNSColorSpace",@"MPDeclaredNSBezierPath",@"MPAppleEventManager"])
        install(NSClassFromString(name));
}
