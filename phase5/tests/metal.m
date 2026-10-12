#import "MetalCompat.h"
#include <assert.h>
#include <string.h>
void mp_game_trace(NSString *event){(void)event;}
int main(void){@autoreleasepool {
    id<MTLDevice> device=mp_game_metal_device();assert(device && device.hasUnifiedMemory);
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    d.storageMode=(MTLStorageMode)1;d.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> texture=[device newTextureWithDescriptor:d];assert(texture && texture.storageMode==MTLStorageModeShared);
    assert((NSUInteger)d.storageMode==1); // The guest descriptor was not mutated.
    uint32_t pixels[16];for(unsigned i=0;i<16;i++)pixels[i]=0xff000000u+i*0x010305u;
    [texture replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:pixels bytesPerRow:16];
    id<MTLBuffer> output=[device newBufferWithLength:1024 options:MTLResourceStorageModeShared];memset(output.contents,0,1024);
    id<MTLCommandQueue> queue=[device newCommandQueue];id<MTLCommandBuffer> command=[queue commandBuffer];id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(4,4,1) toBuffer:output destinationOffset:0 destinationBytesPerRow:256 destinationBytesPerImage:1024];
    [blit endEncoding];[command commit];[command waitUntilCompleted];assert(command.status==MTLCommandBufferStatusCompleted);
    for(unsigned row=0;row<4;row++)assert(!memcmp((char *)output.contents+row*256,pixels+row*4,16));
    d.storageMode=MTLStorageModePrivate;id<MTLTexture> private=[device newTextureWithDescriptor:d];assert(private.storageMode==MTLStorageModePrivate);
    assert([mp_game_metal_stats()[@"managed_textures_translated"] unsignedIntegerValue]==1);
    puts("Metal adapter: guest descriptor preserved, shared GPU bytes verified, private storage preserved");return 0;
}}
