#include <stdint.h>

extern uint64_t masked_shift(uint64_t value, uint64_t count);
extern uint64_t answer(void);

int main(void) {
    if (answer() != 42) return 1;
    if (masked_shift(UINT64_C(0x2a00), 72) != 42) return 2;
    if (masked_shift(UINT64_MAX, 4) != UINT64_C(255)) return 3;
    if (masked_shift(UINT64_C(0x2a00), 9) != 21) return 4;
    return 0;
}
