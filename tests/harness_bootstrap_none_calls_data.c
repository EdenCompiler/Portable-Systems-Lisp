#include <stdint.h>
#include <stdio.h>
uint64_t none_bias = 4;
extern uint64_t none_seed;
extern uint64_t none_answer(uint64_t);
uint64_t none_adjust(uint64_t number) { return number * 2; }
int main(void) {
    if (none_seed != 7 || none_answer(10) != 42) return 1;
    none_seed = 9;
    none_bias = 1;
    if (none_answer(10) != 40) return 2;
    puts("None-target internal/imported calls and writable data preserve the C ABI");
    return 0;
}
