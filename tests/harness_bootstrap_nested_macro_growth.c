#include <stdint.h>
#ifndef EXPECTED
#error EXPECTED must be supplied by the focused test
#endif
uint64_t nested_result(void);
int main(void) { return nested_result() == (uint64_t)EXPECTED ? 0 : 1; }
