#include <stdint.h>

extern uint64_t add_then_multiply(uint64_t left, uint64_t right);

int main(void) {
    return add_then_multiply(4, 5) == 27 ? 0 : 1;
}
