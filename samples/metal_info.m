#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { fputs("No Metal device available\n", stderr); return 1; }
        printf("Metal device: %s\nRegistry ID: %llu\nUnified memory: %s\n",
               device.name.UTF8String, (unsigned long long)device.registryID,
               device.hasUnifiedMemory ? "yes" : "no");
    }
    return 0;
}
