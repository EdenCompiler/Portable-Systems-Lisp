#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t sequence_answer(uint64_t),sequence_nil(void),sequence_defaults(uint64_t);
int main(void) {
  const uint64_t values[]={0,4,UINT64_MAX};
  for(unsigned i=0;i<sizeof values/sizeof values[0];++i) {
    assert(sequence_answer(values[i])==values[i]*3);
    assert(sequence_defaults(values[i])==values[i]*2+3);
  }
  assert(sequence_nil()==84);
  puts("macro implicit/explicit sequencing, nesting, empty bodies and defaults passed");
}
