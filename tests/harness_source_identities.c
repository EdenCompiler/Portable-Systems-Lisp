#include <stdint.h>
#include <assert.h>
uint64_t source_identity_mix(uint64_t,uint64_t,uint64_t);
uint64_t source_identity_shadow(uint64_t);
int main(void) {
  assert(source_identity_mix(1,2,3)==321);
  assert(source_identity_shadow(10)==27);
  return 0;
}
