#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t aux_answer(uint64_t),aux_nil(void),aux_rest(uint64_t);
int main(void) {
  const uint64_t values[]={0,4,UINT64_MAX};
  for(unsigned i=0;i<sizeof values/sizeof values[0];++i) {
    uint64_t value=values[i];
    assert(aux_answer(value)==value*4+10);
    assert(aux_rest(value)==value);
  }
  assert(aux_nil()==126);
  puts("macro auxiliary defaults, earlier bindings, optional/rest integration and NIL passed");
}
