#include <stdint.h>

uint64_t c_counter = 41;
uint32_t MixedCaseData = UINT32_C(0x89abcdef);

extern uint64_t read_counter(void);
extern uint64_t increment_counter(void);
extern uint32_t read_mixed_case_data(void);

int main(void) {
    if (read_counter() != 41) return 1;
    if (increment_counter() != 42 || c_counter != 42) return 2;
    if (read_mixed_case_data() != UINT32_C(0x89abcdef)) return 3;
    return 0;
}
