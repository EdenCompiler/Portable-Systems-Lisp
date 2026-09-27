#include <stdint.h>

extern uint64_t answer(void);
uint64_t unit_c(uint64_t number) { return number + 2; }
int main(void) { return answer() == 42 ? 0 : 1; }
