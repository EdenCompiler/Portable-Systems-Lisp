#include <assert.h>
#include <stdint.h>
#include <stdio.h>
uint64_t identity_c(uint64_t value) { return value * 3; }
extern uint64_t identity_qualified(uint64_t);
extern uint64_t identity_qualified_load(const volatile uint64_t *);
int main(void) {
    assert(identity_qualified(31) == 42);
    assert(identity_qualified(UINT64_MAX) == 10);
    volatile uint64_t word = 41;
    assert(identity_qualified_load(&word) == 42);
    puts("native reader identities resolve escaped names and package qualification");
    return 0;
}
