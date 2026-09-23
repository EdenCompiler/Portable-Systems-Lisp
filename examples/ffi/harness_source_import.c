#include <stdint.h>

extern uint64_t scale_then_add(uint64_t);

int main(void) {
    return scale_then_add(20) == 42 ? 0 : 1;
}
