#include <stdint.h>
#include <stddef.h>

extern uint8_t add_u8(uint8_t left, uint8_t right);
extern uint8_t zero_u8(void);
extern uint16_t multiply_u16(uint16_t left, uint16_t right);
extern uint32_t subtract_u32(uint32_t left, uint32_t right);
extern int8_t smaller_s8(int8_t left, int8_t right);
extern int8_t nested_s8(int8_t value);
extern int16_t add_s16(int16_t left, int16_t right);
extern int add_c_int(int left, int right);
extern int32_t smaller_s32(int32_t left, int32_t right);
extern int64_t negate_s64(int64_t value);
extern int64_t minimum_s64(void);
extern ptrdiff_t smaller_isize(ptrdiff_t left, ptrdiff_t right);

int main(void) {
    return add_u8(UINT8_MAX, 1) == 0
        && zero_u8() == 0
        && multiply_u16(32768, 2) == 0
        && subtract_u32(0, 1) == UINT32_MAX
        && smaller_s8(-128, 127) == -128
        && smaller_s8(127, -128) == -128
        && nested_s8(127) == -128
        && nested_s8(0) == -1
        && add_s16(INT16_MAX, 1) == INT16_MIN
        && add_c_int(INT32_MAX, 1) == INT32_MIN
        && smaller_s32(INT32_MIN, INT32_MAX) == INT32_MIN
        && negate_s64(INT64_MIN) == INT64_MIN
        && negate_s64(42) == -42
        && minimum_s64() == INT64_MIN
        && smaller_isize(-42, 7) == -42 ? 0 : 1;
}
