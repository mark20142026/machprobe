// Cyberpunk 2077 imports that iOS lacks and earlier phases do not cover,
// from the offline SDK gap analysis (phase8/tools/import_gaps.py). Values were
// measured on macOS (docs/evidence/phase8-desktop-constants.txt). Display
// answers describe the single built-in iOS screen (ID 1, as Phase 5.5);
// unavailable services fail with their framework's own error codes.
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#include <string.h>

// ---- AppKit string constants (each measured equal to its own name) ---------
static NSString *const cpConstantNames[]={@"NSApplicationDidChangeScreenParametersNotification",@"NSApplicationDidResignActiveNotification",
    @"NSEventTrackingRunLoopMode",@"NSImageHintInterpolation",@"NSWindowDidBecomeKeyNotification",@"NSWindowDidResignKeyNotification",
    @"NSWindowDidResizeNotification",@"NSWindowWillCloseNotification",@"NSWindowWillExitFullScreenNotification"};
static NSString *cpConstantValues[9];

// ---- CoreGraphics ------------------------------------------------------------------
static int is_builtin(uint32_t d){return d==1;}
static int in_mirror_set(uint32_t d){return 0;}
static uint32_t vendor_number(uint32_t d){return 0x756e6b6e;} // kDisplayVendorIDUnknown
static uint32_t model_number(uint32_t d){return 0x717;}       // kDisplayProductIDGeneric
static uint32_t serial_number(uint32_t d){return 0;}
static int32_t active_displays(uint32_t max,uint32_t *displays,uint32_t *count){if(displays && max)displays[0]=1;if(count)*count=(max || !displays)?1:0;return 0;}
// The adapter's events never come from a hardware event source; the object
// exists so the guest can configure and release it.
static CFTypeRef event_source_create(int32_t state){return CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);}
static void event_source_suppression(CFTypeRef source,double seconds){}

// ---- IOKit -------------------------------------------------------------------------
static int32_t display_float_parameter(uint32_t service,uint32_t options,CFStringRef key,float *value){return (int32_t)0xe00002c7;} // kIOReturnUnsupported

// ---- Metal device list with observer (macOS-only API) ------------------------------
// iOS has one GPU and no hot-plug notifications: the observer is a token
// that never fires.
static id device_observer;
static NSArray *copy_devices_observer(id *observer,id handler) {
    if(observer){if(!device_observer)device_observer=[NSObject new];*observer=device_observer;}
    extern void *mp_cp_metal_devices(void);
    return (__bridge_transfer NSArray *)mp_cp_metal_devices();
}
static void remove_observer(id observer){}

// ---- libcurl (absent on iOS): an offline network --------------------------------------
// Behaves like libcurl on a machine without connectivity: initialisation and
// handles succeed, options are accepted, and every transfer completes with
// CURLE_COULDNT_CONNECT (7) — through curl_easy_perform or the multi
// interface's CURLMSG_DONE messages. Code written against real libcurl never
// sees a NULL handle or an empty header list.
#include <pthread.h>
#include <stdarg.h>
typedef struct {uint32_t magic;void *private_;char *url;} CurlEasy;
typedef struct {int msg;void *easy;union {void *whatever;int result;} data;} CurlMsg;  // CURLMsg
typedef struct {void *added[64];unsigned count;CurlMsg done[64];unsigned doneCount,doneRead;} CurlMulti;
struct curl_slist_ {char *data;struct curl_slist_ *next;};
static pthread_mutex_t curlLock=PTHREAD_MUTEX_INITIALIZER;
static int curl_ok(void){return 0;}
static void curl_void(void){}
static void *curl_easy_init_(void){CurlEasy *e=calloc(1,sizeof *e);e->magic=0xC0FFEE;return e;}
static void curl_easy_cleanup_(CurlEasy *e){if(e)free(e->url);free(e);}
// Variadic: the value is on the stack (8-byte slot for long, pointer or off_t).
// CURLOPT_PRIVATE (10103) and CURLOPT_URL (10002) are kept for getinfo.
static int curl_easy_setopt_(CurlEasy *e,int option,...) {
    if(!e)return 43;                                                           // CURLE_BAD_FUNCTION_ARGUMENT
    va_list ap;va_start(ap,option);void *value=va_arg(ap,void *);va_end(ap);
    if(option==10103)e->private_=value;
    if(option==10002){free(e->url);e->url=value?strdup(value):NULL;}
    return 0;
}
static int curl_easy_perform_(void *e){return 7;}                                // CURLE_COULDNT_CONNECT
// Variadic in libcurl: on arm64 Apple the trailing pointer is on the stack.
static int curl_easy_getinfo_(CurlEasy *e,int info,...) {
    va_list ap;va_start(ap,info);void **out=va_arg(ap,void **);va_end(ap);if(!out)return 43;
    if(info==0x100015)*out=e?e->private_:NULL;                                 // CURLINFO_PRIVATE
    else if(info==0x100001)*out=e?e->url:NULL;                                 // CURLINFO_EFFECTIVE_URL
    else *out=NULL;                                                            // long/double/off_t/char*: 8 zero bytes
    return 0;
}
static const char *curl_easy_strerror_(int code){return code==7?"Couldn't connect to server":code?"Network unavailable":"No error";}
static void *curl_multi_init_(void){return calloc(1,sizeof(CurlMulti));}
static int curl_multi_cleanup_(void *m){free(m);return 0;}
static int curl_multi_add_handle_(CurlMulti *m,void *e) {
    if(!m||!e)return 1;pthread_mutex_lock(&curlLock);
    if(m->count<64)m->added[m->count++]=e;
    if(m->doneCount<64)m->done[m->doneCount++]=(CurlMsg){1,e,{.result=7}};      // CURLMSG_DONE, CURLE_COULDNT_CONNECT
    pthread_mutex_unlock(&curlLock);return 0;
}
static int curl_multi_remove_handle_(CurlMulti *m,void *e) {
    if(!m)return 1;pthread_mutex_lock(&curlLock);
    for(unsigned i=0;i<m->count;i++)if(m->added[i]==e){m->added[i]=m->added[--m->count];break;}
    pthread_mutex_unlock(&curlLock);return 0;
}
static int curl_multi_perform_(CurlMulti *m,int *running){if(running)*running=0;return m?0:1;}
static CurlMsg *curl_multi_info_read_(CurlMulti *m,int *left) {
    CurlMsg *r=NULL;if(!m){if(left)*left=0;return NULL;}pthread_mutex_lock(&curlLock);
    if(m->doneRead<m->doneCount)r=&m->done[m->doneRead++];
    if(m->doneRead==m->doneCount){m->doneRead=m->doneCount=0;}   // Slots reused once drained.
    if(left)*left=(int)(m->doneCount-m->doneRead);
    pthread_mutex_unlock(&curlLock);return r;
}
static struct curl_slist_ *curl_slist_append_(struct curl_slist_ *list,const char *s) {
    struct curl_slist_ *n=calloc(1,sizeof *n);n->data=strdup(s?s:"");
    if(!list)return n;struct curl_slist_ *t=list;while(t->next)t=t->next;t->next=n;return list;
}
static void curl_slist_free_all_(struct curl_slist_ *l){while(l){struct curl_slist_ *n=l->next;free(l->data);free(l);l=n;}}

// ---- Security (macOS-only certificate APIs used by RED Galaxy) -----------------------
static int32_t sec_unimplemented(void){return -4;}         // errSecUnimplemented
static CFStringRef sec_long_description(CFAllocatorRef a,CFTypeRef cert,CFErrorRef *error){if(error)*error=NULL;return NULL;}

void *mp_cp_desktop_symbol(const char *library,const char *symbol) {
    if(strstr(library,"/AppKit.framework/"))for(unsigned i=0;i<9;i++)if(!strcmp(symbol+1,cpConstantNames[i].UTF8String)){cpConstantValues[i]=cpConstantNames[i];return &cpConstantValues[i];}
    static const struct {const char *name;void *function;} table[]={
        {"_CGDisplayIsBuiltin",(void *)is_builtin},{"_CGDisplayIsInMirrorSet",(void *)in_mirror_set},{"_CGDisplayVendorNumber",(void *)vendor_number},
        {"_CGDisplayModelNumber",(void *)model_number},{"_CGDisplaySerialNumber",(void *)serial_number},{"_CGGetActiveDisplayList",(void *)active_displays},
        {"_CGEventSourceCreate",(void *)event_source_create},{"_CGEventSourceSetLocalEventsSuppressionInterval",(void *)event_source_suppression},
        {"_IODisplayGetFloatParameter",(void *)display_float_parameter},
        {"_MTLCopyAllDevicesWithObserver",(void *)copy_devices_observer},{"_MTLRemoveDeviceObserver",(void *)remove_observer},
        {"_curl_global_init_mem",(void *)curl_ok},{"_curl_global_cleanup",(void *)curl_void},{"_curl_easy_init",(void *)curl_easy_init_},
        {"_curl_easy_cleanup",(void *)curl_easy_cleanup_},{"_curl_easy_setopt",(void *)curl_easy_setopt_},{"_curl_easy_getinfo",(void *)curl_easy_getinfo_},
        {"_curl_easy_perform",(void *)curl_easy_perform_},{"_curl_easy_strerror",(void *)curl_easy_strerror_},{"_curl_multi_init",(void *)curl_multi_init_},
        {"_curl_multi_cleanup",(void *)curl_multi_cleanup_},{"_curl_multi_add_handle",(void *)curl_multi_add_handle_},{"_curl_multi_remove_handle",(void *)curl_multi_remove_handle_},
        {"_curl_multi_perform",(void *)curl_multi_perform_},{"_curl_multi_info_read",(void *)curl_multi_info_read_},{"_curl_slist_append",(void *)curl_slist_append_},
        {"_curl_slist_free_all",(void *)curl_slist_free_all_},
        {"_SecItemImport",(void *)sec_unimplemented},{"_SecItemExport",(void *)sec_unimplemented},{"_SecIdentityCreateWithCertificate",(void *)sec_unimplemented},
        {"_SecCertificateCopyLongDescription",(void *)sec_long_description},
    };
    for(unsigned i=0;i<sizeof table/sizeof *table;i++)if(!strcmp(symbol,table[i].name))return table[i].function;
    return NULL;
}
