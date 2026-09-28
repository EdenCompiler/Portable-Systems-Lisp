#include <stdint.h>

extern int64_t eleven_values(uint64_t, uint64_t, uint64_t, uint64_t,
    uint64_t, uint64_t, uint64_t, uint64_t, int8_t, uint16_t, int32_t *);
extern int64_t call_eleven(uint64_t *, int32_t *);

int64_t foreign_eleven(uint64_t a, uint64_t b, uint64_t c, uint64_t d,
    uint64_t e, uint64_t f, uint64_t g, uint64_t h, int8_t i, uint16_t j, int32_t *p) {
    uintptr_t stack;
#if defined(__riscv)
    __asm__ volatile("mv %0, sp" : "=r"(stack));
#elif defined(__x86_64__)
    __asm__ volatile("mov %%rsp, %0" : "=r"(stack));
#else
    __asm__ volatile("mov %0, sp" : "=r"(stack));
#endif
    if ((stack & 15) || a != 1 || b != 2 || c != 3 || d != 4 ||
        e != 5 || f != 6 || g != 7 || h != 8 || i != -128 || j != 65535)
        return INT64_MIN;
    /* Also call back into PSL with three stack arguments. */
    return eleven_values(a, b, c, d, e, f, g, h, i, j, p);
}

int main(void) {
    int32_t value = -70000;
    uint64_t counter = 0;
    if (eleven_values(1, 2, 3, 4, 5, 6, 7, 8, -128, 65535, &value) != -4557) return 1;
    if (call_eleven(&counter, &value) != -4557 || counter != 8) return 2;
    return 0;
}
