#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <math.h>
// Independent GPU experiment: never changes the distributed game's shaders.
NSDictionary *mp_metal_probe(void) {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if(!device)return @{@"passed":@NO,@"error":@"no Metal device"};
    NSMutableDictionary *result=[@{@"device":device.name} mutableCopy],*families=[NSMutableDictionary new],*sets=[NSMutableDictionary new];
    for(NSNumber *family in @[@1001,@1002,@1003,@1004,@1005,@1006,@1007,@1008,@1009,@1010,@1011,@2001,@2002,@3001,@3002,@3003,@5001,@5002])
        families[family.stringValue]=@([device supportsFamily:family.integerValue]);
    for(NSUInteger value=10000;value<=10005;value++)sets[@(value).stringValue]=@([device supportsFeatureSet:value]);
    result[@"families"]=families;result[@"mac_feature_sets"]=sets;
    NSError *error=nil;
    NSString *source=@"#include <metal_stdlib>\nusing namespace metal;\nkernel void border(texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]], device float4 *out [[buffer(0)]], uint i [[thread_position_in_grid]]) { float2 uv[4]={float2(.5,.5),float2(-1,.5),float2(2,.5),float2(.5,2)};out[i]=tex.sample(s,uv[i],level(0)); }";
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    id<MTLComputePipelineState> pipeline=library?[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"border"] error:&error]:nil;
    if(!pipeline){result[@"passed"]=@NO;result[@"error"]=error.description?:@"pipeline failed";return result;}
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:2 mipmapped:NO];td.storageMode=MTLStorageModeShared;
    id<MTLTexture> texture=[device newTextureWithDescriptor:td];
    const uint8_t pixels[]={64,128,192,255,64,128,192,255,64,128,192,255,64,128,192,255};
    [texture replaceRegion:MTLRegionMake2D(0,0,2,2) mipmapLevel:0 withBytes:pixels bytesPerRow:8];
    id<MTLCommandQueue> queue=[device newCommandQueue];NSMutableArray *runs=[NSMutableArray new];BOOL all=YES;
    for(NSUInteger color=0;color<3;color++)for(NSUInteger filter=0;filter<2;filter++) {
        MTLSamplerDescriptor *sd=[MTLSamplerDescriptor new];sd.sAddressMode=sd.tAddressMode=MTLSamplerAddressModeClampToBorderColor;sd.borderColor=color;sd.minFilter=sd.magFilter=filter;
        id<MTLSamplerState> sampler=[device newSamplerStateWithDescriptor:sd];
        if(!sampler){all=NO;[runs addObject:@{@"border":@(color),@"filter":@(filter),@"error":@"sampler unavailable"}];continue;}
        id<MTLBuffer> output=[device newBufferWithLength:64 options:MTLResourceStorageModeShared];
        memset(output.contents,0xff,64);
        id<MTLCommandBuffer> command=[queue commandBuffer];id<MTLComputeCommandEncoder> encoder=[command computeCommandEncoder];
        [encoder setComputePipelineState:pipeline];[encoder setTexture:texture atIndex:0];[encoder setSamplerState:sampler atIndex:0];[encoder setBuffer:output offset:0 atIndex:0];
        [encoder dispatchThreads:MTLSizeMake(4,1,1) threadsPerThreadgroup:MTLSizeMake(4,1,1)];[encoder endEncoding];[command commit];[command waitUntilCompleted];
        float *values=output.contents;BOOL passed=command.status==MTLCommandBufferStatusCompleted;NSMutableArray *actual=[NSMutableArray new];
        for(unsigned i=0;i<16;i++) {
            float expected=i<4?(float)pixels[i]/255.0f:(color==2?1.0f:(color==1 && i%4==3?1.0f:0));
            if(!isfinite(values[i]) || fabsf(values[i]-expected)>0.0001f)passed=NO;
            [actual addObject:isfinite(values[i])?@(values[i]):@"nonfinite"];
        }
        all=all&&passed;[runs addObject:@{@"border":@(color),@"filter":@(filter),@"passed":@(passed),@"values":actual,@"error":command.error.description?:@""}];
    }
    result[@"runs"]=runs;result[@"passed"]=@(all);return result;
}
