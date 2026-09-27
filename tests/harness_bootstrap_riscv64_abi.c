#include <stdint.h>
#include <string.h>

extern uint32_t rv_u32_result(void);
extern uint64_t rv_u32_input(uint32_t);
extern uint64_t rv_check_register(void);
extern uint64_t rv_check_stack(void);
extern uint64_t rv_unaligned_roundtrip(uint8_t *);

/* Inspect actual register/stack bits before a C prologue can normalize them.
   Assembly belongs only to this independent ABI boundary test. */
__attribute__((naked)) uint32_t check_u32_register(uint32_t value __attribute__((unused))) {
    __asm__ volatile("li t0, -1\n\tbne a0, t0, 1f\n\tli a0, -128\n\tret\n"
                     "1: li a0, 0\n\tret");
}

__attribute__((naked)) uint32_t check_u32_stack(
    uint64_t a __attribute__((unused)), uint64_t b __attribute__((unused)),
    uint64_t c __attribute__((unused)), uint64_t d __attribute__((unused)),
    uint64_t e __attribute__((unused)), uint64_t f __attribute__((unused)),
    uint64_t g __attribute__((unused)), uint64_t h __attribute__((unused)),
    uint32_t value __attribute__((unused))) {
    __asm__ volatile("ld t1, 0(sp)\n\tli t0, -1\n\tbne t1, t0, 1f\n"
                     "li a0, -128\n\tret\n1: li a0, 0\n\tret");
}

static uint64_t raw_u32_return(void) {
    register uint64_t bits __asm__("a0");
    __asm__ volatile("call rv_u32_result" : "=r"(bits) : :
        "ra", "t0", "t1", "t2", "t3", "t4", "t5", "t6",
        "a1", "a2", "a3", "a4", "a5", "a6", "a7", "memory");
    return bits;
}

int main(void) {
    uint8_t bytes[10] = {0};
    uint64_t word;
    if (raw_u32_return() != UINT64_C(0xffffffff80000000)) return 1;
    if (rv_u32_result() != UINT32_C(0x80000000)) return 2;
    if (rv_u32_input(UINT32_MAX) != UINT64_C(0xffffffff)) return 3;
    if (rv_check_register() != UINT64_C(0xffffff80)) return 4;
    if (rv_check_stack() != UINT64_C(0xffffff80)) return 5;
    if (rv_unaligned_roundtrip(bytes) != UINT64_C(0xfedcba9876543210)) return 6;
    memcpy(&word, bytes + 1, sizeof word);
    if (word != UINT64_C(0xfedcba9876543210) || bytes[0] || bytes[9]) return 7;
    return 0;
}
