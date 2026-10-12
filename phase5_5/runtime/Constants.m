#import <Foundation/Foundation.h>
#include <string.h>
// Values read from the installed macOS frameworks; see desktop-constants.txt.
// Supplying identifiers does not itself implement their corresponding services.
void *mp_desktop_constant(const char *library,const char *symbol) {
    static NSString *values[]={@"NSAppearanceNameAqua",@"NSFilenamesPboardType",@"public.utf8-plain-text",@"NSShadow",@"NSViewFrameDidChangeNotification",@"TISPropertyUnicodeKeyLayoutData"};
    static const char *names[]={"_NSAppearanceNameAqua","_NSFilenamesPboardType","_NSPasteboardTypeString","_NSShadowAttributeName","_NSViewFrameDidChangeNotification","_kTISPropertyUnicodeKeyLayoutData"};
    for(unsigned i=0;i<6;i++)if(strstr(library,i==5?"/Carbon.framework/":"/AppKit.framework/") && !strcmp(symbol,names[i]))return &values[i];
    return NULL;
}
