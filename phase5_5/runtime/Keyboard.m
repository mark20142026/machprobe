#import <Foundation/Foundation.h>
#include <string.h>
// Carbon is absent on iOS. This is an explicit ANSI-US fallback, not a copy of
// the user's macOS layout or an implementation of arbitrary uchr/dead-key data.
static NSData *layout;
static NSDictionary *source;
static void initialize(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        layout=[@"machprobe.ansi-us.v1" dataUsingEncoding:NSUTF8StringEncoding];
        source=@{@"TISPropertyUnicodeKeyLayoutData":layout};
    });
}
static CFTypeRef copy_source(void) {initialize();return CFRetain((__bridge CFTypeRef)source);}
static void *property(CFTypeRef object,CFStringRef key) {
    initialize();if(object!=(__bridge CFTypeRef)source || !key)return NULL;
    return (__bridge void *)source[(__bridge NSString *)key];
}
static int32_t translate(const void *resource,uint16_t key,uint16_t action,uint32_t modifiers,uint32_t keyboard,uint32_t options,uint32_t *dead,unsigned long capacity,unsigned long *length,uint16_t *out) {
    initialize();
    if(length)*length=0;
    if(resource!=layout.bytes || key>=128 || action>3 || !dead || !length || !out)return -50;
    // Option/dead-key and alternate keyboard types are not silently approximated.
    if((modifiers & ~7u) || (options & ~1u) || *dead || (keyboard!=0 && keyboard!=40))return -4;
    static const char normal[128]="asdfhgzxcv\0bqweryt123465=97-80]ou[ip\rlj'k;\\,/nm.\t `\x7f";
    static const char shifted[128]="ASDFHGZXCV\0BQWERYT!@#$^%+(&_*)}OU{IP\rLJ\"K:|<?NM>\t ~\x7f";
    unsigned char c=normal[key];
    BOOL shift=!(modifiers&1) && (modifiers&2),caps=!(modifiers&1) && (modifiers&4);
    if(c>='a' && c<='z'){if(shift||caps)c=(unsigned char)(c-'a'+'A');}
    else if(shift)c=shifted[key];
    if(!c)return 0;
    if(!capacity)return -25340;
    out[0]=c;*length=1;return 0;
}
static uint8_t keyboard_type(void) {return 40;} // gestaltThirdPartyANSIKbd
void *mp_keyboard_symbol(const char *name) {
    if(!strcmp(name,"_TISCopyCurrentKeyboardLayoutInputSource"))return (void *)&copy_source;
    if(!strcmp(name,"_TISGetInputSourceProperty"))return (void *)&property;
    if(!strcmp(name,"_LMGetKbdType"))return (void *)&keyboard_type;
    if(!strcmp(name,"_UCKeyTranslate"))return (void *)&translate;
    return NULL;
}
