#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern uint64_t build_time_eval_when_value(void);
extern uint64_t build_time_eval_when_redefined(void);
int main(void) {
  assert(build_time_eval_when_value() == 42);
  assert(build_time_eval_when_redefined() == 12);
  puts("compile-toplevel eval-when registers build-host macros");
}
