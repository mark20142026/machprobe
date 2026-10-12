#include "loader.h"
#include <stdio.h>
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    MPHelloResult r;
    if(mp_run_hello(argv[1],&r)) { fprintf(stderr,"Loader failed: %s\n",r.error);return 1; }
    printf("%sTarget returned: %d\nMapped segments: %u; rebases: %u; binds: %u; puts calls: %u\n",
           r.output,r.target_return,r.mapped_segments,r.rebases,r.binds,r.puts_calls);
    return r.target_return;
}
