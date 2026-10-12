// macOS harness: load the unchanged SuperTuxKart executable and its 18
// shipped dylibs as one group with host frameworks, separating loader
// failures from iOS API differences. Usage: stk-load DIR [--run args...]
// where DIR holds supertuxkart and libs/*.dylib (thin arm64 slices).
#import <Foundation/Foundation.h>
#include "runtime.h"
#include <stdlib.h>
#include <dirent.h>
extern const MPExtensions *mp_stk_policy(void);
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc<2)return 2;
        int run=argc>=3 && !strcmp(argv[2],"--run");
        MPGuestSource sources[32];unsigned count=0;char *paths[32];
        asprintf(&paths[0],"%s/supertuxkart",argv[1]);sources[count++]=(MPGuestSource){.path=paths[0]};
        char libs[1024];snprintf(libs,sizeof libs,"%s/libs",argv[1]);
        DIR *d=opendir(libs);struct dirent *e;
        while(d && (e=readdir(d)) && count<32)if(strstr(e->d_name,".dylib")) {
            asprintf(&paths[count],"%s/%s",libs,e->d_name);sources[count]=(MPGuestSource){.path=paths[count]};count++;
        }
        if(d)closedir(d);
        char *guestArgv[64]={"supertuxkart"};int guestArgc=1;
        for(int i=3;run && i<argc && guestArgc<63;i++)guestArgv[guestArgc++]=argv[i];
        MPServices services={.extensions=mp_stk_policy(),.argc=guestArgc,.argv=guestArgv};
        char error[256];
        MPGroup *group=mp_group_open(sources,count,services,error);
        if(!group){fprintf(stderr,"GROUP: %s\n",error);return 1;}
        unsigned rebases=0,binds=0,selectors=0,inits=0;
        for(unsigned i=0;i<mp_group_count(group);i++){MPStats s=mp_image_stats(mp_group_image(group,i));rebases+=s.rebases;binds+=s.binds;selectors+=s.selectors;inits+=s.initializers;}
        fprintf(stderr,"GROUP LOADED: images=%u rebases=%u binds=%u selectors=%u initializers=%u\n",mp_group_count(group),rebases,binds,selectors,inits);
        if(!run)return 0;
        int result;
        return mp_image_main(mp_group_image(group,0),guestArgc,guestArgv,&result)?1:result;
    }
}
