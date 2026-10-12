#include "runtime.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#define CHECK(x) do {if(!(x)){fprintf(stderr,"CHECK failed line %d: %s\n",__LINE__,#x);abort();}}while(0)
static _Atomic int destroyed,total;
static int (*step)(int,void (*)(int));
static void report(int value){atomic_fetch_add(&destroyed,1);atomic_fetch_add(&total,value);}
static void *worker(void *arg){int id=(int)(intptr_t)arg;CHECK(step(id,report)==9+id);CHECK(step(id,report)==11+2*id);return NULL;}
static void *resolve(const char *lib,const char *sym){(void)lib;return sym[0]=='_'?dlsym(RTLD_DEFAULT,sym+1):NULL;}
int main(int argc,char **argv){
    CHECK(argc==2);
    const char *container=getenv("MP_CONTAINER");void *resident=NULL;size_t size=0;
    unsigned char *original=NULL;
    if(container) {
        CHECK(dlopen(container,RTLD_NOW|RTLD_LOCAL));
        for(unsigned i=0;i<_dyld_image_count();i++)if(!strcmp(container,_dyld_get_image_name(i))) {
            unsigned long n;resident=getsectiondata((const struct mach_header_64 *)_dyld_get_image_header(i),"__TEXT","__guest",&n);
        }
        CHECK(resident);FILE *f=fopen(argv[1],"rb");CHECK(f);fseek(f,0,SEEK_END);size=ftell(f);rewind(f);
        original=malloc(size);CHECK(original);CHECK(fread(original,1,size,f)==size);fclose(f);
    }
    MPExtensions policy={.allow_thread_locals=1,.allow_weak_coalescing=1,.resolve=resolve};
    for(int run=0;run<12;run++) {
        char *args[]={"tls-guest","guest-argument",NULL};
        char error[256];MPServices services={.extensions=&policy,.argc=2,.argv=args};
        if(container)CHECK(!memcmp(resident,original,size));
        MPImage *im=container?mp_image_open_embedded(container,"__TEXT",resident,size,services,error):mp_image_open(argv[1],services,error);
        if(!im){fprintf(stderr,"%s\n",error);return 1;}
        int (*check)(void)=mp_image_symbol(im,"_tls_startup_check");CHECK(check && check());
        step=mp_image_symbol(im,"_tls_step");CHECK(step);
        pthread_t threads[24];
        for(int i=0;i<24;i++)CHECK(!pthread_create(&threads[i],NULL,worker,(void *)(intptr_t)(i+1)));
        for(int i=0;i<24;i++)CHECK(!pthread_join(threads[i],NULL));
        mp_image_close(im);CHECK(mp_live_images()==0);
        if(container)CHECK(!memcmp(resident,original,size));
    }
    CHECK(destroyed==288);CHECK(total==12*(24*11+2*300));
    free(original);
    puts("TLS initialized/zero/aligned state, 288 workers, destructors and 12 unloads verified");
}
