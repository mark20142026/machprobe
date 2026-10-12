#include "guest_abi.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
typedef struct { MPHost host; MPState state; } Counter;
static int event(void *context, const MPEvent *input, MPState *result) {
    if (!context || !input || input->size != sizeof *input || !result) return -22;
    Counter *c=context;
    int64_t delta;
    switch(input->type) {
    case MP_INCREMENT: delta=1; break;
    case MP_DECREMENT: delta=-1; break;
    case MP_RESET: delta=0; break;
    default:return -22;
    }
    if (c->state.sequence==UINT64_MAX || (delta>0 && c->state.counter==INT64_MAX) ||
        (delta<0 && c->state.counter==INT64_MIN)) return -34;
    c->state.counter=input->type==MP_RESET?0:c->state.counter+delta;
    c->state.sequence++;
    *result=c->state;
    char text[80];snprintf(text,sizeof text,"Guest counter: %lld",(long long)c->state.counter);
    c->host.changed(c->host.context,c->state,text);
    return 0;
}
static void destroy(void *context) { free(context); }
int mp_guest_open(const MPHost *host, MPGuest *out) {
    if(!host || !out || host->size!=sizeof *host || host->version!=MP_ABI_VERSION ||
        out->size!=sizeof *out || !host->changed)return -22;
    Counter *c=calloc(1,sizeof *c);if(!c)return -12;c->host=*host;
    *out=(MPGuest){sizeof *out,MP_ABI_VERSION,c,event,destroy};
    host->changed(host->context,c->state,"Guest counter: 0");return 0;
}
int64_t abi_integer(int64_t a,int64_t b) { return a*7-b; }
MPState abi_struct(MPState in) { return (MPState){in.counter*2,in.sequence+3}; }
int abi_buffer(const char *in,char *out,size_t capacity) {
    if(!in || !out)return -22;size_t n=strlen(in);if(n+1>capacity)return -34;
    for(size_t i=0;i<n;i++)out[i]=in[n-i-1];out[n]=0;return (int)n;
}
int abi_callback(int value,int (*callback)(void *,int),void *context) { return callback(context,value+5)*2; }
long abi_variadic(int count,...) { va_list ap;va_start(ap,count);long n=0;for(int i=0;i<count;i++)n+=va_arg(ap,int);va_end(ap);return n; }
int abi_errno(int value) { errno=value;return errno; }
int *abi_errno_address(void) { return &errno; }
static int initialized;
__attribute__((constructor)) static void initialize(void) { initialized=73; }
int abi_initialized(void) { return initialized; }
int main(void) { puts("Interactive guest requires mp_guest_open ABI v1");return 0; }
