// Hang diagnostics: if the guest's main loop stops pumping events, record the
// main thread's stack (frame-pointer walk, symbolized with dladdr, which also
// resolves guest images through the loader). Read-only observation.
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
static _Atomic uint64_t heartbeat;
static mach_port_t mainThread;
void mp_watchdog_beat(void){atomic_fetch_add_explicit(&heartbeat,1,memory_order_relaxed);}
extern void mp_game_trace(NSString *);
static NSString *describe(uintptr_t pc) {
    Dl_info info={0};
    // Guest addresses resolve through the loader's dladdr; host ones through dyld.
    extern void *mp_group_dl_import(const char *);
    int (*guest_dladdr)(const void *,Dl_info *)=(int (*)(const void *,Dl_info *))mp_group_dl_import("_dladdr");
    if(guest_dladdr(((void *)pc),&info) && info.dli_fname) {
        const char *file=strrchr(info.dli_fname,'/');
        return [NSString stringWithFormat:@"%s %s+0x%lx (img+0x%lx)",file?file+1:info.dli_fname,info.dli_sname?:"?",
                (unsigned long)(pc-(uintptr_t)info.dli_saddr),(unsigned long)(pc-(uintptr_t)info.dli_fbase)];
    }
    return [NSString stringWithFormat:@"0x%lx",(unsigned long)pc];
}
NSArray *mp_watchdog_main_stack(void) {
    NSMutableArray *frames=[NSMutableArray array];
    if(thread_suspend(mainThread)!=KERN_SUCCESS)return frames;
    arm_thread_state64_t state;mach_msg_type_number_t count=ARM_THREAD_STATE64_COUNT;
    if(thread_get_state(mainThread,ARM_THREAD_STATE64,(thread_state_t)&state,&count)==KERN_SUCCESS) {
        uintptr_t pc=(uintptr_t)arm_thread_state64_get_pc(state),lr=(uintptr_t)arm_thread_state64_get_lr(state),fp=(uintptr_t)arm_thread_state64_get_fp(state);
        uintptr_t pcs[64];unsigned n=0;pcs[n++]=pc;pcs[n++]=lr;
        // Walk saved {fp, lr} pairs while they look like a valid stack chain.
        for(unsigned i=0;i<60 && fp && !(fp&7);i++){uintptr_t *frame=(uintptr_t *)fp;uintptr_t next=frame[0],ret=frame[1];if(!ret)break;pcs[n++]=ret&0x0000000fffffffffull;if(n>=64 || next<=fp)break;fp=next;}
        thread_resume(mainThread);
        for(unsigned i=0;i<n;i++)[frames addObject:describe(pcs[i])];
        return frames;
    }
    thread_resume(mainThread);return frames;
}
static void (^sampler)(NSArray *);
void mp_watchdog_set_sampler(void (^block)(NSArray *)){sampler=block;}
void mp_watchdog_start(void (^report)(NSArray *stack)) {
    mainThread=mach_thread_self();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        uint64_t last=0;unsigned stalled=0;
        for(;;) {
            sleep(1);uint64_t now=atomic_load(&heartbeat);
            static unsigned tick;if(++tick%10==0 && sampler)sampler(mp_watchdog_main_stack());
            if(now!=last){last=now;stalled=0;continue;}
            if(++stalled>=5 && (stalled-5)%15==0)report(mp_watchdog_main_stack()); // At 5 s, then every 15 s.
        }
    });
}
