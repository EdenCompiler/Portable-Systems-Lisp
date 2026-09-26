#include <stdint.h>

extern uint64_t weighted_eight(uint64_t, uint64_t, uint64_t, uint64_t,
                               uint64_t, uint64_t, uint64_t, uint64_t);
extern uint64_t seventh_argument(uint64_t, uint64_t, uint64_t, uint64_t,
                                 uint64_t, uint64_t, uint64_t);
extern int64_t mixed_stack(uint64_t, uint64_t, uint64_t, uint64_t,
                           uint64_t, uint64_t, int8_t, uint16_t, int32_t *);
extern uint64_t ordered_eight(uint64_t *);
extern uint64_t nested_stack(void);
extern int64_t call_mixed_stack(int32_t *);
extern uint64_t recursive_eight(uint64_t, uint64_t, uint64_t, uint64_t,
                                uint64_t, uint64_t, uint64_t, uint64_t);

int main(void) {
    uint64_t counter = 0;
    int32_t negative = -70000;
    if (weighted_eight(1, 2, 3, 4, 5, 6, 7, 8) != UINT64_C(87654321)) return 1;
    if (weighted_eight(8, 7, 6, 5, 4, 3, 2, 1) != UINT64_C(12345678)) return 2;
    if (seventh_argument(1, 2, 3, 4, 5, 6, UINT64_MAX) != UINT64_MAX) return 3;
    if (mixed_stack(1, 2, 3, 4, 5, 6, -128, 65535, &negative) != -4593) return 4;
    if (ordered_eight(&counter) != UINT64_C(87654321) || counter != 8) return 5;
    if (nested_stack() != UINT64_C(87654321)) return 6;
    if (call_mixed_stack(&negative) != -4593) return 7;
    if (recursive_eight(25, 2, 3, 4, 5, 6, 7, 8) != UINT64_C(87654321)) return 8;
    return 0;
}
