#include "runtime.h"
#include "guest_abi.h"
#include "../host/checks.h"
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
typedef struct { MPState last; unsigned calls; char text[80]; } Observer;
static void changed(void *context,MPState state,const char *text) {
 Observer *o=context;o->last=state;o->calls++;snprintf(o->text,sizeof o->text,"%s",text);
}
static int callback(void *ctx,int n) {return *(int *)ctx+n;}
static void *symbol(MPImage *i,const char *n){void *p=mp_image_symbol(i,n);if(!p)fprintf(stderr,"%s\n",mp_image_error(i));assert(p);return p;}
typedef struct {int (*set)(int);int *(*address)(void);int *pointer;int value;} ThreadProbe;
// macOS has no pthread_barrier; mutex-free independence is checked after joins.
static void *thread_probe(void *p) {ThreadProbe *t=p;t->pointer=t->address();assert(t->set(t->value)==t->value);assert(errno==t->value);return NULL;}
static int open_descriptors(void) {
 int n=0;for(int fd=0;fd<256;fd++)if(fcntl(fd,F_GETFD)!=-1)n++;return n;
}
int main(int argc,char **argv) {
 assert(argc==2 || argc==3);char error[256];
 const char *valid="METAL_RESULT count=16 values=7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52 checksum=472\n";
 assert(mp_check_compute_output(valid));assert(!mp_check_compute_output(NULL));
 char corrupt[256];snprintf(corrupt,sizeof corrupt,"%s",valid);char *value=strstr(corrupt,"values=")+7;*value='8';assert(!mp_check_compute_output(corrupt));
 assert(!mp_check_compute_output("Metal compute passed"));assert(!mp_check_compute_output("METAL_RESULT count=16 values=7,10"));
 assert(mp_live_images()==0);assert(!mp_image_open(NULL,(MPServices){0},error));assert(mp_live_images()==0);
 int descriptor_baseline=open_descriptors();
 for(int cycle=0;cycle<40;cycle++) {
 if(argc==3){assert(!mp_image_open(argv[2],(MPServices){0},error));assert(strstr(error,"unsupported import"));assert(open_descriptors()==descriptor_baseline);assert(mp_live_images()==0);}
 MPImage *image=mp_image_open(argv[1],(MPServices){0},error);if(!image)fprintf(stderr,"%s\n",error);assert(image);
 assert(mp_live_images()==1);MPStats stats=mp_image_stats(image);assert(stats.signature_registered && stats.library_validation_passed && stats.initializers==1);
 int (*initialized)(void)=symbol(image,"_abi_initialized");assert(initialized()==73);
 MPOpenGuest open=symbol(image,"_mp_guest_open");Observer a={0},b={0};
 MPHost host={sizeof host,MP_ABI_VERSION,&a,changed};MPGuest guest={.size=sizeof guest};
 assert(open(&host,&guest)==0);assert(a.calls==1 && a.last.counter==0 && a.last.sequence==0);
 MPState state={0};MPEvent input={sizeof input,MP_INCREMENT,0};
 int types[]={MP_INCREMENT,MP_INCREMENT,MP_DECREMENT,MP_RESET,MP_DECREMENT};int expected[]={1,2,1,0,-1};
 for(unsigned j=0;j<5;j++){input.type=types[j];assert(guest.event(guest.context,&input,&state)==0);assert(state.counter==expected[j]);assert(state.sequence==j+1);assert(a.last.counter==state.counter && a.last.sequence==state.sequence);}
 assert(a.calls==6 && !strcmp(a.text,"Guest counter: -1"));
 input.type=999;assert(guest.event(guest.context,&input,&state)==-22);assert(a.calls==6);
 input.size=0;assert(guest.event(guest.context,&input,&state)==-22);assert(guest.event(guest.context,NULL,&state)==-22);
 host.context=&b;MPGuest other={.size=sizeof other};assert(open(&host,&other)==0);assert(b.last.counter==0);other.destroy(other.context);
 host.version=99;other.size=sizeof other;assert(open(&host,&other)==-22);
 guest.destroy(guest.context);
 int64_t (*integer)(int64_t,int64_t)=symbol(image,"_abi_integer");assert(integer(-12,9)==-93);assert(integer(0x100000001,3)==0x700000004);
 MPState (*structure)(MPState)=symbol(image,"_abi_struct");MPState out=structure((MPState){-8,0x100000000});assert(out.counter==-16 && out.sequence==0x100000003);
 int (*buffer)(const char *,char *,size_t)=symbol(image,"_abi_buffer");char data[16];memset(data,0x55,sizeof data);assert(buffer("ARM64",data,sizeof data)==5 && !strcmp(data,"46MRA"));assert(buffer("abcdef",data,3)==-34);assert(buffer(NULL,data,16)==-22);
 int (*cb)(int,int (*)(void *,int),void *)=symbol(image,"_abi_callback");int context=11;assert(cb(7,callback,&context)==46);
 long (*variadic)(int,...)=symbol(image,"_abi_variadic");assert(variadic(5,1,-2,30,4,100)==133);
 int (*seterr)(int)=symbol(image,"_abi_errno");int *(*address)(void)=symbol(image,"_abi_errno_address");
 errno=27;assert(address()==&errno);assert(seterr(41)==41 && errno==41);
 ThreadProbe probes[2]={{.set=seterr,.address=address,.value=64},{.set=seterr,.address=address,.value=65}};pthread_t threads[2];
 for(int k=0;k<2;k++)assert(!pthread_create(&threads[k],NULL,thread_probe,&probes[k]));
 for(int k=0;k<2;k++)assert(!pthread_join(threads[k],NULL));assert(errno==41);
 assert(!mp_image_symbol(image,"_missing"));
 // Query actual VM permissions rather than trusting the loader's counters.
 mach_vm_address_t region=(mach_vm_address_t)integer;mach_vm_size_t length=0;vm_region_basic_info_data_64_t info;mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;mach_port_t object;
 assert(mach_vm_region(mach_task_self(),&region,&length,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&count,&object)==KERN_SUCCESS);
 if(object)mach_port_deallocate(mach_task_self(),object);
 assert((info.protection&VM_PROT_EXECUTE) && !(info.protection&VM_PROT_WRITE));
 uintptr_t guest_page=(uintptr_t)integer & ~((uintptr_t)sysconf(_SC_PAGESIZE)-1);
 mp_image_close(image);assert(mp_live_images()==0);
 region=guest_page;count=VM_REGION_BASIC_INFO_COUNT_64;object=0;
 kern_return_t kr=mach_vm_region(mach_task_self(),&region,&length,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&count,&object);
 if(object)mach_port_deallocate(mach_task_self(),object);
 assert(kr==KERN_INVALID_ADDRESS || (kr==KERN_SUCCESS && region>guest_page));
 assert(open_descriptors()==descriptor_baseline);
 }
 puts("ABI_OK integer pointer buffer struct callback errors variadic errno_threads init input isolation cleanup cycles=40");return 0;
}
