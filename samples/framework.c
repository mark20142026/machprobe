#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
int main(void) {
    CFStringRef text = CFStringCreateWithCString(NULL, "macOS ARM64", kCFStringEncodingUTF8);
    if (!text) return 1;
    printf("CoreFoundation string length: %ld\n", (long)CFStringGetLength(text));
    CFRelease(text);
    return 0;
}
