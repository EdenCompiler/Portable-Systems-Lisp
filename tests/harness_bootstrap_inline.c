#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern uint64_t inline_result(uint64_t, uint64_t *);
extern uint64_t inline_constant_case(void);
extern uint64_t inline_order(uint64_t *);
extern int8_t inline_narrow(int8_t);
extern int64_t inline_cast(uint64_t);
extern void *inline_pointer(uint64_t *);
extern uint64_t *inline_passthrough(uint64_t *);
extern uint64_t inline_many(uint64_t);
extern uint64_t inline_control(uint64_t, uint64_t *);
extern uint64_t inline_memory(uint64_t *);
extern uint64_t inline_recursive(uint64_t);

uint64_t inline_tick(uint64_t *state, uint64_t value) {
    *state = *state * 10 + value;
    return value;
}

int main(void) {
    uint64_t state = 0;
    assert(inline_result(5, &state) == 37 && state == 13);
    assert(inline_constant_case() == 17);
    state = 0;
    assert(inline_order(&state) == 42 && state == 12);
    assert(inline_narrow(120) == -116);
    assert(inline_narrow(-100) == -80);
    assert(inline_cast(255) == -1 && inline_cast(128) == -128);
    assert(inline_pointer(&state) == &state && inline_pointer(0) == 0);
    assert(inline_passthrough(&state) == &state && inline_passthrough(0) == 0);
    assert(inline_many(10) == 24);
    assert(inline_control(3, &state) == 10 && state == 3);
    assert(inline_control(8, &state) == 21 && state == 3);
    assert(inline_memory(&state) == 3 && inline_recursive(5) == 42);
    puts("PSL SSA inlining, argument order, types, and CFG references passed");
    return 0;
}
