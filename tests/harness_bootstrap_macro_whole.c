#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t whole_answer(uint64_t),whole_empty(void);
int main(void) {
  assert(whole_answer(0)==84 && whole_answer(UINT64_MAX)==84);
  assert(whole_empty()==42);
  puts("whole invocation binding integrates with required/optional/rest/auxiliary macros");
}
