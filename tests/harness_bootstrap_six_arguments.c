#include <stdint.h>

extern uint64_t weighted_six(uint64_t a, uint64_t b, uint64_t c,
                             uint64_t d, uint64_t e, uint64_t f);
extern uint64_t nested_six(void);

int main(void) {
    return weighted_six(1, 2, 3, 4, 5, 6) == UINT64_C(654321)
        && weighted_six(6, 5, 4, 3, 2, 1) == UINT64_C(123456)
        && nested_six() == UINT64_C(654321) ? 0 : 1;
}
