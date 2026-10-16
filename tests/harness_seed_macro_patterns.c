#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern uint64_t seed_empty_pattern(void);
extern uint64_t seed_nested_pattern(void);
extern uint64_t seed_key_pattern(void);
int main(void) {
    assert(seed_empty_pattern() == 19);
    assert(seed_nested_pattern() == 42);
    assert(seed_key_pattern() == 42);
    puts("seed macro validation preserves destructuring and explicit NIL key names");
}
