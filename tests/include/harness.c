#include <stdint.h>

extern uint64_t included_call(uint64_t value);

int main(void) {
    return included_call(39) == 42 ? 0 : 1;
}
