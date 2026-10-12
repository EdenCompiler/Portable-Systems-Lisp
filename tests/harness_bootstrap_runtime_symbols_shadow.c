#include <assert.h>
#include <stdint.h>
extern uint64_t shadow_result(void);
int main(void) {assert(shadow_result()==42);return 0;}
