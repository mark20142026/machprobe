#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdio.h>

int foundation_check(void) {
    __weak NSObject *observed;
    @autoreleasepool {
        NSObject *temporary = [[NSObject alloc] init];
        observed = temporary;
        if (!observed) return 2;
    }
    if (observed) return 3;
    @autoreleasepool {
        NSString *text = [NSString stringWithUTF8String:"phase2-foundation"];
        NSString *upper = [text uppercaseString];
        NSMutableArray<NSString *> *items = [NSMutableArray array];
        [items addObject:text];
        [items addObject:upper];

        Class stringClass = objc_getClass("NSString");
        SEL lengthSelector = sel_registerName("length");
        BOOL classLookupOK = stringClass != Nil && [text isKindOfClass:stringClass];
        BOOL selectorAvailable = [text respondsToSelector:lengthSelector];
        NSUInteger length = selectorAvailable
            ? ((NSUInteger (*)(id, SEL))objc_msgSend)(text, lengthSelector)
            : 0;

        if (!classLookupOK || !selectorAvailable || length != 17 || items.count != 2) {
            fprintf(stderr, "FOUNDATION_ERROR class=%d selector=%d length=%lu count=%lu\n",
                    classLookupOK, selectorAvailable, (unsigned long)length,
                    (unsigned long)items.count);
            return 1;
        }

        NSString *joined = [items componentsJoinedByString:
            [NSString stringWithUTF8String:"|"]];
        printf("FOUNDATION_RESULT weak=cleared class=NSString selector=length length=%lu count=%lu value=%s\n",
               (unsigned long)length, (unsigned long)items.count, joined.UTF8String);
        return 0;
    }
}

int main(void) {
    return foundation_check();
}
