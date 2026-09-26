#include <stdint.h>

extern uint8_t narrow_byte(uint64_t value);
extern int64_t widen_signed(int8_t value);
extern uint64_t signed_to_unsigned(int32_t value);
extern int8_t cast_literal(void);
extern uint8_t positive_flag(int32_t value);
extern uint8_t integer_truth(void);
extern uint8_t boolean_choice(int32_t value);
extern uint64_t lexical_mix(int8_t value, uint64_t other);
extern int64_t mixed_six(uint8_t a, int8_t b, uint16_t c,
                         int16_t d, uint32_t e, int32_t f);
extern int64_t nested_mixed(void);

int main(void) {
    const int64_t sum = INT64_C(255) - 128 + 65535 - 32768
                      + UINT32_MAX + INT32_MIN;
    return narrow_byte(258) == 2
        && widen_signed(-128) == -128
        && signed_to_unsigned(-1) == UINT64_MAX
        && cast_literal() == -128
        && positive_flag(-1) == 0 && positive_flag(1) == 1
        && integer_truth() == 1
        && boolean_choice(-1) == 1 && boolean_choice(1) == 2
        && lexical_mix(-2, 258) == 0
        && lexical_mix(-2, 257) == UINT64_MAX
        && lexical_mix(3, 258) == 2
        && mixed_six(255, -128, 65535, -32768, UINT32_MAX, INT32_MIN) == sum
        && nested_mixed() == sum ? 0 : 1;
}
