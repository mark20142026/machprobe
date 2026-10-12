#import "MetalCompat.h"
#import <QuartzCore/QuartzCore.h>
extern NSDictionary *mp_metal_probe(void);
extern void mp_game_trace(NSString *);
// Experimental desktop API profile, not a claim the iOS driver advertises a
// Mac GPU family. Old Mac clients cannot express individual capability queries.
// Keep modern family queries native and reject later legacy feature sets.
#include <pthread.h>
static pthread_mutex_t presentationLock=PTHREAD_MUTEX_INITIALIZER;
static uint64_t presentedFrames,presentRequests,completedPresentBuffers,failedPresentBuffers;
static double firstCompletion,lastCompletion;
static double firstPresentation,lastPresentation;
// Rolling window over the most recent presenting command buffers. Cumulative
// rates above mix title-screen and gameplay intervals; these do not. Request
// times are when the guest asks to present (its own frame pacing); GPU times
// come from the completed buffer and show whether the GPU is the limit.
#define MP_WINDOW 240
static double requestTimes[MP_WINDOW],gpuMillis[MP_WINDOW];
static uint64_t gpuSamples,allBuffers,buffersAlive,buffersCreated,handlersFired;static double allGPUSeconds;
static int compare_doubles(const void *a,const void *b){double x=*(const double *)a,y=*(const double *)b;return (x>y)-(x<y);}
static double percentile(double *sorted,unsigned n,double p){return n?sorted[(unsigned)(p*(n-1)+.5)]:0;}
NSDictionary *mp_legacy_presentation_stats(void) {
    pthread_mutex_lock(&presentationLock);
    uint64_t count=presentedFrames,requests=presentRequests;
    double elapsed=lastPresentation-firstPresentation;
    uint64_t completed=completedPresentBuffers,failed=failedPresentBuffers;double completionElapsed=lastCompletion-firstCompletion;
    unsigned n=(unsigned)MIN(requests,(uint64_t)MP_WINDOW),g=(unsigned)MIN(gpuSamples,(uint64_t)MP_WINDOW);
    double intervals[MP_WINDOW],gpu[MP_WINDOW],newest=0,oldest=0;
    // Walk the ring oldest to newest.
    for(unsigned i=0,previous=0;i<n;i++){
        double t=requestTimes[(requests-n+i)%MP_WINDOW];
        if(i)intervals[i-1]=(t-requestTimes[previous])*1000;else oldest=t;
        previous=(unsigned)((requests-n+i)%MP_WINDOW);newest=t;
    }
    memcpy(gpu,gpuMillis,sizeof(double)*g);
    pthread_mutex_unlock(&presentationLock);
    NSMutableDictionary *result=[@{@"gpu_completed_present_buffers":@(completed),@"gpu_failed_present_buffers":@(failed),@"gpu_completion_elapsed_seconds":@(completionElapsed),@"gpu_present_buffer_rate":@(completionElapsed>0?(completed-1)/completionElapsed:0),@"present_requests":@(requests),@"presented_frames":@(count),@"all_buffers_completed":@(allBuffers),@"wrappers_created":@(buffersCreated),@"wrappers_alive":@(buffersAlive),@"presented_handlers_fired":@(handlersFired),@"all_buffers_gpu_seconds":@(allGPUSeconds),@"elapsed_seconds":@(elapsed),@"average_presented_fps":@(elapsed>0?(count-1)/elapsed:0)} mutableCopy];
    if(n>1){
        qsort(intervals,n-1,sizeof(double),compare_doubles);qsort(gpu,g,sizeof(double),compare_doubles);
        double age=CACurrentMediaTime()-newest;
        result[@"window"]=@{@"frames":@(n),@"seconds":@(newest-oldest),@"request_fps":@((n-1)/(newest-oldest)),
            @"interval_ms_p50":@(percentile(intervals,n-1,.5)),@"interval_ms_p95":@(percentile(intervals,n-1,.95)),@"interval_ms_max":@(intervals[n-2]),
            @"gpu_ms_p50":@(percentile(gpu,g,.5)),@"gpu_ms_p95":@(percentile(gpu,g,.95)),@"seconds_since_last_request":@(age)};
    }
    return result;
}
static void observe_drawable(id<MTLDrawable> drawable) {
    double now=CACurrentMediaTime();
    pthread_mutex_lock(&presentationLock);requestTimes[presentRequests%MP_WINDOW]=now;presentRequests++;pthread_mutex_unlock(&presentationLock);
    [drawable addPresentedHandler:^(id<MTLDrawable> result){
        double time=result.presentedTime;
        pthread_mutex_lock(&presentationLock);handlersFired++;
        if(time>0){if(!presentedFrames)firstPresentation=time;lastPresentation=time;presentedFrames++;}
        pthread_mutex_unlock(&presentationLock);
    }];
}
@interface MPPresentBuffer:NSObject
@property(nonatomic,strong) id<MTLCommandBuffer> native;
@property BOOL presenting;
@end
@implementation MPPresentBuffer
- (instancetype)init {if((self=[super init])){pthread_mutex_lock(&presentationLock);buffersAlive++;buffersCreated++;pthread_mutex_unlock(&presentationLock);}return self;}
- (void)dealloc {pthread_mutex_lock(&presentationLock);buffersAlive--;pthread_mutex_unlock(&presentationLock);}
- (void)commit {
    BOOL presenting=self.presenting;
    [self.native addCompletedHandler:^(id<MTLCommandBuffer> buffer){
        double time=CACurrentMediaTime(),span=buffer.GPUEndTime-buffer.GPUStartTime;
        pthread_mutex_lock(&presentationLock);
        if(span>0){allGPUSeconds+=span;allBuffers++;}
        if(!presenting){pthread_mutex_unlock(&presentationLock);return;}
        if(buffer.status==MTLCommandBufferStatusCompleted){
            if(!completedPresentBuffers)firstCompletion=time;lastCompletion=time;completedPresentBuffers++;
            double gpu=(buffer.GPUEndTime-buffer.GPUStartTime)*1000;
            if(gpu>0)gpuMillis[gpuSamples++%MP_WINDOW]=gpu;
        }
        else failedPresentBuffers++;
        pthread_mutex_unlock(&presentationLock);
    }];
    [self.native commit];
}
- (id)forwardingTargetForSelector:(SEL)s {return self.native;}
- (BOOL)respondsToSelector:(SEL)s {return [super respondsToSelector:s] || [self.native respondsToSelector:s];}
- (BOOL)conformsToProtocol:(Protocol *)p {return [super conformsToProtocol:p] || [self.native conformsToProtocol:p];}
// Diagnostics hooks: no-op weak defaults; phase6/runtime/DrawProbe.m overrides.
__attribute__((weak)) id mp_draw_probe_wrap(id encoder){return encoder;}
extern id mp_base_vertex_wrap(id encoder);
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)d {
    id<MTLRenderCommandEncoder> e=mp_base_vertex_wrap([self.native renderCommandEncoderWithDescriptor:d]);
    return mp_draw_probe_wrap(e);
}
- (void)presentDrawable:(id<MTLDrawable>)d {self.presenting=YES;observe_drawable(d);[self.native presentDrawable:d];}
- (void)presentDrawable:(id<MTLDrawable>)d atTime:(CFTimeInterval)t {self.presenting=YES;observe_drawable(d);[self.native presentDrawable:d atTime:t];}
- (void)presentDrawable:(id<MTLDrawable>)d afterMinimumDuration:(CFTimeInterval)t {self.presenting=YES;observe_drawable(d);[self.native presentDrawable:d afterMinimumDuration:t];}
@end
@interface MPPresentQueue:NSObject
@property(nonatomic,strong) id<MTLCommandQueue> native;
@end
@implementation MPPresentQueue
- (id)forwardingTargetForSelector:(SEL)s {return self.native;}
- (BOOL)respondsToSelector:(SEL)s {return [super respondsToSelector:s] || [self.native respondsToSelector:s];}
- (BOOL)conformsToProtocol:(Protocol *)p {return [super conformsToProtocol:p] || [self.native conformsToProtocol:p];}
- (id<MTLCommandBuffer>)wrap:(id<MTLCommandBuffer>)native {
    if(!native)return nil;MPPresentBuffer *buffer=[MPPresentBuffer new];buffer.native=native;return (id)buffer;
}
- (id<MTLCommandBuffer>)commandBuffer {return [self wrap:self.native.commandBuffer];}
- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences {return [self wrap:self.native.commandBufferWithUnretainedReferences];}
- (id<MTLCommandBuffer>)commandBufferWithDescriptor:(MTLCommandBufferDescriptor *)descriptor {return [self wrap:[self.native commandBufferWithDescriptor:descriptor]];}
@end
@interface MPLegacyMetalDevice:NSObject
@property(nonatomic,strong) id<MTLDevice> adapted;
@property BOOL borderVerified;
@end
@implementation MPLegacyMetalDevice
- (id<MTLCommandQueue>)newCommandQueue {
    id<MTLCommandQueue> native=[self.adapted newCommandQueue];if(!native)return nil;
    MPPresentQueue *queue=[MPPresentQueue new];queue.native=native;return (id)queue;
}
- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)count {
    id<MTLCommandQueue> native=[self.adapted newCommandQueueWithMaxCommandBufferCount:count];if(!native)return nil;
    MPPresentQueue *queue=[MPPresentQueue new];queue.native=native;return (id)queue;
}
__attribute__((weak)) void mp_draw_probe_note_pipeline(id pipeline,MTLRenderPipelineDescriptor *descriptor){}
extern void mp_base_vertex_note_pipeline(id pipeline,MTLRenderPipelineDescriptor *descriptor);
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d error:(NSError **)error {
    id<MTLRenderPipelineState> p=[self.adapted newRenderPipelineStateWithDescriptor:d error:error];
    mp_base_vertex_note_pipeline(p,d);
    mp_draw_probe_note_pipeline(p,d);return p;
}
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)d completionHandler:(MTLNewRenderPipelineStateCompletionHandler)handler {
    [self.adapted newRenderPipelineStateWithDescriptor:d completionHandler:^(id<MTLRenderPipelineState> p,NSError *e){
        mp_base_vertex_note_pipeline(p,d);
        mp_draw_probe_note_pipeline(p,d);handler(p,e);
    }];
}
- (BOOL)isLowPower {return YES;} // The single integrated iOS GPU; no discrete-GPU selection.
// macOS-only MTLDevice queries (API_UNAVAILABLE(ios)) answered for the
// built-in Apple GPU. A real iPhone GPU object does not implement them
// (the VM's paravirtual device happened to): unrecognized-selector crash.
- (BOOL)isDepth24Stencil8PixelFormatSupported {return NO;} // macOS-only pixel format; Apple GPUs use Depth32Float_Stencil8.
- (BOOL)areBarycentricCoordsSupported {return [self.adapted respondsToSelector:@selector(supportsShaderBarycentricCoordinates)] && self.adapted.supportsShaderBarycentricCoordinates;}
- (BOOL)isRemovable {return NO;}
- (NSUInteger)location {return 0;}        // MTLDeviceLocationBuiltIn
- (NSUInteger)locationNumber {return 0;}
- (uint64_t)maxTransferRate {return 0;}   // 0 for built-in GPUs.
- (uint64_t)peerGroupID {return 0;}
- (uint32_t)peerIndex {return 0;}
- (uint32_t)peerCount {return 1;}
- (BOOL)isHeadless {return NO;} // This GPU drives the UIKit presentation surface.
static NSCountedSet *forwardedSelectors;
// Hosts whose guest infers whole capability bundles from legacy Mac feature
// sets (MoltenVK enables BC formats from macOS_GPUFamily1) turn this off.
static BOOL legacyProfile=YES;
void mp_legacy_set_mac_profile(BOOL enabled){legacyProfile=enabled;}
NSDictionary *mp_legacy_forwarded_selectors(void){
    NSMutableDictionary *d=[NSMutableDictionary dictionary];@synchronized(MPLegacyMetalDevice.class){for(NSString *s in forwardedSelectors)d[s]=@([forwardedSelectors countForObject:s]);}return d;
}
- (id)forwardingTargetForSelector:(SEL)selector {
    @synchronized(MPLegacyMetalDevice.class){if(!forwardedSelectors)forwardedSelectors=[NSCountedSet new];if(forwardedSelectors.count<300)[forwardedSelectors addObject:NSStringFromSelector(selector)];}
    return self.adapted;
}
- (BOOL)respondsToSelector:(SEL)s {return [super respondsToSelector:s] || [self.adapted respondsToSelector:s];}
- (BOOL)conformsToProtocol:(Protocol *)p {return [super conformsToProtocol:p] || [self.adapted conformsToProtocol:p];}
- (BOOL)supportsFeatureSet:(MTLFeatureSet)set {
    if([self.adapted supportsFeatureSet:set])return YES;
    if(!legacyProfile)return NO;
    // These legacy sets bundle further promises (notably desktop texture
    // formats). Their full conformance is UNVERIFIED; unsupported actual uses
    // must fail visibly, and this research profile cannot certify Mac support.
    BOOL answer=self.borderVerified && [self.adapted supportsFamily:MTLGPUFamilyApple5] && (set==10000 || set==10001);
    mp_game_trace([NSString stringWithFormat:@"experimental legacy Metal feature set %lu = %d",(unsigned long)set,answer]);
    return answer;
}
@end
NSArray *mp_legacy_copy_metal_devices(void) NS_RETURNS_RETAINED;
NSArray *mp_legacy_copy_metal_devices(void) {
    static NSArray *devices;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSDictionary *probe=mp_metal_probe();BOOL verified=[probe[@"passed"] boolValue];
        mp_game_trace(verified?@"native GPU border sampling verified (six cases)":@"native GPU border sampling probe failed");
        extern void mp_base_vertex_detect(id<MTLDevice>);mp_base_vertex_detect(MTLCreateSystemDefaultDevice());
        MPLegacyMetalDevice *device=[MPLegacyMetalDevice new];device.adapted=mp_game_wrap_metal_device(MTLCreateSystemDefaultDevice());device.borderVerified=verified;
        devices=device.adapted?@[device]:@[];
    });
    return [devices copy];
}
