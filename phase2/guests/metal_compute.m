#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum { ElementCount = 16 };

int metal_compute_check(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            fputs("METAL_ERROR no default Metal device\n", stderr);
            return 1;
        }

        NSString *source = [NSString stringWithUTF8String:
            "#include <metal_stdlib>\n"
            "using namespace metal;\n"
            "kernel void triple_plus_seven(device const uint *input [[buffer(0)]], "
            "device uint *output [[buffer(1)]], uint i [[thread_position_in_grid]]) { "
            "output[i] = input[i] * 3u + 7u; }\n"];
        NSError *error = nil;
        id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
        if (!library) {
            fprintf(stderr, "METAL_ERROR library: %s\n",
                    error.localizedDescription.UTF8String ?: "unknown error");
            return 1;
        }
        id<MTLFunction> function = [library newFunctionWithName:
            [NSString stringWithUTF8String:"triple_plus_seven"]];
        if (!function) {
            fputs("METAL_ERROR kernel function not found\n", stderr);
            return 1;
        }
        id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
        if (!pipeline) {
            fprintf(stderr, "METAL_ERROR pipeline: %s\n",
                    error.localizedDescription.UTF8String ?: "unknown error");
            return 1;
        }

        uint32_t inputValues[ElementCount];
        uint32_t outputValues[ElementCount] = {0};
        for (uint32_t i = 0; i < ElementCount; ++i) inputValues[i] = i;

        const NSUInteger byteCount = sizeof inputValues;
        id<MTLBuffer> input = [device newBufferWithLength:byteCount
                                                 options:MTLResourceStorageModeShared];
        id<MTLBuffer> output = [device newBufferWithLength:byteCount
                                                  options:MTLResourceStorageModeShared];
        if (!input || !output) {
            fputs("METAL_ERROR buffer allocation failed\n", stderr);
            return 1;
        }
        memcpy(input.contents, inputValues, byteCount);

        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
        if (!queue || !commandBuffer || !encoder) {
            fputs("METAL_ERROR command setup failed\n", stderr);
            return 1;
        }
        [encoder setComputePipelineState:pipeline];
        [encoder setBuffer:input offset:0 atIndex:0];
        [encoder setBuffer:output offset:0 atIndex:1];
        MTLSize threads = MTLSizeMake(ElementCount, 1, 1);
        NSUInteger width = pipeline.threadExecutionWidth;
        MTLSize threadgroup = MTLSizeMake(width ? width : 1, 1, 1);
        [encoder dispatchThreads:threads threadsPerThreadgroup:threadgroup];
        [encoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
        if (commandBuffer.status != MTLCommandBufferStatusCompleted) {
            fprintf(stderr, "METAL_ERROR command status=%lu: %s\n",
                    (unsigned long)commandBuffer.status,
                    commandBuffer.error.localizedDescription.UTF8String ?: "unknown error");
            return 1;
        }

        memcpy(outputValues, output.contents, byteCount);
        uint32_t checksum = 0;
        for (uint32_t i = 0; i < ElementCount; ++i) {
            const uint32_t expected = i * 3u + 7u;
            if (outputValues[i] != expected) {
                fprintf(stderr, "METAL_ERROR index=%u expected=%u actual=%u\n",
                        i, expected, outputValues[i]);
                return 1;
            }
            checksum += outputValues[i];
        }

        printf("METAL_RESULT count=%u values=", ElementCount);
        for (uint32_t i = 0; i < ElementCount; ++i)
            printf("%s%u", i ? "," : "", outputValues[i]);
        printf(" checksum=%u\n", checksum);
        return 0;
    }
}

int main(void) {
    return metal_compute_check();
}
