#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern uint64_t macro_let_parallel(uint64_t), macro_let_nested(uint64_t), macro_let_sequence(uint64_t);
extern uint64_t macro_let_empty_body(void), macro_let_empty_bindings(void), macro_let_default_nil(void), macro_let_nil_bindings(void);
int main(void) {
  assert(macro_let_parallel(8) == 11);
  assert(macro_let_parallel(0) == 3);
  assert(macro_let_nested(2) == 9);
  assert(macro_let_sequence(9) == 11);
  assert(macro_let_empty_body() == 2);
  assert(macro_let_empty_bindings() == 7);
  assert(macro_let_default_nil() == 3);
  assert(macro_let_nil_bindings() == 8);
  puts("build-host macro LET preserves parallel initializers, scope, empty bodies and NIL defaults");
}
