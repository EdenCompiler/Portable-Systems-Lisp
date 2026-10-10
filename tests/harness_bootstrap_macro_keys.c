#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t keys_defaults(uint64_t),keys_rest(uint64_t),keys_optional(uint64_t),keys_symbols(uint64_t);
extern uint64_t keys_allow(void),keys_order(void),keys_truth(void),keys_whole(void);
int main(void) {
  const uint64_t values[]={0,4,UINT64_MAX};
  for(unsigned i=0;i<sizeof values/sizeof values[0];++i) {
    assert(keys_defaults(values[i])==values[i]*3+23);
    assert(keys_rest(values[i])==values[i]*2+10);
    assert(keys_optional(values[i])==values[i]*3+23);
    assert(keys_symbols(values[i])==values[i]*2+42);
  }
  assert(keys_allow()==57);
  assert(keys_order()==10);
  assert(keys_truth()==48);
  assert(keys_whole()==52);
  puts("macro keyword defaults, supplied flags, rest/optional/aux, explicit names and allow-other-keys passed");
}
