#include <stdint.h>
extern uint64_t native_cli_answer(void);
int main(void) { return native_cli_answer() == 42 ? 0 : 1; }
