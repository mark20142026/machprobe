#import <Foundation/Foundation.h>
#include "Extended.h"
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc<2)return 2;
        char error[256];MPServices services={.extensions=mp_extended_policy()};
        MPImage *image=mp_image_open(argv[1],services,error);
        if(!image){fprintf(stderr,"LOAD: %s\n",error);return 1;}
        MPStats stats=mp_image_stats(image);fprintf(stderr,"LOADED: rebases=%u binds=%u selectors=%u\n",stats.rebases,stats.binds,stats.selectors);
        if(!mp_register_metadata(image,error)){fprintf(stderr,"METADATA: %s\n",error);return 1;}
        fprintf(stderr,"METADATA: registered (process lifetime)\n");
        if(argc==3 && !strcmp(argv[2],"--run")){int result;return mp_image_main(image,1,argv+1,&result)?1:result;}
        return 0;
    }
}
