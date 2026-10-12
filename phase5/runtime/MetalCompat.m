#import "MetalCompat.h"
extern void mp_game_trace(NSString *event);
static NSUInteger textureTranslations,bufferTranslations,heapTranslations,buffersCreated;
// MTLResourceStorageModeManaged (1<<4) is macOS-only. On unified memory the
// Shared mode gives the same CPU/GPU view without didModifyRange: syncs.
static MTLResourceOptions shared_options(MTLResourceOptions options) {
    if(((options>>MTLResourceStorageModeShift)&0xf)==1){bufferTranslations++;options&=~(MTLResourceOptions)(0xf<<MTLResourceStorageModeShift);}
    buffersCreated++;return options;
}
@interface MPMetalDeviceAdapter:NSObject
@property(nonatomic,strong) id<MTLDevice> native;
@end
@implementation MPMetalDeviceAdapter
- (id)forwardingTargetForSelector:(SEL)selector {return self.native;}
- (BOOL)respondsToSelector:(SEL)selector {return [super respondsToSelector:selector] || [self.native respondsToSelector:selector];}
- (BOOL)conformsToProtocol:(Protocol *)protocol {return [self.native conformsToProtocol:protocol] || [super conformsToProtocol:protocol];}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor {
    // Numeric 1 is macOS Managed, unavailable in the iOS SDK. On unified
    // memory, Shared provides CPU/GPU access to the same allocation. Keep
    // descriptor mutation local; the guest's descriptor retains its own value.
    if((NSUInteger)descriptor.storageMode==1 && self.native.hasUnifiedMemory) {
        MTLTextureDescriptor *translated=[descriptor copy];translated.storageMode=MTLStorageModeShared;
        textureTranslations++;mp_game_trace(@"Metal managed texture → shared unified-memory allocation");
        return [self.native newTextureWithDescriptor:translated];
    }
    return [self.native newTextureWithDescriptor:descriptor];
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {return [self.native newBufferWithLength:length options:shared_options(options)];}
- (id<MTLBuffer>)newBufferWithBytes:(const void *)bytes length:(NSUInteger)length options:(MTLResourceOptions)options {return [self.native newBufferWithBytes:bytes length:length options:shared_options(options)];}
- (id<MTLBuffer>)newBufferWithBytesNoCopy:(void *)bytes length:(NSUInteger)length options:(MTLResourceOptions)options deallocator:(void (^)(void *,NSUInteger))deallocator {return [self.native newBufferWithBytesNoCopy:bytes length:length options:shared_options(options) deallocator:deallocator];}
- (id<MTLHeap>)newHeapWithDescriptor:(MTLHeapDescriptor *)descriptor {
    if((NSUInteger)descriptor.storageMode==1){MTLHeapDescriptor *d=[descriptor copy];d.storageMode=MTLStorageModeShared;heapTranslations++;return [self.native newHeapWithDescriptor:d];}
    return [self.native newHeapWithDescriptor:descriptor];
}
@end
id<MTLDevice> mp_game_wrap_metal_device(id<MTLDevice> native) {
    if(!native)return nil;
    MPMetalDeviceAdapter *adapter=[MPMetalDeviceAdapter new];adapter.native=native;return (id<MTLDevice>)adapter;
}
id<MTLDevice> mp_game_metal_device(void) {
    static MPMetalDeviceAdapter *adapter;static dispatch_once_t once;
    dispatch_once(&once,^{adapter=(id)mp_game_wrap_metal_device(MTLCreateSystemDefaultDevice());});
    return (id<MTLDevice>)adapter;
}
NSDictionary *mp_game_metal_stats(void){
    static NSDictionary *native;static dispatch_once_t once;
    dispatch_once(&once,^{
        id<MTLDevice> d=MTLCreateSystemDefaultDevice();NSMutableDictionary *f=[NSMutableDictionary dictionary];
        for(NSNumber *family in @[@(MTLGPUFamilyApple5),@(MTLGPUFamilyApple6),@(MTLGPUFamilyApple7),@(MTLGPUFamilyApple8),@(MTLGPUFamilyApple9),@(MTLGPUFamilyMac2),@(MTLGPUFamilyMetal3)])
            f[family.stringValue]=@([d supportsFamily:(MTLGPUFamily)family.integerValue]);
        native=@{@"families":f,@"bc_textures":@([d respondsToSelector:@selector(supportsBCTextureCompression)] && d.supportsBCTextureCompression),
                 @"unified_memory":@(d.hasUnifiedMemory),@"name":d.name?:@""};
    });
    return @{@"managed_textures_translated":@(textureTranslations),@"managed_buffers_translated":@(bufferTranslations),@"managed_heaps_translated":@(heapTranslations),@"buffers_created":@(buffersCreated),@"native_device":native};
}
