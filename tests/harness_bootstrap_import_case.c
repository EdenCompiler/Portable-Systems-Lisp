#include <assert.h>
#include <stdint.h>
#include <stdio.h>

uint64_t MixedCaseAdd(uint64_t value) { return value + 17; }
uint64_t call_mixed_case(uint64_t value);

int main(void) {
    assert(call_mixed_case(25) == 42);
    puts("PSL case-sensitive C import passed");
    return 0;
}
