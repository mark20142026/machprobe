#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#include <stdatomic.h>
static _Atomic unsigned callbacks, lastFrames;
static OSStatus silence(void *context,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,UInt32 bus,UInt32 frames,AudioBufferList *buffers) {
    atomic_fetch_add(&callbacks,1);atomic_store(&lastFrames,frames);
    for(UInt32 i=0;i<buffers->mNumberBuffers;i++)memset(buffers->mBuffers[i].mData,0,buffers->mBuffers[i].mDataByteSize);
    return noErr;
}
static NSDictionary *sessionInfo(void) {
    AVAudioSession *s=AVAudioSession.sharedInstance;NSMutableArray *outputs=[NSMutableArray new];
    for(AVAudioSessionPortDescription *port in s.currentRoute.outputs)[outputs addObject:@{@"type":port.portType,@"name":port.portName}];
    return @{@"sample_rate":@(s.sampleRate),@"duration":@(s.IOBufferDuration),@"channels":@(s.outputNumberOfChannels),@"outputs":outputs};
}
extern void mp_audio_probe_finished(NSDictionary *result);
@interface MPAudioProbe:NSObject
- (void)runProbe;
@end
@implementation MPAudioProbe
- (void)runProbe {
    NSMutableDictionary *result=[NSMutableDictionary new];result[@"before"]=sessionInfo();
    NSError *error=nil;BOOL category=[AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:&error];
    result[@"category_ok"]=@(category);result[@"category_error"]=error.description?:@"";error=nil;
    BOOL active=[AVAudioSession.sharedInstance setActive:YES error:&error];result[@"active_ok"]=@(active);result[@"active_error"]=error.description?:@"";
    result[@"active_session"]=sessionInfo();
    AudioComponentDescription description={kAudioUnitType_Output,kAudioUnitSubType_RemoteIO,kAudioUnitManufacturer_Apple,0,0};
    AudioComponent component=AudioComponentFindNext(NULL,&description);result[@"component_found"]=@(component!=NULL);
    AudioUnit unit=NULL;OSStatus create=component?AudioComponentInstanceNew(component,&unit):-1;result[@"create_status"]=@(create);
    if(create){result[@"passed"]=@NO;mp_audio_probe_finished(result);return;}
    AudioStreamBasicDescription format={0};UInt32 bytes=sizeof(format);
    OSStatus formatStatus=AudioUnitGetProperty(unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&format,&bytes);
    result[@"format_status"]=@(formatStatus);result[@"format"]=@{@"rate":@(format.mSampleRate),@"channels":@(format.mChannelsPerFrame),@"bytes_per_frame":@(format.mBytesPerFrame),@"flags":@(format.mFormatFlags)};
    UInt32 maximum=0;bytes=sizeof(maximum);OSStatus maxStatus=AudioUnitGetProperty(unit,kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,&maximum,&bytes);
    result[@"maximum_status"]=@(maxStatus);result[@"maximum_frames_per_slice"]=@(maximum);
    AURenderCallbackStruct callback={silence,NULL};OSStatus set=AudioUnitSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&callback,sizeof(callback));result[@"callback_status"]=@(set);
    OSStatus initialize=AudioUnitInitialize(unit);result[@"initialize_status"]=@(initialize);
    OSStatus start=initialize?initialize:AudioOutputUnitStart(unit);result[@"start_status"]=@(start);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        result[@"callbacks"]=@(atomic_load(&callbacks));result[@"last_frames"]=@(atomic_load(&lastFrames));result[@"running_session"]=sessionInfo();
        result[@"stop_status"]=@(AudioOutputUnitStop(unit));result[@"uninitialize_status"]=@(AudioUnitUninitialize(unit));result[@"dispose_status"]=@(AudioComponentInstanceDispose(unit));
        result[@"passed"]=@(category && active && !formatStatus && !set && !initialize && !start && atomic_load(&callbacks)>0);
        mp_audio_probe_finished(result);
    });
}
@end
void mp_start_audio_probe(void) {[[MPAudioProbe new] runProbe];}
