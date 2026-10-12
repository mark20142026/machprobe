#import <Foundation/Foundation.h>
#include "Extended.h"
#include "Policy.h"
#include <stdlib.h>
extern const MPExtensions *mp_large_game_policy(void);
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc<2)return 2;
        MPExtensions policy=*mp_large_game_policy();
        const char *limit=getenv("MP_IMAGE_LIMIT");
        if(limit)policy.max_image_bytes=strtoull(limit,NULL,10);
        int run=argc>=3 && !strcmp(argv[2],"--run");
        char *path=argv[1];
        if(run)argv[2]=path;
        char error[256];MPServices services={.extensions=&policy,.argc=run?argc-2:1,.argv=run?argv+2:argv+1};
        MPImage *image=mp_image_open(argv[1],services,error);
        if(!image){fprintf(stderr,"LOAD: %s\n",error);return 1;}
        MPStats stats=mp_image_stats(image);fprintf(stderr,"LOADED: rebases=%u binds=%u selectors=%u\n",stats.rebases,stats.binds,stats.selectors);
        if(!mp_register_metadata(image,error)){fprintf(stderr,"METADATA: %s\n",error);return 1;}
        fprintf(stderr,"METADATA: registered (process lifetime)\n");
        if(run){
            int result;
            return mp_image_main(image,services.argc,services.argv,&result)?1:result;
        }
        return 0;
    }
}
