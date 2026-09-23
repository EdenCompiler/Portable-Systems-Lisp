#include <stdint.h>

extern uint64_t call_increment(uint64_t);
extern uint8_t constant_wrap(void);
extern int8_t signed_wrap(void);
extern uint64_t signed_less(int8_t, int8_t);
extern uint64_t discard_pure(uint64_t);
extern uint64_t effect_probe(uint64_t);
extern uint8_t volatile_discard(volatile uint8_t *);

static uint64_t calls;
static uint64_t last_value;

uint64_t side_effect_c(uint64_t value) {
    ++calls;
    last_value = value;
    return 999;
}

int main(void) {
    volatile uint8_t status = 7;
    if (call_increment(41) != 42) return 1;
    if (constant_wrap() != 4) return 2;
    if (signed_wrap() != 116) return 3;
    if (signed_less(-3, 2) != 1) return 4;
    if (signed_less(2, -3) != 0) return 5;
    if (discard_pure(42) != 42) return 6;
    if (effect_probe(9) != 41 || calls != 1 || last_value != 9) return 7;
    if (effect_probe(10) != 12 || calls != 2 || last_value != 10) return 8;
    if (volatile_discard(&status) != 42) return 9;
    return 0;
}
