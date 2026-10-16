#include <stdint.h>
#include <assert.h>
#include <stdio.h>
extern uint64_t nil_key_values(void);
int main(void) {
  assert(nil_key_values() == 119);
  puts("explicit NIL macro key names accept NIL and () with lazy defaults");
}
