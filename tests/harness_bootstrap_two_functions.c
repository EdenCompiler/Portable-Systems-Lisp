#include <stdint.h>

extern uint64_t answer(void);
extern uint64_t other_answer(void);

int main(void) {
    return answer() == 42 && other_answer() == 42 ? 0 : 1;
}
