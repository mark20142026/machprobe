// A real AppKit program. It has no UIKit, Metal, or compatibility-layer imports.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdint.h>

static NSWindow *window;
static NSTextField *label;
static id target;
static Class actionClass;
static int counter;

static void clicked(id self, SEL command, id sender) {
    (void)self; (void)command;
    NSInteger tag=[sender tag];
    counter=tag==3?0:counter+(tag==1?1:-1);
    [label setStringValue:[NSString stringWithFormat:@"Guest clicks: %d",counter]];
}
int mp_gui_counter(void) { return counter; }
uintptr_t mp_gui_action_address(void) { return (uintptr_t)&clicked; }
void mp_gui_destroy(void) {
    [window close];
    [label release]; label=nil;
    [window release]; window=nil;
    [target release]; target=nil;
    if(actionClass)objc_disposeClassPair(actionClass);
    actionClass=Nil; counter=0;
}
int main(void) {
    @autoreleasepool {
        NSApplication *app=[NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,340,240)
            styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered defer:NO];
        [window setReleasedWhenClosed:NO];
        [window setTitle:@"macOS guest window"];
        label=[[NSTextField alloc] initWithFrame:NSMakeRect(20,150,300,45)];
        [label setEditable:NO]; [label setBezeled:NO]; [label setDrawsBackground:NO];
        [label setStringValue:@"Guest clicks: 0"];
        [[window contentView] addSubview:label];
        actionClass=objc_allocateClassPair([NSObject class],"MPGuestActions",0);
        if(!actionClass || !class_addMethod(actionClass,sel_registerName("clicked:"),(IMP)clicked,"v@:@"))return 2;
        objc_registerClassPair(actionClass);
        target=[[actionClass alloc] init];
        NSArray *titles=@[@"+",@"-",@"Reset"];
        for(int i=0;i<3;i++) {
            NSButton *button=[[NSButton alloc] initWithFrame:NSMakeRect(20+i*105,55,90,55)];
            [button setTitle:[titles objectAtIndex:i]];
            [button setTag:i+1]; [button setTarget:target]; [button setAction:sel_registerName("clicked:")];
            [button setBezelStyle:NSBezelStyleRounded];
            [[window contentView] addSubview:button]; [button release];
        }
        [window center]; [window makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES]; [app run];
    }
    return 0;
}
