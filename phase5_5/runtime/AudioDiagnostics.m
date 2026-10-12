#include <AudioToolbox/AudioToolbox.h>
#import <AVFAudio/AVFAudio.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdatomic.h>
#include <math.h>
// The iOS SDK omits the desktop HAL address declaration. The public macOS
// AudioHardwareBase.h ABI is three UInt32 values, independent of pointer size.
typedef struct {UInt32 selector,scope,element;} MPHALAddress;
static _Atomic unsigned traces;
static void log_property(const char *operation,UInt32 object,const MPHALAddress *a,OSStatus status,UInt32 size) {
    if(atomic_fetch_add(&traces,1)>=64)return;
    fprintf(stderr,"AUDIO %s object=%u selector=%08x scope=%08x element=%u status=%d bytes=%u\n",operation,object,a?a->selector:0,a?a->scope:0,a?a->element:0,(int)status,size);
}
static OSStatus get_data(UInt32 object,const MPHALAddress *a,UInt32 qualifierSize,const void *qualifier,UInt32 *size,void *data) {
    typedef OSStatus(*Fn)(UInt32,const MPHALAddress *,UInt32,const void *,UInt32 *,void *);
    Fn fn=(Fn)dlsym(RTLD_DEFAULT,"AudioObjectGetPropertyData");
    UInt32 capacity=size?*size:0;
    if(a && a->selector==0x66737a23)fprintf(stderr,"AUDIO quantum capacity=%u duration=%f rate=%f\n",capacity,AVAudioSession.sharedInstance.IOBufferDuration,AVAudioSession.sharedInstance.sampleRate);
    OSStatus status=fn?fn(object,a,qualifierSize,qualifier,size,data):-4;
    // Desktop HAL's deprecated device stream-format property is absent on
    // this iOS output device. Query the public RemoteIO output input bus.
    if(status && a && a->selector==0x73666d74 && a->scope==0x6f757470 && a->element==0 && size && data && capacity>=sizeof(AudioStreamBasicDescription)) {
        MPHALAddress address={0x644f7574,0x676c6f62,0};UInt32 device=0,bytes=sizeof(device);
        if(fn && !fn(1,&address,0,NULL,&bytes,&device) && device==object) {
            NSError *error=nil;
            BOOL active=[AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:&error] && [AVAudioSession.sharedInstance setActive:YES error:&error];
            AudioComponentDescription desc={kAudioUnitType_Output,kAudioUnitSubType_RemoteIO,kAudioUnitManufacturer_Apple,0,0};
            AudioComponent component=AudioComponentFindNext(NULL,&desc);AudioUnit unit=NULL;
            if(active && component && !AudioComponentInstanceNew(component,&unit)) {
                *size=sizeof(AudioStreamBasicDescription);
                status=AudioUnitGetProperty(unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,data,size);
                AudioComponentInstanceDispose(unit);
            }
        }
    }
    if(status && a && a->selector==0x66737a23 && a->scope==0x676c6f62 && a->element==0 && size && data && capacity>=sizeof(AudioValueRange)) {
        MPHALAddress address={0x644f7574,0x676c6f62,0};UInt32 device=0,bytes=sizeof(device);
        if(fn && !fn(1,&address,0,NULL,&bytes,&device) && device==object) {
            // Only promise the currently active iOS quantum, not a made-up
            // hardware range or arbitrary HAL buffer reconfiguration.
            double frames=round(AVAudioSession.sharedInstance.IOBufferDuration*AVAudioSession.sharedInstance.sampleRate);
            if(frames<=0) {
                MPHALAddress quantum={0x6673697a,0x676c6f62,0};UInt32 current=0,n=sizeof(current);
                OSStatus query=fn(object,&quantum,0,NULL,&n,&current);
                fprintf(stderr,"AUDIO native buffer quantum status=%d size=%u frames=%u\n",(int)query,n,current);
                if(!query && n==sizeof(current))frames=current;
            }
            if(frames>0){*(AudioValueRange *)data=(AudioValueRange){frames,frames};*size=sizeof(AudioValueRange);status=0;}
        }
    }
    log_property("HAL get",object,a,status,size?*size:0);return status;
}
static OSStatus get_size(UInt32 object,const MPHALAddress *a,UInt32 qualifierSize,const void *qualifier,UInt32 *size) {
    typedef OSStatus(*Fn)(UInt32,const MPHALAddress *,UInt32,const void *,UInt32 *);
    Fn fn=(Fn)dlsym(RTLD_DEFAULT,"AudioObjectGetPropertyDataSize");
    OSStatus status=fn?fn(object,a,qualifierSize,qualifier,size):-4;
    log_property("HAL size",object,a,status,size?*size:0);return status;
}
static OSStatus unit_get(AudioUnit unit,AudioUnitPropertyID property,AudioUnitScope scope,AudioUnitElement element,void *data,UInt32 *size) {
    OSStatus status=AudioUnitGetProperty(unit,property,scope,element,data,size);
    MPHALAddress a={property,scope,element};log_property("unit get",0,&a,status,size?*size:0);return status;
}
static OSStatus unit_set(AudioUnit unit,AudioUnitPropertyID property,AudioUnitScope scope,AudioUnitElement element,const void *data,UInt32 size) {
    OSStatus status=AudioUnitSetProperty(unit,property,scope,element,data,size);
    MPHALAddress a={property,scope,element};log_property("unit set",0,&a,status,size);return status;
}
static AudioComponent find_component(AudioComponent previous,const AudioComponentDescription *description) {
    AudioComponent result=AudioComponentFindNext(previous,description);
    if(atomic_fetch_add(&traces,1)<64 && description)fprintf(stderr,"AUDIO component type=%08x subtype=%08x found=%d\n",description->componentType,description->componentSubType,result!=NULL);
    return result;
}
void *mp_audio_diagnostic_symbol(const char *symbol) {
    if(!strcmp(symbol,"_AudioObjectGetPropertyData"))return (void *)&get_data;
    if(!strcmp(symbol,"_AudioObjectGetPropertyDataSize"))return (void *)&get_size;
    if(!strcmp(symbol,"_AudioUnitGetProperty"))return (void *)&unit_get;
    if(!strcmp(symbol,"_AudioUnitSetProperty"))return (void *)&unit_set;
    if(!strcmp(symbol,"_AudioComponentFindNext"))return (void *)&find_component;
    return NULL;
}
