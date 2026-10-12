#include <stdio.h>
extern int probe_a(void);
int main(void) { int n = probe_a(); printf("dependency chain: %d\n", n); return n == 42 ? 0 : 1; }
