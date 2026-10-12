#include <mach-o/dyld.h>
#include <stdint.h>
#include <crt_externs.h>
#include <string.h>
__attribute__((weak,visibility("default"))) int weak_value=29;
int *weak_pointer=&weak_value;
static unsigned char ordinary_bss[65536];
int startup_ok;
__attribute__((constructor)) static void startup(void) {startup_ok=*_NSGetArgc()==2 && !strcmp((*_NSGetArgv())[1],"guest-argument");}
int tls_startup_check(void){int ok=startup_ok && *weak_pointer==29 && ordinary_bss[65535]==0;ordinary_bss[65535]=67;return ok;}
static _Thread_local int initialized=7;
static _Thread_local int zero;
static _Thread_local _Alignas(128) unsigned char aligned[128];
static _Thread_local void (*report)(int);
static void destroy(void *arg) {
    (void)arg;
    report(initialized+zero+aligned[0]);
}
__attribute__((visibility("default")))
int tls_step(int id,void (*callback)(int)) {
    if(!zero) {
        if(initialized!=7 || aligned[0] || (uintptr_t)aligned%128)return -100;
        report=callback;_tlv_atexit(destroy,0);
    }
    zero++;initialized+=id;aligned[0]++;
    return initialized+zero+aligned[0];
}
int main(void) {return 0;}
