#include "runtime.h"
#include <stdio.h>
#include <string.h>
static void output(void *ctx,const char *s,size_t n){(void)ctx;fwrite(s,1,n,stdout);}
int main(int argc,char **argv) {
 if(argc<2)return 2;
 char error[256];MPImage *image=mp_image_open(argv[1],(MPServices){NULL,output},error);
 if(!image){fprintf(stderr,"LOAD ERROR: %s\n",error);return 1;}
 int result=-1;int status=mp_image_main(image,argc-1,argv+1,&result);
 MPStats s=mp_image_stats(image);
 fprintf(stderr,"runtime: segments=%u rebases=%u binds=%u selectors=%u initializers=%u guest_return=%d\n",s.segments,s.rebases,s.binds,s.selectors,s.initializers,result);
 mp_image_close(image);return status?1:result;
}
