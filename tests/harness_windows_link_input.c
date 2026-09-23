#include <stdint.h>

extern uint64_t add42(uint64_t value);
extern int other_answer(void);

int main(void) {
    return add42(8) == 50 && other_answer() == 0 ? 0 : 1;
}
