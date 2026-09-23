#include <stdint.h>

extern uint64_t sum8_psl(uint64_t, uint64_t, uint64_t, uint64_t,
                         uint64_t, uint64_t, uint64_t, uint64_t);
extern uint64_t call_sum8_c(uint64_t, uint64_t, uint64_t, uint64_t,
                            uint64_t, uint64_t, uint64_t, uint64_t);
extern int64_t roundtrip_signed_stack(uint64_t, uint64_t, uint64_t,
                                      uint64_t, uint64_t, uint64_t, int8_t);

uint64_t sum8_c(uint64_t a, uint64_t b, uint64_t c, uint64_t d,
                uint64_t e, uint64_t f, uint64_t g, uint64_t h)
{
    return a + b + c + d + e + f + g + h;
}

int64_t signed_stack_c(uint64_t a, uint64_t b, uint64_t c,
                       uint64_t d, uint64_t e, uint64_t f, int8_t g)
{
    return (int64_t)(a + b + c + d + e + f) + g;
}

int main(void)
{
    if (sum8_psl(1, 2, 3, 4, 5, 6, 7, 8) != 36)
        return 1;
    if (call_sum8_c(1, 2, 3, 4, 5, 6, 7, 8) != 36)
        return 2;
    if (roundtrip_signed_stack(1, 2, 3, 4, 5, 6, -5) != 16)
        return 3;
    return 0;
}
