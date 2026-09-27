#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern uint8_t fold_u8(void);
extern int8_t fold_s8(void), fold_bits(void);
extern uint16_t fold_u16(void);
extern int16_t fold_s16(void);
extern uint32_t fold_u32(void);
extern int32_t fold_s32(void);
extern uint64_t fold_u64(void), fold_cast(void), fold_signed_compare(void);
extern uint64_t fold_unsigned_compare(void), fold_equal(void);
extern uint64_t fold_shift64(void), fold_shift65(void), fold_shiftmax(void);
extern uint64_t fold_join(uint64_t), fold_boolean_join(uint64_t);
extern uint64_t fold_truth(uint64_t *), fold_null_truth(uint64_t *);
extern uint64_t fold_void_effect(uint64_t *), fold_loop(uint64_t *);

uint64_t optimizer_tick(uint64_t *counter) { ++*counter; return 0; }
void *optimizer_null(uint64_t *counter) { ++*counter; return 0; }
void optimizer_void(uint64_t *counter) { ++*counter; }

int main(void) {
    uint64_t counter = 0;
    assert(fold_u8() == 7 && fold_s8() == -127);
    assert(fold_u16() == UINT16_MAX - 1 && fold_s16() == INT16_MIN);
    assert(fold_u32() == 1 && fold_s32() == INT32_MAX);
    assert(fold_u64() == 42 && fold_cast() == UINT64_MAX);
    assert(fold_signed_compare() == 42 && fold_unsigned_compare() == 42 && fold_equal() == 42);
    assert(fold_bits() == INT8_MIN);
    assert(fold_shift64() == UINT64_MAX && fold_shift65() == UINT64_MAX / 2);
    assert(fold_shiftmax() == 1);
    assert(fold_join(0) == 42 && fold_join(1) == 42);
    assert(fold_boolean_join(0) == 42 && fold_boolean_join(1) == 42);
    assert(fold_truth(&counter) == 42 && counter == 1);
    assert(fold_null_truth(&counter) == 42 && counter == 2);
    assert(fold_void_effect(&counter) == 42 && counter == 3);
    assert(fold_loop(&counter) == 44 && counter == 44);
    puts("PSL optimizer widths, shifts, joins, truth, and effects passed");
    return 0;
}
