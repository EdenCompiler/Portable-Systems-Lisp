#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t nil_key_shape(void);
extern uint64_t nil_key_redefined(void);
int main(void) {
  assert(nil_key_shape() == 37);
  assert(nil_key_redefined() == 8);
  puts("explicit NIL key bridge preserves original whole and rest forms");
}
