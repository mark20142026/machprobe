#include "checks.h"
#include <stdlib.h>
#include <string.h>
int mp_check_compute_output(const char *text) {
 const char prefix[]="METAL_RESULT count=16 values=";
 if(!text)return 0;const char *p=strstr(text,prefix);if(!p)return 0;
 // Exact delimiter parsing prevents a success label from substituting for data.
 p+=sizeof prefix-1;
 for(int i=0;i<16;i++) {char *end;long n=strtol(p,&end,10);if(end==p || n!=i*3+7)return 0;
  if(i<15){if(*end!=',')return 0;p=end+1;}else p=end;}
 return !strcmp(p," checksum=472\n");
}
