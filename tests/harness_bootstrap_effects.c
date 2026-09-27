#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern uint64_t effect_region(uint64_t *), effect_outer_binding(uint64_t *);
extern uint64_t effect_loop(uint64_t *), effect_nested(uint64_t *), effect_discarded(uint64_t *);
extern uint64_t *effect_pointer_case(uint64_t *);
extern void effect_void_case(uint64_t *);
uint64_t effect_tick(uint64_t *counter) { return ++*counter; }
uint64_t effect_unknown(uint64_t *counter) { *counter += 100; return *counter; }
void effect_void(uint64_t *counter) { ++*counter; }
uint64_t *effect_pointer(uint64_t *counter) { return counter; }

int main(void) {
    uint64_t counter = 0;
    assert(effect_region(&counter) == 43 && counter == 43);
    assert(effect_outer_binding(&counter) == 143 && counter == 143);
    assert(effect_loop(&counter) == 3 && counter == 3);
    effect_void_case(&counter);
    assert(counter == 4);
    assert(effect_pointer_case(&counter) == &counter);
    assert(effect_pointer_case(NULL) == NULL);
    assert(effect_nested(&counter) == 6 && counter == 5);
    assert(effect_discarded(&counter) == 42 && counter == 6);
    puts("PSL allocation regions, recursive summaries, and retained effects passed");
    return 0;
}
