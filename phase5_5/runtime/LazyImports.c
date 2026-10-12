#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// Signed, precompiled lazy failure entries. They never report API success or
// return invented values: the first actual call names its missing import.
static struct { char library[256],symbol[256]; } imports[64];
static unsigned count;
_Noreturn static void unavailable(unsigned index) {
    fprintf(stderr,"MISSING LAZY IMPORT: %s from %s\n",imports[index].symbol,imports[index].library);
    abort();
}
#define ENTRIES(X) \
X(0) X(1) X(2) X(3) X(4) X(5) X(6) X(7) X(8) X(9) X(10) X(11) X(12) X(13) X(14) X(15) \
X(16) X(17) X(18) X(19) X(20) X(21) X(22) X(23) X(24) X(25) X(26) X(27) X(28) X(29) X(30) X(31) \
X(32) X(33) X(34) X(35) X(36) X(37) X(38) X(39) X(40) X(41) X(42) X(43) X(44) X(45) X(46) X(47) \
X(48) X(49) X(50) X(51) X(52) X(53) X(54) X(55) X(56) X(57) X(58) X(59) X(60) X(61) X(62) X(63)
#define DECLARE(N) _Noreturn static void missing_##N(void){unavailable(N);}
ENTRIES(DECLARE)
#define ADDRESS(N) missing_##N,
static void (*const entries[])(void)={ENTRIES(ADDRESS)};
void *mp_deferred_import(const char *library,const char *symbol) {
    for(unsigned i=0;i<count;i++)if(!strcmp(library,imports[i].library) && !strcmp(symbol,imports[i].symbol))return (void *)entries[i];
    if(count==64 || strlen(library)>=256 || strlen(symbol)>=256)return NULL;
    unsigned index=count++;strcpy(imports[index].library,library);strcpy(imports[index].symbol,symbol);
    fprintf(stderr,"DEFERRED UNSUPPORTED IMPORT: %s from %s\n",symbol,library);
    return (void *)entries[index];
}
