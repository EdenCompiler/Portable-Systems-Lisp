#include <assert.h>
#include <stdint.h>
#include <stdio.h>

extern uint64_t cl_user_value(uint64_t);

int main(void) {
    static const uint64_t inputs[] = {0, 1, UINT64_C(0x123456789abcdef0), UINT64_MAX - 9};
    for (size_t i = 0; i < sizeof inputs / sizeof inputs[0]; ++i)
        assert(cl_user_value(inputs[i]) == inputs[i] + 7);
    puts("CL-USER source package identity and CL visibility execute correctly");
    return 0;
}
