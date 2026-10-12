#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>
#include <assert.h>
extern void *mp_keyboard_symbol(const char *);
int main(void){@autoreleasepool {
    CFTypeRef (*copy)(void)=mp_keyboard_symbol("_TISCopyCurrentKeyboardLayoutInputSource");
    void *(*property)(CFTypeRef,CFStringRef)=mp_keyboard_symbol("_TISGetInputSourceProperty");
    __typeof__(&UCKeyTranslate) translate=mp_keyboard_symbol("_UCKeyTranslate");
    CFTypeRef source=copy();CFDataRef data=property(source,CFSTR("TISPropertyUnicodeKeyLayoutData"));
    assert(data && !property(source,CFSTR("unknown")));
    const UCKeyboardLayout *ours=(const void *)CFDataGetBytePtr(data);
    CFDictionaryRef filter=(__bridge CFDictionaryRef)@{(__bridge NSString *)kTISPropertyInputSourceID:@"com.apple.keylayout.US"};
    CFArrayRef sources=TISCreateInputSourceList(filter,true);assert(sources && CFArrayGetCount(sources));
    CFDataRef native=TISGetInputSourceProperty((TISInputSourceRef)CFArrayGetValueAtIndex(sources,0),kTISPropertyUnicodeKeyLayoutData);
    const UCKeyboardLayout *system=(const void *)CFDataGetBytePtr(native);
    unsigned compared=0,fail=0;
    for(UInt16 action=0;action<4;action++)for(UInt16 key=0;key<51;key++){if(key==10)continue;
      for(UInt32 mods=0;mods<8;mods++){
        UInt32 a=0,b=0;UniChar ca[8]={0},cb[8]={0};UniCharCount na=0,nb=0;
        OSStatus ra=translate(ours,key,action,mods,40,1,&a,8,&na,ca);
        OSStatus rb=UCKeyTranslate(system,key,action,mods,40,1,&b,8,&nb,cb);
        if(ra!=rb || na!=nb || memcmp(ca,cb,na*sizeof(UniChar))){fprintf(stderr,"key=%u mods=%u ours=%d/%u/%04x native=%d/%u/%04x\n",key,mods,ra,(unsigned)na,ca[0],rb,(unsigned)nb,cb[0]);fail++;}compared++;
      }
    }
    UInt32 dead=0;UniCharCount n=99;UniChar output=0xbeef;
    assert(translate(ours,0,0,0,40,0,&dead,0,&n,&output)==-25340 && n==0 && output==0xbeef);
    assert(translate(NULL,0,0,0,40,0,&dead,1,&n,&output)==-50);
    assert(translate(ours,0,0,8,40,0,&dead,1,&n,&output)==-4);
    CFRelease(source);CFRelease(sources);
    printf("%u native US layout comparisons, %u failures\n",compared,fail);return fail?1:0;
}}
