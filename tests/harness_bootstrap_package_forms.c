#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern uint64_t package_value(uint64_t);
extern uint64_t package_default(uint64_t);
extern uint64_t package_include(uint64_t);
extern uint64_t package_after_include(uint64_t);
int main(void) {
    const uint64_t inputs[] = {0, 1, 31, UINT64_MAX - 3, UINT64_MAX};
    for (unsigned i = 0; i < sizeof inputs / sizeof *inputs; ++i) {
        assert(package_value(inputs[i]) == inputs[i] + 11);
        assert(package_default(inputs[i]) == inputs[i] + 12);
        assert(package_include(inputs[i]) == inputs[i] + 5);
        assert(package_after_include(inputs[i]) == inputs[i] + 10);
    }
    puts("ordered source package imports, nicknames and includes execute correctly");
}
