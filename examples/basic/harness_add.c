#include <stdint.h>

extern uint64_t add(uint64_t, uint64_t);
extern uint64_t add_then_multiply(uint64_t, uint64_t);
extern uint64_t choose_and_double(uint64_t, uint64_t);
extern uint64_t subtract(uint64_t, uint64_t);
extern int64_t signed_min(int64_t, int64_t);
extern uint64_t zero_is_true(void);
extern uint64_t nil_is_false(void);
extern uint64_t nested_choice(uint64_t, uint64_t);
extern uint64_t let_is_parallel(uint64_t);
extern uint64_t reader_radix(void);

uint64_t multiply_c(uint64_t a, uint64_t b) { return a * b; }

int main(void) {
    if (add(40, 2) != 42) return 1;
    if (add_then_multiply(12, 2) != 42) return 2;
    if (choose_and_double(19, 21) != 42) return 3;
    if (choose_and_double(21, 19) != 42) return 4;
    if (subtract(1, 2) != UINT64_MAX) return 5;
    if (signed_min(-3, 7) != -3) return 6;
    if (zero_is_true() != 42) return 7;
    if (nil_is_false() != 42) return 8;
    if (nested_choice(19, 21) != 42) return 9;
    if (nested_choice(21, 19) != 0) return 10;
    if (let_is_parallel(41) != 42) return 11;
    if (reader_radix() != 42) return 12;
    return 0;
}
