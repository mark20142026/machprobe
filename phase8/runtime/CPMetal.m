// Lean Metal for Cyberpunk 2077: the guest receives Apple's real MTLDevice
// (no proxy objects on any per-frame path). macOS-only API is added directly
// to the concrete Metal classes with answers for a built-in Apple GPU, and
// macOS Managed storage (1) is rewritten to Shared at resource creation
// (unified memory: same CPU/GPU view, no didModifyRange: needed).
#import <Metal/Metal.h>
#import <objc/runtime.h>
static id<MTLDevice> device;
static BOOL yes(id s,SEL c){return YES;}
static BOOL no(id s,SEL c){return NO;}
static NSUInteger zero(id s,SEL c){return 0;}
static uint32_t one32(id s,SEL c){return 1;}
static uint32_t zero32(id s,SEL c){return 0;}
static void nop1(id s,SEL c,id a){}
static void nop_range(id s,SEL c,NSRange r){}
static void nop_tex(id s,SEL c,id t,NSUInteger slice,NSUInteger level){}
static BOOL barycentric(id s,SEL c){return [s supportsShaderBarycentricCoordinates];}
static void add(Class cls,SEL sel,IMP imp,const char *types){if(cls && !class_respondsToSelector(cls,sel))class_addMethod(cls,sel,imp,types);}
// Storage-mode rewrites wrap the original implementation of the concrete class.
static MTLResourceOptions shared_options(MTLResourceOptions o){return ((o>>MTLResourceStorageModeShift)&0xf)==1?(o&~(MTLResourceOptions)(0xf<<MTLResourceStorageModeShift)):o;}
static IMP origBufLen,origBufBytes,origBufNoCopy,origTex,origHeap;
// MP_MEM_TRACE: GPU allocations of 16 MB or more, with running totals and the
// guest caller, to find what fills the memory budget.
static int gtrace=-1;static _Atomic unsigned long long gpuTotal,gpuCount;
static void gpu_trace(const char *kind,NSUInteger bytes,void *caller) {
    if(gtrace<0)gtrace=getenv("MP_MEM_TRACE")!=NULL;
    if(!gtrace)return;
    gpuTotal+=bytes;gpuCount++;
    if(bytes<(16u<<20))return;
    extern const char *mp_locate(uintptr_t,uintptr_t *);uintptr_t off=0;const char *g=mp_locate((uintptr_t)caller,&off);
    fprintf(stderr,"[gpu] %s %lu MB (total %llu MB in %llu allocations) from %s+%#lx\n",kind,(unsigned long)(bytes>>20),gpuTotal>>20,gpuCount,g?g:"host",(unsigned long)off);
}
static id buf_len(id s,SEL c,NSUInteger l,MTLResourceOptions o){gpu_trace("buffer",l,__builtin_return_address(0));return ((id(*)(id,SEL,NSUInteger,MTLResourceOptions))origBufLen)(s,c,l,shared_options(o));}
static id buf_bytes(id s,SEL c,const void *b,NSUInteger l,MTLResourceOptions o){gpu_trace("buffer+bytes",l,__builtin_return_address(0));return ((id(*)(id,SEL,const void *,NSUInteger,MTLResourceOptions))origBufBytes)(s,c,b,l,shared_options(o));}
static id buf_nocopy(id s,SEL c,void *b,NSUInteger l,MTLResourceOptions o,id d){return ((id(*)(id,SEL,void *,NSUInteger,MTLResourceOptions,id))origBufNoCopy)(s,c,b,l,shared_options(o),d);}
// Texture storage census (logged with [perf]): what the Mac build asks for.
// Managed has no iOS equivalent; Shared loses lossless compression on Apple
// GPUs, so render targets that were Managed may go Private
// (MP_MANAGED_RT_PRIVATE=1, experiment: the CPU never writes render targets).
_Atomic unsigned long mp_tex_census[4]; // 0 managed render target, 1 managed other, 2 shared, 3 private
static id tex(id s,SEL c,MTLTextureDescriptor *d){
    if(gtrace)gpu_trace("texture",[s heapTextureSizeAndAlignWithDescriptor:d].size,__builtin_return_address(0));
    NSUInteger mode=(NSUInteger)d.storageMode;BOOL rt=(d.usage&MTLTextureUsageRenderTarget)!=0;
    mp_tex_census[mode==1?(rt?0:1):mode==0?2:3]++;
    if(mode==1){static int rtPrivate=-1;if(rtPrivate<0)rtPrivate=getenv("MP_MANAGED_RT_PRIVATE")!=NULL;
        d=[d copy];d.storageMode=(rt && rtPrivate)?MTLStorageModePrivate:MTLStorageModeShared;}
    id t=((id(*)(id,SEL,id))origTex)(s,c,d);
    if(!t)fprintf(stderr,"[gpu] texture FAILED: type %lu fmt %lu %lux%lux%lu mips %lu array %lu samples %lu usage %#lx storage %lu\n",(unsigned long)d.textureType,(unsigned long)d.pixelFormat,(unsigned long)d.width,(unsigned long)d.height,(unsigned long)d.depth,(unsigned long)d.mipmapLevelCount,(unsigned long)d.arrayLength,(unsigned long)d.sampleCount,(unsigned long)d.usage,(unsigned long)d.storageMode);
    return t;
}
// Heap sub-allocation failures (a capped heap that filled up) are logged
// always: the game may not check for nil.
// Spill-over heaps. Capped heaps (see heap()) fill up during world streaming;
// a failed sub-allocation then comes from an overflow heap chained to the
// capped one, created only while real memory allows (os_proc_available_memory
// keeps a safety margin). Encoders that make a capped heap resident (useHeap:)
// also make its overflow heaps resident, so resources stay valid on the GPU.
#include <os/proc.h>
#include <os/lock.h>
#include <stdatomic.h>
static IMP origHeapTex,origHeapBuf;static char overflowKey;static os_unfair_lock overflowLock=OS_UNFAIR_LOCK_INIT;
static const size_t marginBytes=900u<<20;
static _Atomic unsigned spilledHeaps; // Heaps that own spill-over heaps; 0 keeps useHeap: hooks free.
static NSArray *overflows(id heap){
    if(!spilledHeaps)return nil;
    os_unfair_lock_lock(&overflowLock);NSArray *a=objc_getAssociatedObject(heap,&overflowKey);os_unfair_lock_unlock(&overflowLock);
    return a; // Append-only; a stale count only skips the newest heap for one encoder.
}
static void install_encoder_hooks(id device);
static _Atomic uint64_t spilledBytes;
// The game keeps its heaps resident with residency sets (addAllocation:), not only useHeap:, so
// spill-over heaps it never saw were non-resident in passes that read them through argument
// buffers: those reads returned black (a fixed black spot in the sky with motion blur). One
// residency set of our own holds every spill-over heap and is attached to every command queue.
static id spillSet;static os_unfair_lock spillSetLock=OS_UNFAIR_LOCK_INIT;
static IMP origQueue,origQueueMax,origQueueDesc;
static id resident(id q){if(q && spillSet)[q addResidencySet:spillSet];return q;}
static id queue_plain(id s,SEL c){return resident(((id(*)(id,SEL))origQueue)(s,c));}
static id queue_max(id s,SEL c,NSUInteger n){return resident(((id(*)(id,SEL,NSUInteger))origQueueMax)(s,c,n));}
static id queue_desc(id s,SEL c,id d){return resident(((id(*)(id,SEL,id))origQueueDesc)(s,c,d));}
static id spill_heap(id<MTLHeap> heap,NSUInteger need) {
    // Total spill-over is capped (MP_SPILL_CAP_MB, default 1024): past it the game
    // streams lower mips instead of pushing the app toward the memory limit.
    static uint64_t capBytes;if(!capBytes){const char *v=getenv("MP_SPILL_CAP_MB");capBytes=(uint64_t)(v?atoll(v):1024)<<20;}
    if(spilledBytes+need>capBytes)return nil;
    if(os_proc_available_memory()<need+marginBytes)return nil;
    MTLHeapDescriptor *d=[MTLHeapDescriptor new];
    d.storageMode=heap.storageMode;d.cpuCacheMode=heap.cpuCacheMode;d.hazardTrackingMode=heap.hazardTrackingMode;d.type=heap.type;
    d.size=MAX(need,(NSUInteger)64<<20);
    id device=heap.device;id h=((id(*)(id,SEL,id))origHeap)(device,@selector(newHeapWithDescriptor:),d);
    if(!h)return nil;
    spilledBytes+=d.size;
    if(spillSet){os_unfair_lock_lock(&spillSetLock);[spillSet addAllocation:h];[spillSet commit];os_unfair_lock_unlock(&spillSetLock);}
    install_encoder_hooks(device);
    os_unfair_lock_lock(&overflowLock);
    NSArray *old=objc_getAssociatedObject(heap,&overflowKey);if(!old)spilledHeaps++;
    NSArray *list=old?[old arrayByAddingObject:h]:@[h];   // Copy-on-write: readers never see a mutating array.
    objc_setAssociatedObject(heap,&overflowKey,list,OBJC_ASSOCIATION_RETAIN);NSUInteger count=list.count;
    os_unfair_lock_unlock(&overflowLock);
    fprintf(stderr,"[gpu] heap %p full: spill-over heap #%lu of %lu MB (%zu MB free)%s\n",heap,(unsigned long)count,(unsigned long)(d.size>>20),os_proc_available_memory()>>20,spillSet?", resident on all queues":", NOT in a residency set");
    return h;
}
static id heap_tex(id s,SEL c,MTLTextureDescriptor *d){
    id r=((id(*)(id,SEL,id))origHeapTex)(s,c,d);if(r)return r;
    for(id h in overflows(s))if((r=((id(*)(id,SEL,id))origHeapTex)(h,c,d)))return r;
    NSUInteger need=[[s device] heapTextureSizeAndAlignWithDescriptor:d].size;
    id h=spill_heap(s,need);if(h && (r=((id(*)(id,SEL,id))origHeapTex)(h,c,d)))return r;
    static int warned;if(warned++<20)fprintf(stderr,"[gpu] heap %p FULL: texture %lux%lu fmt %lu failed (%zu MB free)\n",s,(unsigned long)d.width,(unsigned long)d.height,(unsigned long)d.pixelFormat,os_proc_available_memory()>>20);
    return nil;
}
static id heap_buf(id s,SEL c,NSUInteger l,MTLResourceOptions o){
    o=shared_options(o);id r=((id(*)(id,SEL,NSUInteger,MTLResourceOptions))origHeapBuf)(s,c,l,o);if(r)return r;
    for(id h in overflows(s))if((r=((id(*)(id,SEL,NSUInteger,MTLResourceOptions))origHeapBuf)(h,c,l,o)))return r;
    NSUInteger need=[[s device] heapBufferSizeAndAlignWithLength:l options:o].size;
    id h=spill_heap(s,need);if(h && (r=((id(*)(id,SEL,NSUInteger,MTLResourceOptions))origHeapBuf)(h,c,l,o)))return r;
    static int warned;if(warned++<20)fprintf(stderr,"[gpu] heap %p FULL: buffer %lu KB failed (%zu MB free)\n",s,(unsigned long)(l>>10),os_proc_available_memory()>>20);
    return nil;
}
static void watch_heap(id h) {
    static dispatch_once_t once;dispatch_once(&once,^{Class k=object_getClass(h);
        Method m=class_getInstanceMethod(k,@selector(newTextureWithDescriptor:));origHeapTex=method_getImplementation(m);method_setImplementation(m,(IMP)heap_tex);
        m=class_getInstanceMethod(k,@selector(newBufferWithLength:options:));origHeapBuf=method_getImplementation(m);method_setImplementation(m,(IMP)heap_buf);});
}
// useHeap: variants on the device's concrete render/compute encoder classes.
static IMP origUseHeapR,origUseHeapStagesR,origUseHeapsR,origUseHeapsStagesR,origUseHeapC,origUseHeapsC;
static void useHeapR(id e,SEL c,id h){((void(*)(id,SEL,id))origUseHeapR)(e,c,h);for(id o in overflows(h))((void(*)(id,SEL,id))origUseHeapR)(e,c,o);}
static void useHeapStagesR(id e,SEL c,id h,NSUInteger st){((void(*)(id,SEL,id,NSUInteger))origUseHeapStagesR)(e,c,h,st);for(id o in overflows(h))((void(*)(id,SEL,id,NSUInteger))origUseHeapStagesR)(e,c,o,st);}
static void useHeapsR(id e,SEL c,const id *hs,NSUInteger n){((void(*)(id,SEL,const id *,NSUInteger))origUseHeapsR)(e,c,hs,n);for(NSUInteger i=0;i<n;i++)for(id o in overflows(hs[i]))((void(*)(id,SEL,id))origUseHeapR)(e,@selector(useHeap:),o);}
static void useHeapsStagesR(id e,SEL c,const id *hs,NSUInteger n,NSUInteger st){((void(*)(id,SEL,const id *,NSUInteger,NSUInteger))origUseHeapsStagesR)(e,c,hs,n,st);for(NSUInteger i=0;i<n;i++)for(id o in overflows(hs[i]))((void(*)(id,SEL,id,NSUInteger))origUseHeapStagesR)(e,@selector(useHeap:stages:),o,st);}
static void useHeapC(id e,SEL c,id h){((void(*)(id,SEL,id))origUseHeapC)(e,c,h);for(id o in overflows(h))((void(*)(id,SEL,id))origUseHeapC)(e,c,o);}
static void useHeapsC(id e,SEL c,const id *hs,NSUInteger n){((void(*)(id,SEL,const id *,NSUInteger))origUseHeapsC)(e,c,hs,n);for(NSUInteger i=0;i<n;i++)for(id o in overflows(hs[i]))((void(*)(id,SEL,id))origUseHeapC)(e,@selector(useHeap:),o);}
static IMP hook(Class k,SEL sel,IMP imp){Method m=class_getInstanceMethod(k,sel);return m?method_setImplementation(m,imp):NULL;}
static void install_encoder_hooks(id device) {
    static dispatch_once_t once;dispatch_once(&once,^{
        id queue=[device newCommandQueue];id cb=[queue commandBuffer];
        MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;
        MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=[device newTextureWithDescriptor:td];rp.colorAttachments[0].loadAction=MTLLoadActionDontCare;
        id re=[cb renderCommandEncoderWithDescriptor:rp];Class rk=object_getClass(re);[re endEncoding];
        id ce=[cb computeCommandEncoder];Class ck=object_getClass(ce);[ce endEncoding];
        origUseHeapR=hook(rk,@selector(useHeap:),(IMP)useHeapR);origUseHeapStagesR=hook(rk,@selector(useHeap:stages:),(IMP)useHeapStagesR);
        origUseHeapsR=hook(rk,@selector(useHeaps:count:),(IMP)useHeapsR);origUseHeapsStagesR=hook(rk,@selector(useHeaps:count:stages:),(IMP)useHeapsStagesR);
        origUseHeapC=hook(ck,@selector(useHeap:),(IMP)useHeapC);origUseHeapsC=hook(ck,@selector(useHeaps:count:),(IMP)useHeapsC);
        fprintf(stderr,"[gpu] spill-over residency hooks on %s / %s\n",class_getName(rk),class_getName(ck));
    });
}
static id heap(id s,SEL c,MTLHeapDescriptor *d){
    gpu_trace("heap",d.size,__builtin_return_address(0));
    if(gtrace)fprintf(stderr,"[gpu]   heap type=%ld storage=%ld cpuCache=%ld hazard=%ld options=%#lx sparsePage=%ld\n",(long)d.type,(long)d.storageMode,(long)d.cpuCacheMode,(long)d.hazardTrackingMode,(unsigned long)d.resourceOptions,(long)(@available(iOS 16.0,*)?d.sparsePageSize:0));
    static long cap=-1;if(cap<0){const char *v=getenv("MP_HEAP_CAP_MB");cap=v?atol(v):96;} // Grow-on-demand: iOS charges a heap whole at creation; spill-over heaps add capacity only as the game fills it.
    if(cap && d.size>(NSUInteger)cap<<20){d=[d copy];if(gtrace)fprintf(stderr,"[gpu]   heap %lu MB capped to %ld MB\n",(unsigned long)(d.size>>20),cap);d.size=(NSUInteger)cap<<20;}
    if((NSUInteger)d.storageMode==1){d=[d copy];d.storageMode=MTLStorageModeShared;}
    id h=((id(*)(id,SEL,id))origHeap)(s,c,d);if(h)watch_heap(h);
    return h;
}
static IMP wrap(Class cls,SEL sel,IMP replacement) {
    Method m=class_getInstanceMethod(cls,sel);if(!m)return NULL;IMP original=method_getImplementation(m);
    // Add on the concrete class so only Metal objects of this device change.
    if(!class_addMethod(cls,sel,replacement,method_getTypeEncoding(m)))method_setImplementation(class_getInstanceMethod(cls,sel),replacement);
    return original;
}
void mp_cp_metal_install(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        device=MTLCreateSystemDefaultDevice();Class d=object_getClass(device);
        // macOS-only MTLDevice queries (API_UNAVAILABLE(ios)).
        add(d,@selector(isDepth24Stencil8PixelFormatSupported),(IMP)no,"B@:");   // Apple GPUs use Depth32Float_Stencil8.
        add(d,@selector(areBarycentricCoordsSupported),(IMP)barycentric,"B@:");
        add(d,@selector(isLowPower),(IMP)no,"B@:");add(d,@selector(isHeadless),(IMP)no,"B@:");add(d,@selector(isRemovable),(IMP)no,"B@:");
        add(d,@selector(location),(IMP)zero,"Q@:");add(d,@selector(locationNumber),(IMP)zero,"Q@:");add(d,@selector(maxTransferRate),(IMP)zero,"Q@:");
        add(d,@selector(peerGroupID),(IMP)zero,"Q@:");add(d,@selector(peerIndex),(IMP)zero32,"I@:");add(d,@selector(peerCount),(IMP)one32,"I@:");
        origBufLen=wrap(d,@selector(newBufferWithLength:options:),(IMP)buf_len);
        origBufBytes=wrap(d,@selector(newBufferWithBytes:length:options:),(IMP)buf_bytes);
        origBufNoCopy=wrap(d,@selector(newBufferWithBytesNoCopy:length:options:deallocator:),(IMP)buf_nocopy);
        origTex=wrap(d,@selector(newTextureWithDescriptor:),(IMP)tex);
        origHeap=wrap(d,@selector(newHeapWithDescriptor:),(IMP)heap);
        if(@available(iOS 18.0,*)){   // Before any queue exists, so every queue gets it.
            MTLResidencySetDescriptor *rs=[MTLResidencySetDescriptor new];rs.label=@"machprobe spill-over heaps";rs.initialCapacity=32;
            spillSet=[device newResidencySetWithDescriptor:rs error:NULL];
        }
        if(spillSet){
            origQueue=wrap(d,@selector(newCommandQueue),(IMP)queue_plain);
            origQueueMax=wrap(d,@selector(newCommandQueueWithMaxCommandBufferCount:),(IMP)queue_max);
            origQueueDesc=wrap(d,@selector(newCommandQueueWithDescriptor:),(IMP)queue_desc);
        }
        // macOS-only managed-resource synchronisation: no-ops on unified memory.
        id<MTLBuffer> b=[device newBufferWithLength:16 options:MTLResourceStorageModeShared];add(object_getClass(b),@selector(didModifyRange:),(IMP)nop_range,"v@:{_NSRange=QQ}");
        id<MTLCommandQueue> q=[device newCommandQueue];id<MTLCommandBuffer> cb=[q commandBuffer];id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder];
        add(object_getClass(blit),@selector(synchronizeResource:),(IMP)nop1,"v@:@");
        add(object_getClass(blit),@selector(synchronizeTexture:slice:level:),(IMP)nop_tex,"v@:@QQ");
        [blit endEncoding];
    });
}
void *mp_cp_metal_devices(void) {mp_cp_metal_install();return (__bridge_retained void *)@[device];}
id<MTLDevice> mp_cp_metal_default_device(void) {mp_cp_metal_install();return device;}
NSDictionary *mp_cp_metal_features(void) {
    mp_cp_metal_install();NSMutableDictionary *f=[NSMutableDictionary dictionary];
    for(NSNumber *n in @[@(MTLGPUFamilyApple7),@(MTLGPUFamilyApple8),@(MTLGPUFamilyApple9),@(MTLGPUFamilyApple10),@(MTLGPUFamilyMac2),@(MTLGPUFamilyMetal3),@(MTLGPUFamilyMetal4)])
        f[n.stringValue]=@([device supportsFamily:(MTLGPUFamily)n.integerValue]);
    return @{@"name":device.name?:@"",@"families":f,@"bc_textures":@([device respondsToSelector:@selector(supportsBCTextureCompression)] && device.supportsBCTextureCompression),
             @"recommended_working_set":@(device.recommendedMaxWorkingSetSize),@"max_buffer":@(device.maxBufferLength)};
}

// GPU busy time: every command buffer's GPUEndTime-GPUStartTime, summed (the
// GPU runs one at a time per queue, so the sum approximates busy time).
static _Atomic uint64_t gpuBusyNanos;static IMP origCommit;
static void counted_commit(id cb,SEL c){
    [cb addCompletedHandler:^(id<MTLCommandBuffer> b){double t=b.GPUEndTime-b.GPUStartTime;if(t>0 && t<1)gpuBusyNanos+=(uint64_t)(t*1e9);}];
    ((void(*)(id,SEL))origCommit)(cb,c);
}
uint64_t mp_cp_gpu_busy_nanos(void){return gpuBusyNanos;}
void mp_cp_gpu_timing_install(id<MTLDevice> device) {
    static dispatch_once_t once;dispatch_once(&once,^{
        id<MTLCommandQueue> q=[device newCommandQueue];id cb=[q commandBuffer];
        Method m=class_getInstanceMethod(object_getClass(cb),@selector(commit));
        if(m){origCommit=method_getImplementation(m);method_setImplementation(m,(IMP)counted_commit);}
    });
}
