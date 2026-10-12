#import "Observe.h"
#import <AVFAudio/AVFAudio.h>
#import <objc/runtime.h>
#include <stdatomic.h>
#include <math.h>
extern void mp_game_trace(NSString *event);
static uint64_t frames;static double firstTime,lastTime,guestCPU,maxCPU;
@interface MPDrawObserver:NSObject<MTKViewDelegate>
@property(nonatomic,weak) id<MTKViewDelegate> guest;
@end
@implementation MPDrawObserver
- (void)drawInMTKView:(MTKView *)view {
    double start=CACurrentMediaTime();if(!frames)firstTime=start;
    [self.guest drawInMTKView:view];
    double elapsed=CACurrentMediaTime()-start;frames++;lastTime=start;guestCPU+=elapsed;if(elapsed>maxCPU)maxCPU=elapsed;
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {[self.guest mtkView:view drawableSizeWillChange:size];}
@end
void mp_game_observe_view(UIView *view) {
    if(![view isKindOfClass:MTKView.class])return;
    MTKView *metal=(MTKView *)view;if(!metal.delegate)return;
    MPDrawObserver *observer=[MPDrawObserver new];observer.guest=metal.delegate;
    objc_setAssociatedObject(view,@selector(mp_game_observe_view),observer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);metal.delegate=observer;
}
NSDictionary *mp_game_frame_stats(void) {
    double seconds=lastTime-firstTime;
    return @{@"guest_draw_callbacks":@(frames),@"elapsed_seconds":@(seconds),@"average_fps":@(seconds>0?(frames-1)/seconds:0),@"mean_guest_callback_ms":@(frames?guestCPU*1000/frames:0),@"max_guest_callback_ms":@(maxCPU*1000)};
}
static _Atomic uint64_t audioFrames,nonzeroSamples;
static _Atomic unsigned peakMicros;
static BOOL audioStarted;static NSString *audioError;
@interface MPObservedAudioEngine:AVAudioEngine @end
@implementation MPObservedAudioEngine
- (BOOL)startAndReturnError:(NSError **)error {
    // Observe the real mix, without replacing the game's source node or samples.
    [self.mainMixerNode installTapOnBus:0 bufferSize:1024 format:nil block:^(AVAudioPCMBuffer *buffer,AVAudioTime *time){
        atomic_fetch_add_explicit(&audioFrames,buffer.frameLength,memory_order_relaxed);
        if(!buffer.floatChannelData)return;
        float peak=0;uint64_t active=0;
        for(AVAudioFrameCount frame=0;frame<buffer.frameLength;frame++){
            float value=fabsf(buffer.floatChannelData[0][frame*buffer.stride]);if(value>1e-6f)active++;if(value>peak)peak=value;
        }
        atomic_fetch_add_explicit(&nonzeroSamples,active,memory_order_relaxed);
        unsigned p=(unsigned)(fminf(peak,100)*1000000),old=atomic_load_explicit(&peakMicros,memory_order_relaxed);
        while(p>old && !atomic_compare_exchange_weak_explicit(&peakMicros,&old,p,memory_order_relaxed,memory_order_relaxed)){}
    }];
    NSError *failure=nil;BOOL ok=[super startAndReturnError:&failure];audioStarted=ok;audioError=failure.description;
    if(error)*error=failure;mp_game_trace(ok?@"guest AVAudioEngine started":[@"guest AVAudioEngine failed: " stringByAppendingString:audioError?:@"unknown"]);return ok;
}
@end
Class mp_game_audio_engine_class(void){return MPObservedAudioEngine.class;}
NSDictionary *mp_game_audio_stats(void){return @{@"engine_started":@(audioStarted),@"error":audioError?:@"",@"frames_observed":@(atomic_load(&audioFrames)),@"nonzero_samples":@(atomic_load(&nonzeroSamples)),@"peak_absolute":@(atomic_load(&peakMicros)/1000000.0)};}
