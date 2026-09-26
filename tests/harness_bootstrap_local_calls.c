#include <stdint.h>

extern uint64_t helper(void);
extern uint64_t direct(void);
extern uint64_t answer(void);

int main(void) {
    return helper() == 20 && direct() == 20 && answer() == 42 ? 0 : 1;
}
