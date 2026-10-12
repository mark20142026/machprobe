// Frame pacing as seen by Core Animation: every Metal presenter, including
// MoltenVK's swapchain, takes one drawable per frame from -[CAMetalLayer
// nextDrawable]. Records acquisition times in a rolling window. This is the
// guest's frame production rate, not a display-scanout measurement.
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <pthread.h>
#define WINDOW 240
static double times[WINDOW];static uint64_t count;
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static id (*original)(id,SEL);
static id next_drawable(id self,SEL _cmd) {
    id drawable=original(self,_cmd);double now=CACurrentMediaTime();
    pthread_mutex_lock(&lock);times[count++%WINDOW]=now;pthread_mutex_unlock(&lock);
    return drawable;
}
__attribute__((constructor)) static void install(void) {
    Method m=class_getInstanceMethod(CAMetalLayer.class,@selector(nextDrawable));
    original=(id (*)(id,SEL))method_setImplementation(m,(IMP)next_drawable);
}
NSDictionary *mp_stk_frame_window(void) {
    pthread_mutex_lock(&lock);
    uint64_t n=count;unsigned k=(unsigned)MIN(n,(uint64_t)WINDOW);double t[WINDOW];
    for(unsigned i=0;i<k;i++)t[i]=times[(n-k+i)%WINDOW];
    pthread_mutex_unlock(&lock);
    if(k<2)return @{@"drawables":@(n)};
    double span=t[k-1]-t[0],worst=0;
    // Last-second rate too, so a menu->race transition shows quickly.
    unsigned recent=0;for(unsigned i=0;i<k;i++)if(t[k-1]-t[i]<=1.0)recent++;
    for(unsigned i=1;i<k;i++)if(t[i]-t[i-1]>worst)worst=t[i]-t[i-1];
    return @{@"drawables":@(n),@"window_frames":@(k),@"window_seconds":@(span),@"window_fps":@((k-1)/span),
             @"last_second_frames":@(recent),@"worst_interval_ms":@(worst*1000),@"seconds_since_last":@(CACurrentMediaTime()-t[k-1])};
}
