#include "runtime.h"
const MPExtensions *mp_extended_policy(void);
void mp_extended_set_shim(void *(*shim)(const char *,const char *));
int mp_register_metadata(MPImage *,char error[256]);
