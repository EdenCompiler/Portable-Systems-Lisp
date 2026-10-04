#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t declarations_answer(uint64_t), declarations_nil(void);
int main(void) {
  const uint64_t values[]={0,4,UINT64_MAX};
  for(unsigned i=0;i<sizeof values/sizeof values[0];++i)
    assert(declarations_answer(values[i])==values[i]*6+3);
  assert(declarations_nil()==42);
  puts("macro declaration prefixes, documentation, defaults and empty bodies passed");
}
