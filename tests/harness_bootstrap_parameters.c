#include <stdint.h>

extern uint64_t add(uint64_t a, uint64_t b);
extern uint64_t double_value(uint64_t value);

int main(void) {
    return add(20, 22) == 42 && double_value(21) == 42 ? 0 : 1;
}
