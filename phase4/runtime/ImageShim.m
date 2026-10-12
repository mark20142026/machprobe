#import "ImageShim.h"
#import <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <string.h>
@interface MPCompatNumberFormatter : NSNumberFormatter
- (void)setHasThousandSeparators:(BOOL)value;
- (BOOL)hasThousandSeparators;
@end
@implementation MPCompatNumberFormatter
- (void)setHasThousandSeparators:(BOOL)value { self.usesGroupingSeparator=value; }
- (BOOL)hasThousandSeparators { return self.usesGroupingSeparator; }
@end
@implementation MPCompatImage
- (instancetype)initWithData:(NSData *)data {
    UIImage *image=[UIImage imageWithData:data];if(!image)return nil;
    if((self=[super init]))self.uiImage=image;return self;
}
- (CGSize)size {return self.uiImage.size;}
+ (instancetype)imageNamed:(NSString *)name {
    UIImage *image=[UIImage imageNamed:name inBundle:NSBundle.mainBundle compatibleWithTraitCollection:nil];
    if(!image)return nil;
    MPCompatImage *result=[self new];result.uiImage=image;return result;
}
@end
@implementation MPCompatSound
+ (void)beep { AudioServicesPlaySystemSound(1104); }
@end
void *mp_ios_shim(const char *library,const char *symbol) {
    (void)library;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSNumberFormatter"))return (__bridge void *)MPCompatNumberFormatter.class;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSImage"))return (__bridge void *)MPCompatImage.class;
    if(!strcmp(symbol,"_OBJC_CLASS_$_NSSound"))return (__bridge void *)MPCompatSound.class;
    if(!strcmp(symbol,"_$s7SwiftUI5ImageV02nsC0ACSo7NSImageC_tcfC") || !strcmp(symbol,"_$sSo7NSSoundC6AppKitE4beepyyFZ"))return dlsym(RTLD_DEFAULT,symbol+1);
    return NULL;
}
