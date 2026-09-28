#include <stdint.h>

extern uint64_t test_answer(void);
uint64_t foreign_return_42(void) { return 42; }
int main(void) { return test_answer() == 42 ? 0 : 1; }
