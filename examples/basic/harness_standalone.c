#include <stdint.h>

extern uint64_t add42(uint64_t);

int main(void)
{
    return add42(8) == 50 ? 0 : 1;
}
