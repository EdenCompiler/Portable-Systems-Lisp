#include <stdint.h>

extern uint64_t answer(void);

int main(void) {
    return answer() == 42 ? 0 : 1;
}
