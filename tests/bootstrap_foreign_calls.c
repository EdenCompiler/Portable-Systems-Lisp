#include <stdint.h>

/* Inspect the ABI stack alignment at an imported boundary. Assembly is
   confined to this test provider; PSL encodes its own instructions. */
#if defined(__aarch64__)
static uint64_t entry_alignment(void) {
    uintptr_t stack;
    __asm__ volatile("mov %0, sp" : "=r"(stack));
    return stack & 15;
}
#define EXPECTED_ALIGNMENT 0
#else
__attribute__((naked)) static uint64_t entry_alignment(void) {
    __asm__ volatile("mov %rsp, %rax\n\tand $15, %rax\n\tret");
}
#define EXPECTED_ALIGNMENT 8
#endif

uint64_t foreign_seven(uint64_t a, uint64_t b, uint64_t c, uint64_t d,
                        uint64_t e, uint64_t f, uint64_t g) {
    if (entry_alignment() != EXPECTED_ALIGNMENT) return UINT64_MAX;
    return a + 10*b + 100*c + 1000*d + 10000*e + 100000*f + 1000000*g;
}

uint64_t foreign_eight(uint64_t a, uint64_t b, uint64_t c, uint64_t d,
                        uint64_t e, uint64_t f, uint64_t g, uint64_t h) {
    if (entry_alignment() != EXPECTED_ALIGNMENT) return UINT64_MAX;
    return a + 10*b + 100*c + 1000*d + 10000*e + 100000*f + 1000000*g + 10000000*h;
}

int8_t foreign_narrow(int8_t a, uint16_t b) {
    return a == -128 && b == 65535 ? -7 : 99;
}

int32_t *foreign_pointer(int32_t *input, uintptr_t offset) {
    return input + offset;
}

int32_t foreign_integer_zero(void) { return 0; }
int32_t *foreign_pointer_zero(void) { return (int32_t *)0; }
