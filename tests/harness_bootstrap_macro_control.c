#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t control_answer(uint64_t),control_lazy(void),control_false(void),control_syntax_truth(void);
int main(void) {
  const uint64_t values[]={0,4,UINT64_MAX};
  for(unsigned i=0;i<sizeof values/sizeof values[0];++i) assert(control_answer(values[i])==values[i]*2+10);
  assert(control_lazy()==94 && control_false()==42 && control_syntax_truth()==42);
  puts("build-host macro IF preserves zero truth, NIL falsehood and lazy branch evaluation");
}
