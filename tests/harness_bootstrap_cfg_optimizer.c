#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern uint64_t prune_true(uint64_t, uint64_t *), prune_false(uint64_t *);
extern uint64_t prune_signed(uint64_t *), prune_nested(uint64_t, uint64_t *);
extern uint64_t prune_cascade(uint64_t *), prune_pointer(uint64_t *);
extern uint64_t prune_boolean(uint64_t, uint64_t *), prune_loop(uint64_t *);
extern void prune_void(uint64_t *);

uint64_t cfg_live(uint64_t *counter) { ++*counter; return 42; }
uint64_t cfg_dead(uint64_t *counter) { (void)counter; assert(!"unreachable call executed"); return 0; }
void cfg_void(uint64_t *counter) { ++*counter; }

int main(void) {
    uint64_t counter = 0;
    assert(prune_true(41, &counter) == 42 && counter == 0);
    assert(prune_true(UINT64_MAX, &counter) == 0 && counter == 0);
    assert(prune_false(&counter) == 42 && counter == 1);
    assert(prune_signed(&counter) == 42 && counter == 2);
    assert(prune_nested(41, &counter) == 7 && counter == 2);
    assert(prune_nested(UINT64_MAX, &counter) == 1 && counter == 2);
    assert(prune_cascade(&counter) == 42 && counter == 3);
    assert(prune_pointer(&counter) == 3);
    assert(prune_boolean(0, &counter) == 3 && counter == 3);
    assert(prune_boolean(1, &counter) == 42 && counter == 4);
    assert(prune_loop(&counter) == 42 && counter == 4);
    prune_void(&counter);
    assert(counter == 5);
    puts("PSL CFG branches, repaired joins, cycles, and effects passed");
    return 0;
}
